package com.teapodstream.teapodstream

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.system.OsConstants
import androidx.core.app.NotificationCompat
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import teapodcore.Teapodcore
import teapodcore.XrayCallback
import teapodcore.TunValidator
import teapodcore.VpnProtector

class XrayVpnService : VpnService() {

    companion object {
        init {
            System.loadLibrary("vpnhelper")
        }

        @JvmStatic external fun nativeSetMaxFds(maxFds: Int): Int
        const val ACTION_CONNECT = "com.teapodstream.CONNECT"
        const val ACTION_DISCONNECT = "com.teapodstream.DISCONNECT"
        const val ACTION_CONNECT_QUICK = "com.teapodstream.CONNECT_QUICK" // reconnect from notification
        const val EXTRA_XRAY_CONFIG = "xray_config"
        const val EXTRA_SOCKS_PORT = "socks_port"
        const val EXTRA_SOCKS_USER = "socks_user"
        const val EXTRA_SOCKS_PASSWORD = "socks_password"
        const val EXTRA_EXCLUDED_PACKAGES = "excluded_packages"
        const val EXTRA_INCLUDED_PACKAGES = "included_packages"
        const val EXTRA_VPN_MODE = "vpn_mode"
        const val EXTRA_SS_PREFIX = "ss_prefix" // hex-encoded Outline prefix bytes
        const val EXTRA_PROXY_ONLY = "proxy_only" // start only SOCKS proxy, no VPN tunnel
        const val EXTRA_SHOW_NOTIFICATION = "show_notification" // show rich notification with speed
        const val EXTRA_KILL_SWITCH = "kill_switch" // block traffic when VPN drops unexpectedly

        // Static state tracker for querying from Dart
        @Volatile private var currentNativeState: String = "disconnected"
        @JvmStatic fun getNativeState(): String = currentNativeState

        // Set true on explicit user disconnect, false on connect — guards reconnectInternal()
        val userRequestedDisconnect = AtomicBoolean(false)

        // Active SOCKS credentials — stored so onListen can replay them with "connected"
        @Volatile var activeSocksPort: Int = 0
            private set
        @Volatile var activeSocksUser: String = ""
            private set
        @Volatile var activeSocksPassword: String = ""
            private set

        @JvmStatic fun getSocksCredentials(): Map<String, Any> = mapOf(
            "port" to activeSocksPort,
            "user" to activeSocksUser,
            "password" to activeSocksPassword
        )

        private const val NOTIFICATION_CHANNEL_ID = "vpn_service"
        private const val NOTIFICATION_CHANNEL_MINIMAL_ID = "vpn_service_minimal"
        private const val NOTIFICATION_ID = 1

        @Volatile private var totalUpload: Long = 0
        @Volatile private var totalDownload: Long = 0
        @Volatile private var lastUploadSpeed: Long = 0
        @Volatile private var lastDownloadSpeed: Long = 0

        fun getStats(): Map<String, Long> = mapOf(
            "upload" to totalUpload,
            "download" to totalDownload,
            "uploadSpeed" to lastUploadSpeed,
            "downloadSpeed" to lastDownloadSpeed,
        )

        @JvmStatic fun showIntermediateNotification(context: android.content.Context, isConnecting: Boolean) {
            try {
                val manager = context.getSystemService(android.content.Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                ensureNotificationChannel(manager)
                val text = if (isConnecting) "Подключение…" else "Отключение…"
                val notification = androidx.core.app.NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
                    .setContentTitle("TeapodStream VPN")
                    .setContentText(text)
                    .setSmallIcon(android.R.drawable.ic_lock_lock)
                    .setOngoing(true)
                    .setPriority(androidx.core.app.NotificationCompat.PRIORITY_LOW)
                    .setProgress(0, 0, true)
                    .build()
                manager.notify(NOTIFICATION_ID, notification)
            } catch (_: Exception) { }
        }

        private fun ensureNotificationChannel(manager: android.app.NotificationManager) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.createNotificationChannel(
                    android.app.NotificationChannel(NOTIFICATION_CHANNEL_ID, "VPN статус", android.app.NotificationManager.IMPORTANCE_LOW)
                )
            }
        }

        fun prepareBinaries(context: android.content.Context): Boolean {
            val filesDir = context.filesDir
            val assets = context.assets
            val assetsToCopy = listOf("geoip.dat", "geosite.dat")
            for (name in assetsToCopy) {
                val file = java.io.File(filesDir, name)
                if (file.exists()) continue
                try {
                    val input = try { assets.open("binaries/$name") } catch (e: Exception) { assets.open("flutter_assets/assets/binaries/$name") }
                    input.use { i -> file.outputStream().use { o -> i.copyTo(o) } }
                } catch (e: Exception) { }
            }
            return true
        }
    }

    private var tunInterface: ParcelFileDescriptor? = null
    private var statsThread: Thread? = null
    private val isRunning = AtomicBoolean(false)
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    @Volatile private var lastUnderlyingNetwork: Network? = null
    private var prefixProxy: PrefixTcpProxy? = null
    private var showNotification = true
    private var wakeLock: PowerManager.WakeLock? = null
    private var killSwitchEnabled = false
    private var proxyOnlyMode = false
    private val networkChangeHandler = Handler(Looper.getMainLooper())
    private var pendingNetworkRunnable: Runnable? = null
    private var heartbeatThread: Thread? = null
    private val heartbeatFailures = AtomicInteger(0)

    // TUN parameters — always the same fixed values; defined once here to avoid
    // scattering magic strings across the file. The Dart side uses the same constants
    // (AppConstants.tunAddress / tunNetmask / tunMtu / tunDns).
    private val tunAddress = "10.120.230.1"
    private val tunNetmask = "255.255.255.0"
    private val tunMtu    = 1500
    private val tunDns    = "1.1.1.1"

    override fun onCreate() {
        super.onCreate()
        // Контекст для обновления Quick Settings плитки
        VpnEventStreamHandler.appContext = applicationContext
        migrateConnectionParamsIfNeeded()
        Teapodcore.registerVpnProtector(object : VpnProtector {
            override fun protect(fd: Long): Boolean {
                val result = this@XrayVpnService.protect(fd.toInt())
                android.util.Log.i("TeapodVPN", "[protect] fd=$fd result=$result")
                return result
            }
        })
    }

    private fun migrateConnectionParamsIfNeeded() {
        val oldFile = File(filesDir, "last_connection.json")
        if (!oldFile.exists()) return
        try {
            val json = org.json.JSONObject(oldFile.readText())
            val meta = org.json.JSONObject().apply {
                put("socksPort", json.optInt("socksPort", 10808))
                put("excludedPackages", json.optJSONArray("excludedPackages") ?: org.json.JSONArray())
                put("includedPackages", json.optJSONArray("includedPackages") ?: org.json.JSONArray())
                put("vpnMode", json.optString("vpnMode", "allExcept"))
                val ssPrefix = json.optString("ssPrefix")
                if (ssPrefix.isNotEmpty()) put("ssPrefix", ssPrefix)
                put("proxyOnly", json.optBoolean("proxyOnly", false))
                put("showNotification", json.optBoolean("showNotification", true))
                put("killSwitch", json.optBoolean("killSwitch", false))
            }
            File(filesDir, "last_connection_meta.json").writeText(meta.toString())
        } catch (_: Exception) { }
        oldFile.delete()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_DISCONNECT -> {
                userRequestedDisconnect.set(true)
                // Signal disconnecting immediately so the button turns yellow
                // even when triggered from the notification (no Flutter-side handler).
                currentNativeState = "disconnecting"
                VpnEventStreamHandler.sendStateEvent("disconnecting")

                // Run cleanup off the main thread — Go calls (stopTun2Socks/stopXray)
                // can block if goroutines are stuck after long uptime or network changes.
                Thread {
                    val stopThread = Thread { stopVpn(explicit = true) }
                    stopThread.start()
                    try {
                        stopThread.join(5000) // safety timeout — wait max 5s for движок to stop
                        if (stopThread.isAlive) {
                            log("warning", "stopVpn timed out after 5s, forcing disconnected state")
                        }
                    } catch (e: InterruptedException) {
                        Thread.currentThread().interrupt()
                    }

                    // Guarantee "disconnected" is always sent
                    currentNativeState = "disconnected"
                    VpnEventStreamHandler.sendStateEvent("disconnected")
                    // Update notification to "Disconnected" ONLY after we've actually
                    // finished (or timed out) the stopping process.
                    showDisconnectedNotification()
                }.start()
                return START_STICKY
            }
            ACTION_CONNECT -> {
                showNotification = intent.getBooleanExtra(EXTRA_SHOW_NOTIFICATION, true)
                val xrayConfig = intent.getStringExtra(EXTRA_XRAY_CONFIG) ?: ""
                val socksPort = intent.getIntExtra(EXTRA_SOCKS_PORT, 10808)
                val socksUser = intent.getStringExtra(EXTRA_SOCKS_USER) ?: ""
                val socksPassword = intent.getStringExtra(EXTRA_SOCKS_PASSWORD) ?: ""
                val excludedPackages = intent.getStringArrayListExtra(EXTRA_EXCLUDED_PACKAGES) ?: arrayListOf()
                val includedPackages = intent.getStringArrayListExtra(EXTRA_INCLUDED_PACKAGES) ?: arrayListOf()
                val vpnMode = intent.getStringExtra(EXTRA_VPN_MODE) ?: "allExcept"
                val ssPrefix = intent.getStringExtra(EXTRA_SS_PREFIX)
                val proxyOnly = intent.getBooleanExtra(EXTRA_PROXY_ONLY, false)
                val killSwitch = intent.getBooleanExtra(EXTRA_KILL_SWITCH, false)
                // Persist non-sensitive params for CONNECT_QUICK reconnect (no credentials)
                saveConnectionParams(socksPort, excludedPackages, includedPackages,
                    vpnMode, ssPrefix, proxyOnly, showNotification, killSwitch)
                userRequestedDisconnect.set(false)
                ensureForeground()
                Thread {
                    startVpn(xrayConfig, socksPort, socksUser, socksPassword,
                        excludedPackages, includedPackages, vpnMode, ssPrefix, proxyOnly, killSwitch)
                }.start()
                return START_STICKY
            }
            ACTION_CONNECT_QUICK -> {
                ensureForeground()
                val params = loadConnectionParams()
                val configFile = File(filesDir, "xray_config.json")
                if (params != null && configFile.exists()) {
                    showNotification = params.showNotification
                    val needsPermission = !params.proxyOnly && VpnService.prepare(this) != null
                    if (needsPermission) {
                        openApp()
                    } else {
                        userRequestedDisconnect.set(false)
                        currentNativeState = "connecting"
                        VpnEventStreamHandler.sendStateEvent("connecting")
                        val configText = configFile.readText()
                        // Extract SOCKS credentials from the saved xray config instead of storing them
                        val (socksUser, socksPassword) = extractSocksFromConfig(configText)
                        Thread {
                            startVpn(
                                configText,
                                params.socksPort, socksUser, socksPassword,
                                params.excludedPackages, params.includedPackages, params.vpnMode,
                                params.ssPrefix, params.proxyOnly, params.killSwitch
                            )
                        }.start()
                    }
                } else {
                    openApp()
                }
                return START_STICKY
            }
        }
        // Service restarted by Android after being killed — must call startForeground() first
        // (Android 8+ requires startForeground within 5s of startForegroundService)
        ensureForeground()
        showDisconnectedNotification()
        return START_STICKY
    }

    // ---- Connection-params persistence ----

    private data class ConnectionParams(
        val socksPort: Int,
        val excludedPackages: List<String>,
        val includedPackages: List<String>,
        val vpnMode: String,
        val ssPrefix: String?,
        val proxyOnly: Boolean,
        val showNotification: Boolean,
        val killSwitch: Boolean,
    )

    private fun saveConnectionParams(
        socksPort: Int,
        excludedPackages: List<String>, includedPackages: List<String>,
        vpnMode: String, ssPrefix: String?, proxyOnly: Boolean, showNotification: Boolean,
        killSwitch: Boolean,
    ) {
        try {
            val json = org.json.JSONObject().apply {
                put("socksPort", socksPort)
                put("excludedPackages", org.json.JSONArray(excludedPackages))
                put("includedPackages", org.json.JSONArray(includedPackages))
                put("vpnMode", vpnMode)
                if (ssPrefix != null) put("ssPrefix", ssPrefix)
                put("proxyOnly", proxyOnly)
                put("showNotification", showNotification)
                put("killSwitch", killSwitch)
            }
            File(filesDir, "last_connection_meta.json").writeText(json.toString())
        } catch (e: Exception) {
            log("warning", "Failed to save connection params: ${e.message}")
        }
    }

    private fun loadConnectionParams(): ConnectionParams? {
        return try {
            val text = File(filesDir, "last_connection_meta.json").readText()
            val json = org.json.JSONObject(text)
            val excluded = json.getJSONArray("excludedPackages")
                .let { arr -> List(arr.length()) { arr.getString(it) } }
            val included = json.getJSONArray("includedPackages")
                .let { arr -> List(arr.length()) { arr.getString(it) } }
            ConnectionParams(
                socksPort = json.getInt("socksPort"),
                excludedPackages = excluded,
                includedPackages = included,
                vpnMode = json.optString("vpnMode", "allExcept"),
                ssPrefix = json.optString("ssPrefix").takeIf { it.isNotEmpty() },
                proxyOnly = json.optBoolean("proxyOnly", false),
                showNotification = json.optBoolean("showNotification", true),
                killSwitch = json.optBoolean("killSwitch", false),
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun extractSocksFromConfig(configJson: String): Pair<String, String> {
        return try {
            val inbounds = org.json.JSONObject(configJson).getJSONArray("inbounds")
            for (i in 0 until inbounds.length()) {
                val inbound = inbounds.getJSONObject(i)
                if (inbound.optString("tag") == "socks-in") {
                    val accounts = inbound.optJSONObject("settings")
                        ?.optJSONArray("accounts") ?: continue
                    if (accounts.length() > 0) {
                        val acc = accounts.getJSONObject(0)
                        return acc.optString("user", "") to acc.optString("pass", "")
                    }
                }
            }
            "" to ""
        } catch (_: Exception) {
            "" to ""
        }
    }

    private fun openApp() {
        packageManager.getLaunchIntentForPackage(packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ?.let { startActivity(it) }
    }

    private fun startVpn(
        xrayConfig: String,
        socksPort: Int,
        socksUser: String,
        socksPassword: String,
        excludedPackages: List<String>,
        includedPackages: List<String>,
        vpnMode: String,
        ssPrefix: String? = null,
        proxyOnly: Boolean = false,
        killSwitch: Boolean = false,
    ) {
        if (!isRunning.compareAndSet(false, true)) return
        // Close any TUN left open by a previous kill-switch blocking state
        try { tunInterface?.close() } catch (_: Exception) {}
        tunInterface = null
        killSwitchEnabled = killSwitch
        proxyOnlyMode = proxyOnly
        currentNativeState = "connecting"
        VpnEventStreamHandler.sendStateEvent("connecting")
        log("info", "Starting VPN")

        try {
            // Enable prefix proxy only when the ss:// URL contains ?prefix=.
            val finalConfig = if (ssPrefix != null) {
                injectPrefixProxy(xrayConfig, ssPrefix) ?: xrayConfig
            } else {
                xrayConfig
            }

            val configFile = File(filesDir, "xray_config.json")
            configFile.writeText(finalConfig)
            prepareBinaries(this)

            // Set up xray asset path before starting
            Teapodcore.initCoreEnv(filesDir.absolutePath, "")

            if (proxyOnly) {
                // Proxy-only mode: start Xray SOCKS proxy without TUN tunnel or tun2socks
                log("info", "Proxy-only mode: skipping TUN tunnel")

                startXrayAndWait(finalConfig)

                log("info", "xray started (proxy-only, SOCKS on port $socksPort)")
                startStatsMonitoring()
                acquireWakeLock()
                currentNativeState = "connected"
                activeSocksPort = socksPort
                activeSocksUser = socksUser
                activeSocksPassword = socksPassword
                VpnEventStreamHandler.sendConnectedEvent(socksPort, socksUser, socksPassword)
                startHeartbeat()
                log("info", "Proxy-only mode active")
            } else {
                // Full VPN tunnel mode
                val builder = Builder()
                    .setSession("TeapodStream")
                    .setMtu(tunMtu)
                    .addAddress(tunAddress, subnetMaskToPrefix(tunNetmask))
                    .addRoute("0.0.0.0", 0)
                    .addDnsServer(tunDns)
                    .allowFamily(OsConstants.AF_INET)
                    .setBlocking(true)
                    .setMetered(false)

                // On Android 8+, set underlying networks for better routing
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val connectivityManager = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
                    val activeNetwork = connectivityManager.activeNetwork
                    if (activeNetwork != null) {
                        builder.setUnderlyingNetworks(arrayOf(activeNetwork))
                        log("info", "Underlying network set: $activeNetwork")
                    }
                }

                // Apply split tunneling based on VPN mode
                if (vpnMode == "onlySelected") {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        for (pkg in includedPackages) {
                            try {
                                builder.addAllowedApplication(pkg)
                                log("info", "Allowed: $pkg")
                            } catch (e: Exception) {
                                log("warning", "Failed to allow $pkg: ${e.message}")
                            }
                        }
                    } else {
                        log("warning", "onlySelected mode requires Android 10+, falling back to allExcept")
                        for (pkg in excludedPackages) {
                            try { builder.addDisallowedApplication(pkg) } catch (_: Exception) {}
                        }
                        try { builder.addDisallowedApplication(packageName) } catch (_: Exception) {}
                    }
                } else {
                    for (pkg in excludedPackages) {
                        try { builder.addDisallowedApplication(pkg) } catch (_: Exception) {}
                    }
                    try { builder.addDisallowedApplication(packageName) } catch (_: Exception) {}
                }

                val fdResult = nativeSetMaxFds(65536)
                log("info", "nativeSetMaxFds result: $fdResult")

                tunInterface = builder.establish() ?: throw IllegalStateException("Failed to establish TUN")
                log("info", "TUN established")

                // 1. Start xray-core (in-process library, not subprocess)
                startXrayAndWait(finalConfig)
                log("info", "xray started")

                // 2. Resolve UIDs for split tunneling (tun2socks validator level)
                val allowedUids = resolveUids(vpnMode, includedPackages, excludedPackages)
                val validator = buildTunValidator(allowedUids, vpnMode)

                log("info", "Starting tun2socks: mode=$vpnMode uids=${allowedUids.size}")

                val tunErr = Teapodcore.startTun2Socks(
                    tunInterface!!.fd.toLong(),
                    tunMtu.toLong(),
                    socksPort.toLong(),
                    socksUser,
                    socksPassword,
                    validator
                )
                if (tunErr.isNotEmpty()) throw IllegalStateException("tun2socks: $tunErr")

                log("info", "tun2socks started successfully")

                startStatsMonitoring()
                registerNetworkCallback()
                acquireWakeLock()
                currentNativeState = "connected"
                activeSocksPort = socksPort
                activeSocksUser = socksUser
                activeSocksPassword = socksPassword
                VpnEventStreamHandler.sendConnectedEvent(socksPort, socksUser, socksPassword)
                startHeartbeat()
                log("info", "VPN connected successfully")
            }
        } catch (e: Exception) {
            log("error", "Start failed: ${e.message}")
            stopVpn(resultState = "error")
        }
    }

    /**
     * Starts xray-core and blocks until it reports ready or fails (max 3 s).
     * Throws IllegalStateException if xray reports an error status.
     */
    private fun startXrayAndWait(config: String) {
        val ready = AtomicBoolean(false)
        val failed = AtomicBoolean(false)

        Teapodcore.startXray(config, object : XrayCallback {
            override fun onStatus(status: Long, message: String) {
                log("info", "[xray] $message")
                if (status == 0L) ready.set(true) else failed.set(true)
            }
        })

        val deadline = System.currentTimeMillis() + 3000
        while (!ready.get() && !failed.get() && System.currentTimeMillis() < deadline) {
            Thread.sleep(50)
        }
        if (failed.get()) throw IllegalStateException("xray failed to start")
        if (!ready.get()) throw IllegalStateException("xray start timeout (3s)")
    }

    /**
     * Resolves UIDs for the given package lists based on vpnMode.
     * In "onlySelected" mode returns allowed UIDs; otherwise returns excluded UIDs
     * (including the app's own UID to prevent routing loops).
     */
    private fun resolveUids(
        vpnMode: String,
        includedPackages: List<String>,
        excludedPackages: List<String>,
    ): Set<Int> {
        val uids = mutableSetOf<Int>()
        val packages = if (vpnMode == "onlySelected") includedPackages else excludedPackages
        for (pkg in packages) {
            try {
                val uid = packageManager.getPackageUid(pkg, PackageManager.GET_META_DATA)
                uids.add(uid)
                log("info", "${if (vpnMode == "onlySelected") "Allowed" else "Excluded"} UID for $pkg: $uid")
            } catch (e: Exception) {
                log("warning", "Failed to get UID for $pkg: ${e.message}")
            }
        }
        if (vpnMode != "onlySelected") {
            // Always exclude own app to prevent routing loops at tun2socks level
            try {
                val uid = packageManager.getPackageUid(packageName, PackageManager.GET_META_DATA)
                uids.add(uid)
                log("info", "Excluded own UID ($packageName): $uid")
            } catch (e: Exception) {
                log("warning", "Failed to get own UID: ${e.message}")
            }
        }
        return uids
    }

    /**
     * Builds a TunValidator that enforces split tunneling using
     * ConnectivityManager.getConnectionOwnerUid (requires API 29+).
     */
    private fun buildTunValidator(allowedUids: Set<Int>, vpnMode: String): TunValidator {
        if (allowedUids.isEmpty()) {
            // No UID filtering — allow everything
            return object : TunValidator {
                override fun onValidate(srcIP: String, srcPort: Long, dstIP: String, dstPort: Long, protocol: Long) = true
            }
        }
        val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
        return object : TunValidator {
            override fun onValidate(srcIP: String, srcPort: Long, dstIP: String, dstPort: Long, protocol: Long): Boolean {
                return try {
                    val uid = cm.getConnectionOwnerUid(
                        protocol.toInt(),
                        InetSocketAddress(srcIP, srcPort.toInt()),
                        InetSocketAddress(dstIP, dstPort.toInt())
                    )
                    if (vpnMode == "onlySelected") uid in allowedUids else uid !in allowedUids
                } catch (_: Exception) {
                    true // allow on lookup failure
                }
            }
        }
    }

    /**
     * Parses [xrayConfig] JSON, finds the first proxy Shadowsocks server address,
     * starts a [PrefixTcpProxy] that sends [prefixHex] bytes before forwarding,
     * and returns a modified config pointing Xray to the local proxy.
     */
    private fun injectPrefixProxy(xrayConfig: String, prefixHex: String): String? {
        return try {
            val prefixBytes = prefixHex.chunked(2)
                .map { it.toInt(16).toByte() }
                .toByteArray()

            val json = org.json.JSONObject(xrayConfig)
            val outbounds = json.getJSONArray("outbounds")
            var proxyOutbound: org.json.JSONObject? = null
            for (i in 0 until outbounds.length()) {
                val ob = outbounds.getJSONObject(i)
                if (ob.optString("tag") == "proxy") { proxyOutbound = ob; break }
            }
            if (proxyOutbound == null) return null

            val settings = proxyOutbound.getJSONObject("settings")
            val servers = settings.getJSONArray("servers")
            val server = servers.getJSONObject(0)
            val realHost = server.getString("address")
            val realPort = server.getInt("port")

            val proxy = PrefixTcpProxy(realHost, realPort, prefixBytes)
            proxy.start()
            prefixProxy = proxy

            // Redirect Xray to the local proxy
            server.put("address", "127.0.0.1")
            server.put("port", proxy.localPort)

            log("info", "Prefix proxy: 127.0.0.1:${proxy.localPort} → $realHost:$realPort (${prefixBytes.size} prefix bytes)")
            json.toString()
        } catch (e: Exception) {
            log("warning", "Failed to start prefix proxy: ${e.message}")
            null
        }
    }

    override fun onRevoke() {
        // Вызывается Android, когда VPN отключен извне (системные настройки, другой VPN)
        log("info", "VPN revoked by system")
        stopVpn()
        stopSelf()
    }

    private fun acquireWakeLock() {
        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            wakeLock?.release()
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "TeapodStream:VpnWakeLock")
            wakeLock?.acquire()
        } catch (e: Exception) {
            log("warning", "Failed to acquire wake lock: ${e.message}")
        }
    }

    private fun stopVpn(
        resultState: String = "disconnected",
        explicit: Boolean = false,
        reconnecting: Boolean = false,
    ) {
        if (!isRunning.compareAndSet(true, false)) return  // idempotent — safe to call multiple times
        stopHeartbeat()
        lastUnderlyingNetwork = null
        pendingNetworkRunnable?.let { networkChangeHandler.removeCallbacks(it) }
        pendingNetworkRunnable = null

        try { wakeLock?.release() } catch (_: Exception) {}
        wakeLock = null

        try {
            try { unregisterNetworkCallback() } catch (e: Exception) {
                log("warning", "unregisterNetworkCallback failed: ${e.message}")
            }

            statsThread?.let {
                try { it.interrupt() } catch (e: Exception) {
                    log("warning", "statsThread.interrupt failed: ${e.message}")
                }
            }
            statsThread = null

            try { prefixProxy?.stop() } catch (e: Exception) {
                log("warning", "prefixProxy.stop failed: ${e.message}")
            }
            prefixProxy = null

            try { Teapodcore.stopTun2Socks() } catch (e: Exception) {
                log("warning", "stopTun2Socks failed: ${e.message}")
            }

            try { Teapodcore.stopXray() } catch (e: Exception) {
                log("warning", "stopXray failed: ${e.message}")
            }

            // Kill switch: on unexpected drop (non-explicit, non-reconnect), keep TUN open so
            // all traffic is routed to the TUN but nobody reads it → effectively blocked.
            // setUnderlyingNetworks(emptyArray) signals Android there is no real network.
            val activateKillSwitch = killSwitchEnabled && !explicit && !reconnecting && !proxyOnlyMode
                    && tunInterface != null
                    && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
            if (activateKillSwitch) {
                setUnderlyingNetworks(emptyArray())
                log("info", "Kill switch active: TUN kept open, underlying networks cleared")
            } else {
                try {
                    tunInterface?.close()
                } catch (e: Exception) {
                    log("warning", "tunInterface.close failed: ${e.message}")
                }
                tunInterface = null
            }

            // Keep xray_config.json for Quick Settings tile reconnect.
            // File is in process-private filesDir, not accessible to other apps.
            // if (explicit && !reconnecting) {
            //     try { File(filesDir, "xray_config.json").delete() } catch (_: Exception) {}
            // }
        } finally {
            // Don't overwrite "connecting" state when doing internal reconnect
            if (!reconnecting) {
                currentNativeState = resultState
                VpnEventStreamHandler.sendStateEvent(resultState)
            }
        }
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }

    private fun startStatsMonitoring() {
        var lastUp = 0L
        var lastDown = 0L
        var lastTime = System.currentTimeMillis()

        totalUpload = 0
        totalDownload = 0
        lastUploadSpeed = 0
        lastDownloadSpeed = 0

        statsThread = Thread {
            while (isRunning.get()) {
                try {
                    Thread.sleep(1000)
                    val now = System.currentTimeMillis()
                    val elapsed = (now - lastTime) / 1000.0

                    val currentTx = Teapodcore.getTunUploadBytes()
                    val currentRx = Teapodcore.getTunDownloadBytes()

                    totalUpload = currentTx
                    totalDownload = currentRx

                    if (elapsed > 0) {
                        lastUploadSpeed = ((currentTx - lastUp) / elapsed).toLong().coerceAtLeast(0)
                        lastDownloadSpeed = ((currentRx - lastDown) / elapsed).toLong().coerceAtLeast(0)
                    }
                    lastUp = totalUpload
                    lastDown = totalDownload
                    lastTime = now
                    VpnEventStreamHandler.sendStatsEvent(totalUpload, totalDownload, lastUploadSpeed, lastDownloadSpeed)
                    updateNotification(lastUploadSpeed, lastDownloadSpeed)
                } catch (_: InterruptedException) { break } catch (_: Exception) {}
            }
        }.also { it.isDaemon = true; it.start() }
    }

    private fun registerNetworkCallback() {
        try {
            val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
            // Pre-seed lastUnderlyingNetwork before registering so the initial onAvailable
            // callback sees prev == current and does NOT trigger a spurious reconnect.
            updateUnderlyingNetworks(cm)
            networkCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    log("info", "Network available: $network")
                    val prev = lastUnderlyingNetwork
                    updateUnderlyingNetworks(cm)
                    val current = lastUnderlyingNetwork
                    // Trigger if network changed (prev→current) OR if prev was null but we now
                    // have a network (covers WiFi→LTE when onLost fired before onAvailable).
                    if (current != null && prev != current) {
                        scheduleNetworkChanged()
                    }
                }

                override fun onLost(network: Network) {
                    log("info", "Network lost: $network")
                    // Snapshot BEFORE clearing — needed for smooth-handover case where
                    // onAvailable(LTE) fires before onLost(WiFi): prev=wifi, after=LTE → trigger.
                    val prev = lastUnderlyingNetwork
                    if (lastUnderlyingNetwork == network) {
                        lastUnderlyingNetwork = null
                    }
                    updateUnderlyingNetworks(cm)
                    if (prev != null && lastUnderlyingNetwork != null && prev != lastUnderlyingNetwork) {
                        scheduleNetworkChanged()
                    }
                }

                override fun onCapabilitiesChanged(
                    network: Network,
                    networkCapabilities: NetworkCapabilities
                ) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        if (cm.activeNetwork == network) {
                            updateUnderlyingNetworks(cm)
                        }
                    }
                }
            }
            val request = NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()
            cm.registerNetworkCallback(request, networkCallback!!)
        } catch (e: Exception) {
            log("warning", "Failed to register network callback: ${e.message}")
        }
    }

    private fun updateUnderlyingNetworks(cm: ConnectivityManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val activeNetwork = cm.activeNetwork ?: run {
                setUnderlyingNetworks(null)
                lastUnderlyingNetwork = null
                return
            }

            // In Android 10+, cm.activeNetwork returns the VPN network itself if active.
            // We must set the REAL underlying network (WiFi/LTE) to avoid status bar glitches.
            val caps = cm.getNetworkCapabilities(activeNetwork)
            if (caps == null || caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
                // Active is VPN or unknown — look for the best physical internet network
                val allNetworks = try { cm.allNetworks } catch (e: Exception) { emptyArray<Network>() }
                var physicalNetwork: Network? = null
                for (nw in allNetworks) {
                    val c = cm.getNetworkCapabilities(nw) ?: continue
                    if (c.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                        !c.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
                        physicalNetwork = nw
                        break
                    }
                }

                if (physicalNetwork == null) {
                    if (lastUnderlyingNetwork != null) {
                        setUnderlyingNetworks(null)
                        lastUnderlyingNetwork = null
                        log("info", "All underlying networks lost")
                    }
                    return
                }

                if (physicalNetwork == lastUnderlyingNetwork) return
                lastUnderlyingNetwork = physicalNetwork
                setUnderlyingNetworks(arrayOf(physicalNetwork))
                log("info", "Underlying network set to physical: $physicalNetwork")
            } else {
                // Active is already physical
                if (activeNetwork == lastUnderlyingNetwork) return
                lastUnderlyingNetwork = activeNetwork
                setUnderlyingNetworks(arrayOf(activeNetwork))
                log("info", "Underlying network updated: $activeNetwork")
            }
        }
    }

    private fun scheduleNetworkChanged() {
        // Only reconnect when fully connected — prevents spurious reconnects during the
        // initial startVpn() phase when onAvailable fires right after registration.
        if (currentNativeState != "connected") return
        pendingNetworkRunnable?.let { networkChangeHandler.removeCallbacks(it) }
        val r = Runnable { reconnectInternal() }
        pendingNetworkRunnable = r
        networkChangeHandler.postDelayed(r, 2000L)
    }

    private fun reconnectInternal() {
        if (userRequestedDisconnect.get()) return
        if (!isRunning.get()) return
        networkChangeHandler.post {
            if (userRequestedDisconnect.get() || !isRunning.get()) return@post
            // Don't send "connecting" here — ACTION_CONNECT_QUICK will do it
            Thread {
                stopVpn(resultState = "connecting", reconnecting = true)
                val intent = Intent(this@XrayVpnService, XrayVpnService::class.java)
                    .setAction(ACTION_CONNECT_QUICK)
                startService(intent)
            }.start()
        }
    }

    private fun startHeartbeat() {
        heartbeatThread?.interrupt()
        heartbeatFailures.set(0)
        heartbeatThread = Thread {
            while (!Thread.currentThread().isInterrupted && isRunning.get()) {
                try {
                    Thread.sleep(30_000)
                    if (!isRunning.get()) break
                    val port = activeSocksPort
                    if (port <= 0) continue
                    Socket().use { s ->
                        s.soTimeout = 5000
                        s.connect(InetSocketAddress("127.0.0.1", port), 5000)
                    }
                    heartbeatFailures.set(0)
                    log("debug", "Heartbeat OK")
                } catch (_: InterruptedException) {
                    break
                } catch (e: Exception) {
                    val failures = heartbeatFailures.incrementAndGet()
                    log("warning", "Heartbeat failed ($failures): ${e.message}")
                    if (failures >= 3) {
                        log("warning", "Heartbeat failed $failures times, reconnecting")
                        reconnectInternal()
                        break
                    }
                }
            }
        }.also { it.isDaemon = true; it.start() }
    }

    private fun stopHeartbeat() {
        heartbeatThread?.interrupt()
        heartbeatThread = null
        heartbeatFailures.set(0)
    }

    private fun unregisterNetworkCallback() {
        try {
            val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
            networkCallback?.let {
                cm.unregisterNetworkCallback(it)
                networkCallback = null
            }
        } catch (e: Exception) {
            // Ignore
        }
    }

    private fun pendingFlags() =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else
            PendingIntent.FLAG_UPDATE_CURRENT

    private fun buildConnectedNotification(uploadSpeed: Long, downloadSpeed: Long): Notification {
        val flags = pendingFlags()
        val stopIntent = PendingIntent.getService(this, 0,
            Intent(this, XrayVpnService::class.java).apply { action = ACTION_DISCONNECT }, flags)
        val openIntent = PendingIntent.getActivity(this, 0,
            packageManager.getLaunchIntentForPackage(packageName)
                ?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), flags)
        val speedText = "↑ ${formatSpeed(uploadSpeed)}  ↓ ${formatSpeed(downloadSpeed)}"
        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("TeapodStream VPN")
            .setContentText(speedText)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .setContentIntent(openIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Отключить", stopIntent)
            .build()
    }

    private fun buildDisconnectedNotification(): Notification {
        val flags = pendingFlags()
        val connectIntent = PendingIntent.getService(this, 1,
            Intent(this, XrayVpnService::class.java).apply { action = ACTION_CONNECT_QUICK }, flags)
        val openIntent = PendingIntent.getActivity(this, 0,
            packageManager.getLaunchIntentForPackage(packageName)
                ?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), flags)
        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("TeapodStream VPN")
            .setContentText("Отключено")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .setContentIntent(openIntent)
            .addAction(android.R.drawable.ic_media_play, "Подключить", connectIntent)
            .build()
    }

    private fun buildMinimalNotification(): Notification =
        NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_MINIMAL_ID)
            .setContentTitle("TeapodStream VPN")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .build()

    private fun formatSpeed(bps: Long): String {
        return when {
            bps >= 1_000_000 -> "%.1f MB/s".format(bps / 1_000_000.0)
            bps >= 1_000     -> "%.0f KB/s".format(bps / 1_000.0)
            else             -> "$bps B/s"
        }
    }

    /** Ensure the service is in foreground. Safe to call multiple times. */
    private fun ensureForeground() {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(NOTIFICATION_CHANNEL_ID, "VPN статус", NotificationManager.IMPORTANCE_LOW)
                    .apply { description = "Скорость и управление VPN" }
            )
            manager.createNotificationChannel(
                NotificationChannel(NOTIFICATION_CHANNEL_MINIMAL_ID, "VPN (фоновый режим)", NotificationManager.IMPORTANCE_MIN)
                    .apply { description = "Фоновый VPN-сервис" }
            )
        }
        val notification = if (showNotification) buildDisconnectedNotification() else buildMinimalNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun showDisconnectedNotification() {
        if (!showNotification) return
        try {
            val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(NOTIFICATION_ID, buildDisconnectedNotification())
        } catch (_: Exception) {}
    }

    private fun updateNotification(uploadSpeed: Long, downloadSpeed: Long) {
        if (!showNotification) return

        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildConnectedNotification(uploadSpeed, downloadSpeed))
    }

    private fun log(level: String, message: String) {
        android.util.Log.i("TeapodVPN", "[$level] $message")
        // Send logs to Flutter UI
        if (level == "error" || level == "info" || (BuildConfig.DEBUG && level == "debug")) {
            VpnEventStreamHandler.sendLogEvent(level, message)
        }
    }

    private fun subnetMaskToPrefix(mask: String): Int {
        val parts = mask.split(".").map { it.toInt() }
        var prefix = 0
        for (part in parts) {
            var bits = part
            while (bits != 0) { prefix += bits and 1; bits = bits ushr 1 }
        }
        return prefix
    }
}
