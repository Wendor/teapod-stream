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
import android.util.LruCache
import androidx.core.app.NotificationCompat
import java.io.File
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.Socket
import java.net.URL
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
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
        const val EXTRA_ALLOW_ICMP = "allow_icmp" // allow ICMP echo (ping) through the tunnel
        const val EXTRA_BLOCK_QUIC = "block_quic" // reject UDP/443 inside the TUN via ICMP Port Unreachable
        const val EXTRA_IPV6 = "ipv6_enabled" // add IPv6 address/route to the TUN interface
        const val EXTRA_MTU = "mtu" // TUN MTU size

        // Static state tracker for querying from Dart
        @Volatile private var currentNativeState: String = "disconnected"
        // Tracks whether we are in TUN mode (not proxy-only). Used by getNativeState() to detect
        // a TUN fd closed externally (e.g. during a phone call) without onRevoke() being called.
        @Volatile private var tunModeActive = false

        @JvmStatic fun getNativeState(): String {
            // If the native state claims "connected" in TUN mode but tun2socks is no longer running,
            // the TUN fd was likely closed externally (e.g. system network change during a phone call)
            // without onRevoke() being called. Correct the stale state proactively so that
            // syncNativeState() in Flutter reflects reality instead of showing a phantom connection.
            if (currentNativeState == "connected" && tunModeActive && !Teapodcore.isTunRunning()) {
                currentNativeState = "disconnected"
            }
            return currentNativeState
        }

        // Set true on explicit user disconnect, false on connect — guards reconnectInternal()
        val userRequestedDisconnect = AtomicBoolean(false)

        // Active SOCKS credentials — stored so onListen can replay them with "connected".
        // AtomicReference ensures the three fields are always read/written as a consistent unit.
        private data class SocksCredentials(val port: Int, val user: String, val password: String)
        private val _socksCredentials = AtomicReference(SocksCredentials(0, "", ""))

        val activeSocksPort: Int get() = _socksCredentials.get().port
        val activeSocksUser: String get() = _socksCredentials.get().user
        val activeSocksPassword: String get() = _socksCredentials.get().password

        // Epoch-ms when VPN became connected; 0 when disconnected. Survives UI restarts because
        // the foreground service process stays alive. Flutter uses this to restore the timer.
        @Volatile var connectedAtMs: Long = 0
            private set

        @JvmStatic fun getSocksCredentials(): Map<String, Any> {
            val c = _socksCredentials.get()
            return mapOf("port" to c.port, "user" to c.user, "password" to c.password, "connectedAtMs" to connectedAtMs)
        }

        const val LOG_FILE_NAME = "vpn_log.txt"
        const val LOG_PREV_FILE_NAME = "vpn_log.prev.txt"
        val LOG_FILE_LOCK = Any()

        private const val NOTIFICATION_CHANNEL_ID = "vpn_service"
        private const val NOTIFICATION_CHANNEL_MINIMAL_ID = "vpn_service_minimal"
        private const val NOTIFICATION_ID = 1

        // DNS-over-TCP endpoints for the direct-internet probe. Multiple providers so a
        // single blocked resolver (e.g. Google DNS unreachable in some regions) doesn't
        // make hasDirectInternet() report "no internet" forever, which would suppress
        // heartbeat failure counting and block reconnects. Yandex DNS covers networks
        // where foreign resolvers are filtered.
        private val CONNECTIVITY_CHECK_HOSTS = arrayOf("8.8.8.8", "1.1.1.1", "77.88.8.8")
        private const val STATS_INTERVAL_MS = 1_000L
        private const val STOP_THREAD_TIMEOUT_MS = 5_000L
        private const val RECONNECT_DEBOUNCE_MS = 2_000L
        // Failed CONNECT_QUICK reconnects are retried with linear backoff instead of
        // silently leaving the VPN off (and, with kill switch, traffic leaking).
        private const val MAX_RECONNECT_ATTEMPTS = 3
        private const val RECONNECT_RETRY_BASE_MS = 5_000L

        @Volatile private var totalUpload: Long = 0
        @Volatile private var totalDownload: Long = 0
        @Volatile private var lastUploadSpeed: Long = 0
        @Volatile private var lastDownloadSpeed: Long = 0

        private const val MAX_STATS_HISTORY = 300
        private val statsHistory = ArrayDeque<Pair<Long, Long>>(MAX_STATS_HISTORY)

        fun getStats(): Map<String, Long> = mapOf(
            "upload" to totalUpload,
            "download" to totalDownload,
            "uploadSpeed" to lastUploadSpeed,
            "downloadSpeed" to lastDownloadSpeed,
        )

        fun getStatsHistory(): List<Map<String, Long>> {
            synchronized(statsHistory) {
                return statsHistory.map { (up, down) ->
                    mapOf("uploadSpeed" to up, "downloadSpeed" to down)
                }
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
    @Volatile private var lastConnectedMs: Long = 0L
    private var prefixProxy: PrefixTcpProxy? = null
    @Volatile private var showNotification = true
    private var wakeLock: PowerManager.WakeLock? = null
    private var screenReceiver: android.content.BroadcastReceiver? = null
    private var killSwitchEnabled = false
    @Volatile private var allowIcmpEnabled = true
    @Volatile private var blockQuicEnabled = false
    private var proxyOnlyMode = false
    private val networkChangeHandler = Handler(Looper.getMainLooper())
    private var pendingNetworkRunnable: Runnable? = null
    private val reconnectAttempts = AtomicInteger(0)
    @Volatile private var notificationChannelsReady = false
    private val heartbeat = HeartbeatMonitor(object : HeartbeatMonitor.Deps {
        override val running: Boolean get() = isRunning.get()
        override val tunModeActive: Boolean get() = Companion.tunModeActive
        override val socksPort: Int get() = activeSocksPort
        override fun socksAuth(): Pair<String, String> =
            _socksCredentials.get().let { it.user to it.password }
        override fun isTunRunning() = Teapodcore.isTunRunning()
        override fun tunActiveConnections() = Teapodcore.tunActiveConnections()
        override fun tunLastRxActivityMs() = Teapodcore.getTunLastRxActivityMs()
        override fun tunStatsLine(): String = Teapodcore.getTunStatsLine()
        override fun hasDirectInternet() = this@XrayVpnService.hasDirectInternet()
        override fun requestReconnect() = reconnectInternal()
        override fun log(level: String, message: String) = this@XrayVpnService.log(level, message)
    })

    private val tunAddress = "10.120.230.1"
    private val tunNetmask = "255.255.255.0"
    @Volatile private var tunMtu = 1500
    private val tunDns    = "1.1.1.1"

    override fun onCreate() {
        super.onCreate()
        VpnEventStreamHandler.appContext = applicationContext
        migrateConnectionParamsIfNeeded()
        Teapodcore.registerVpnProtector(object : VpnProtector {
            override fun protect(fd: Long): Boolean {
                val result = this@XrayVpnService.protect(fd.toInt())
                android.util.Log.i("TeapodVPN", "[protect] fd=$fd result=$result")
                return result
            }
        })
        registerScreenReceiver()
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
                try { File(filesDir, "user_disconnected.flag").createNewFile() } catch (_: Exception) {}
                // Signal disconnecting immediately so the button turns yellow
                // even when triggered from the notification (no Flutter-side handler).
                setState("disconnecting")

                // Run cleanup off the main thread — Go calls (stopTun2Socks/stopXray)
                // can block if goroutines are stuck after long uptime or network changes.
                Thread {
                    val stopThread = Thread { stopVpn(explicit = true) }
                    stopThread.start()
                    try {
                        stopThread.join(STOP_THREAD_TIMEOUT_MS)
                        if (stopThread.isAlive) {
                            log("warning", "stopVpn timed out after 5s, forcing disconnected state")
                        }
                    } catch (e: InterruptedException) {
                        Thread.currentThread().interrupt()
                    }

                    // Из состояния blocked stopVpn выходит по CAS (isRunning уже false),
                    // TUN-sink kill switch'а нужно закрыть явно.
                    closeTunSink()

                    // Guarantee "disconnected" is always sent
                    setState("disconnected")
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
                val allowIcmp = intent.getBooleanExtra(EXTRA_ALLOW_ICMP, true)
                val blockQuic = intent.getBooleanExtra(EXTRA_BLOCK_QUIC, false)
                val ipv6Enabled = intent.getBooleanExtra(EXTRA_IPV6, false)
                val mtu = intent.getIntExtra(EXTRA_MTU, 1500).coerceIn(576, 9000)
                // Persist non-sensitive params for CONNECT_QUICK reconnect (no credentials)
                ConnectionParams(socksPort, excludedPackages, includedPackages,
                    vpnMode, ssPrefix, proxyOnly, showNotification, killSwitch, allowIcmp, blockQuic, ipv6Enabled, mtu)
                    .save(filesDir, ::log)
                userRequestedDisconnect.set(false)
                reconnectAttempts.set(0)
                try { File(filesDir, "user_disconnected.flag").delete() } catch (_: Exception) {}
                ensureForeground()
                Thread {
                    startVpn(xrayConfig, socksPort, socksUser, socksPassword,
                        excludedPackages, includedPackages, vpnMode, ssPrefix, proxyOnly, killSwitch,
                        allowIcmp, blockQuic, ipv6Enabled, mtu = mtu)
                }.start()
                return START_STICKY
            }
            ACTION_CONNECT_QUICK -> {
                // Load params and set showNotification BEFORE ensureForeground so the
                // correct notification type (full vs minimal) is shown from the start.
                val params = ConnectionParams.load(filesDir)
                if (params != null) showNotification = params.showNotification
                ensureForeground()
                if (isRunning.get()) {
                    // startVpn would bail on its CAS anyway — bail here instead so the
                    // state isn't left stuck at "reconnecting" over a live tunnel.
                    log("info", "CONNECT_QUICK ignored: VPN already running")
                    return START_STICKY
                }
                val configFile = File(filesDir, "xray_config.json")
                if (params != null && configFile.exists()) {
                    val needsPermission = !params.proxyOnly && VpnService.prepare(this) != null
                    if (needsPermission) {
                        openApp()
                    } else {
                        userRequestedDisconnect.set(false)
                        try { File(filesDir, "user_disconnected.flag").delete() } catch (_: Exception) {}
                        setState("reconnecting")
                        val configText = configFile.readText()
                        // Load SOCKS credentials from saved file (survives reconnect)
                        var socksUser = ""
                        var socksPassword = ""
                        try {
                            val credsFile = File(filesDir, "socks_creds.json")
                            if (credsFile.exists()) {
                                val json = org.json.JSONObject(credsFile.readText())
                                socksUser = json.optString("user", "")
                                socksPassword = json.optString("pass", "")
                                log("debug", "CONNECT_QUICK: loaded creds from file (auth=${socksUser.isNotEmpty()})")
                            } else {
                                // Fallback: extract from config
                                val (u, p) = extractSocksFromConfig(configText)
                                socksUser = u
                                socksPassword = p
                            }
                        } catch (e: Exception) {
                            log("warning", "Failed to load socks_creds: ${e.message}")
                            val (u, p) = extractSocksFromConfig(configText)
                            socksUser = u
                            socksPassword = p
                        }
                        Thread {
                            startVpn(
                                configText,
                                params.socksPort, socksUser, socksPassword,
                                params.excludedPackages, params.includedPackages, params.vpnMode,
                                params.ssPrefix, params.proxyOnly, params.killSwitch,
                                params.allowIcmp, params.blockQuic, params.ipv6Enabled, mtu = params.mtu, isReconnect = true
                            )
                        }.start()
                    }
                } else {
                    openApp()
                }
                return START_STICKY
            }
        }
        // Service restarted by Android after being killed, or started by always-on VPN.
        // Load params and set showNotification BEFORE ensureForeground (same fix as CONNECT_QUICK).
        val params = ConnectionParams.load(filesDir)
        if (params != null) showNotification = params.showNotification
        ensureForeground()
        // Auto-connect if saved params exist and user didn't explicitly disconnect.
        // The flag file covers process restarts: the static userRequestedDisconnect
        // is reset to false in a fresh process, but the user's choice must survive.
        val configFile = File(filesDir, "xray_config.json")
        if (params != null && configFile.exists()
            && !userRequestedDisconnect.get()
            && !File(filesDir, "user_disconnected.flag").exists()
            && !isRunning.get()
        ) {
            val needsPermission = !params.proxyOnly && VpnService.prepare(this) != null
            if (!needsPermission) {
                userRequestedDisconnect.set(false)
                setState("reconnecting")
                try {
                    val configText = configFile.readText()
                    val (socksUser, socksPassword) = extractSocksFromConfig(configText)
                    Thread {
                        startVpn(
                            configText,
                            params.socksPort, socksUser, socksPassword,
                            params.excludedPackages, params.includedPackages, params.vpnMode,
                            params.ssPrefix, params.proxyOnly, params.killSwitch,
                            params.allowIcmp, params.blockQuic, params.ipv6Enabled, mtu = params.mtu, isReconnect = true
                        )
                    }.start()
                    return START_STICKY
                } catch (e: Exception) {
                    log("warning", "Auto-connect failed: ${e.message}")
                    setState("disconnected")
                }
            }
        }
        applyNotificationState("disconnected")
        return START_STICKY
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
                        val user = acc.optString("user", "")
                        val pass = acc.optString("pass", "")
                        log("debug", "extractSocksFromConfig: extracted creds (auth=${user.isNotEmpty()})")
                        return user to pass
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
        allowIcmp: Boolean = true,
        blockQuic: Boolean = false,
        ipv6Enabled: Boolean = false,
        mtu: Int = 1500,
        isReconnect: Boolean = false,
    ) {
        if (!isRunning.compareAndSet(false, true)) return
        // Keep the previous TUN (kill-switch sink left by a reconnect) open until the
        // new one is established: establish() atomically replaces the interface, so
        // app traffic is blackholed by the old TUN instead of leaking while xray starts.
        val previousTun = tunInterface
        tunInterface = null
        killSwitchEnabled = killSwitch
        tunModeActive = !proxyOnly
        allowIcmpEnabled = allowIcmp
        blockQuicEnabled = blockQuic
        proxyOnlyMode = proxyOnly
        tunMtu = mtu.coerceIn(576, 9000)
        if (!isReconnect) clearLogFile()
        setState(if (isReconnect) "reconnecting" else "connecting")
        log("info", "Starting VPN (MTU: $tunMtu)")

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
                try { previousTun?.close() } catch (_: Exception) {}

                startXrayAndWait(finalConfig)

                log("info", "xray started (proxy-only, SOCKS on port $socksPort)")
                startStatsMonitoring()
                acquireWakeLock()
                setConnected(socksPort, socksUser, socksPassword)
                heartbeat.start(isReconnect)
                log("info", "Proxy-only mode active")
            } else {
                val randomSubnet1 = (2..250).random()
                val randomSubnet2 = (2..250).random()
                val randomSubnet3 = (2..250).random()
                val dynamicTunIp = "10.$randomSubnet1.$randomSubnet2.$randomSubnet3"

                val dynamicSession = "Teapod-${System.currentTimeMillis() % 10000}"

                val builder = Builder()
                    .setSession(dynamicSession)
                    .setMtu(tunMtu)
                    .addAddress(dynamicTunIp, 32)
                    .addRoute("0.0.0.0", 0)
                    .addDnsServer(tunDns)
                    .setBlocking(true)
                    .setMetered(false)

                // Without an IPv6 address Android blocks the family for tunneled apps
                // (no leak): connect() fails instantly and apps fall back to IPv4.
                // With the address, literal-IPv6 destinations (e.g. Telegram DCs) hang
                // when the VPN server has no IPv6 connectivity (#81).
                if (ipv6Enabled) {
                    val hex1 = (1..65535).random().toString(16)
                    val hex2 = (1..65535).random().toString(16)
                    val hex3 = (1..65535).random().toString(16)
                    builder.addAddress("fd00:$hex1:$hex2:$hex3::1", 64)
                    builder.addRoute("::", 0)
                }

                if (vpnMode == "onlySelected") {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        for (pkg in includedPackages) {
                            try {
                                builder.addAllowedApplication(pkg)
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
                // The new interface replaced the old one atomically — the sink fd can go now.
                try { previousTun?.close() } catch (_: Exception) {}
                log("info", "TUN established with IP $dynamicTunIp")

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
                    allowIcmpEnabled,
                    blockQuicEnabled,
                    validator
                )
                if (tunErr.isNotEmpty()) throw IllegalStateException("tun2socks: $tunErr")

                log("info", "tun2socks started successfully")

                startStatsMonitoring()
                registerNetworkCallback()
                acquireWakeLock()
                setConnected(socksPort, socksUser, socksPassword)
                heartbeat.start(isReconnect)
                log("info", "VPN connected successfully")
            }
        } catch (e: Exception) {
            log("error", "Start failed: ${e.message}")
            // If no new TUN was established, restore the old kill-switch sink so
            // stopVpn keeps blocking traffic; otherwise the old fd is obsolete.
            if (tunInterface == null && previousTun != null && killSwitch && !proxyOnly) {
                tunInterface = previousTun
            } else {
                try { previousTun?.close() } catch (_: Exception) {}
            }
            val willRetry = isReconnect && !userRequestedDisconnect.get()
                    && reconnectAttempts.incrementAndGet() <= MAX_RECONNECT_ATTEMPTS
            // On final failure with kill switch keep the sink (explicit=false) so
            // traffic stays blocked instead of silently leaking past the VPN.
            stopVpn(resultState = "error", explicit = !willRetry && !killSwitch, reconnecting = willRetry)
            if (willRetry) {
                val attempt = reconnectAttempts.get()
                val delayMs = RECONNECT_RETRY_BASE_MS * attempt
                log("warning", "Reconnect attempt $attempt/$MAX_RECONNECT_ATTEMPTS failed, retrying in ${delayMs}ms")
                try { Thread.sleep(delayMs) } catch (_: InterruptedException) { return }
                if (!userRequestedDisconnect.get() && !isRunning.get()) {
                    startService(Intent(this, XrayVpnService::class.java).setAction(ACTION_CONNECT_QUICK))
                }
            }
        }
    }

    /**
     * Starts xray-core and blocks until it signals ready or error via callback (max 30s safety timeout).
     * Throws IllegalStateException if xray reports an error status.
     */
    private fun startXrayAndWait(config: String) {
        val latch = CountDownLatch(1)
        val failed = AtomicBoolean(false)

        Teapodcore.startXray(config, object : XrayCallback {
            override fun onStatus(status: Long, message: String) {
                log("info", "[xray] $message")
                if (status != 0L) failed.set(true)
                latch.countDown()
            }
        })

        if (!latch.await(30, TimeUnit.SECONDS)) throw IllegalStateException("xray start timeout (30s)")
        if (failed.get()) throw IllegalStateException("xray failed to start")
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

        try {
            val ownUid = packageManager.getPackageUid(packageName, PackageManager.GET_META_DATA)
            if (vpnMode == "onlySelected") {
                if (uids.remove(ownUid)) {
                    log("info", "Removed own UID ($ownUid) from Allowed list to prevent loop")
                }
            } else {
                uids.add(ownUid)
                log("info", "Excluded own UID ($packageName): $ownUid")
            }
        } catch (e: Exception) {
            log("warning", "Failed to resolve own UID: ${e.message}")
        }

        return uids
    }

    private fun buildTunValidator(allowedUids: Set<Int>, vpnMode: String): TunValidator {
        if (allowedUids.isEmpty()) {
            return object : TunValidator {
                override fun onValidate(srcIP: String, srcPort: Long, dstIP: String, dstPort: Long, protocol: Long) = true
            }
        }
        val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager

        return object : TunValidator {
            override fun onValidate(srcIP: String, srcPort: Long, dstIP: String, dstPort: Long, protocol: Long): Boolean {
                var uid = -1
                var threwException = false
                try {
                    uid = cm.getConnectionOwnerUid(
                        protocol.toInt(),
                        InetSocketAddress(srcIP, srcPort.toInt()),
                        InetSocketAddress(dstIP, dstPort.toInt())
                    )
                } catch (_: Exception) {
                    threwException = true
                }

                if (threwException) {
                    // Lookup threw (e.g. API unavailable) — allow to avoid breaking connectivity.
                    return true
                }

                // uid=-1 means no local owner (e.g. tethered client packets).
                // Apply the same vpnMode logic: in allExcept mode -1 is not excluded → allow;
                // in onlySelected mode -1 is not in the allowlist → block.
                val effectiveUid = if (uid < 0) -1 else uid
                return if (vpnMode == "onlySelected") {
                    effectiveUid in allowedUids
                } else {
                    effectiveUid !in allowedUids
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

            val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
            val ownUid = android.os.Process.myUid()
            val proxy = PrefixTcpProxy(realHost, realPort, prefixBytes) { client ->
                try {
                    val uid = cm.getConnectionOwnerUid(
                        OsConstants.IPPROTO_TCP,
                        client.remoteSocketAddress as InetSocketAddress,
                        InetSocketAddress(client.localAddress, client.localPort)
                    )
                    uid == ownUid
                } catch (_: Exception) {
                    true // lookup unavailable — don't break the tunnel
                }
            }
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
        // Prevent START_STICKY auto-reconnect while the user is e.g. on a phone call.
        // The user did not request disconnect, but we must not reconnect until they explicitly
        // connect again — VPN permission may be temporarily revoked by the system.
        userRequestedDisconnect.set(true)
        stopVpn(explicit = true)
        // Force state update in case stopVpn returned early (isRunning was already false
        // during a reconnect cycle when the user tapped the system VPN popup).
        setState("disconnected")
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

    /** Закрывает TUN-sink kill switch'а, если сервис уже остановлен. */
    private fun closeTunSink() {
        if (isRunning.get()) return
        try { tunInterface?.close() } catch (_: Exception) {}
        tunInterface = null
    }

    private fun stopVpn(
        resultState: String = "disconnected",
        explicit: Boolean = false,
        reconnecting: Boolean = false,
    ) {
        if (!isRunning.compareAndSet(true, false)) return  // idempotent — safe to call multiple times
        log("info", "stopVpn: begin (explicit=$explicit, reconnecting=$reconnecting)")
        heartbeat.stop()
        tunModeActive = false
        lastUnderlyingNetwork = null
        lastConnectedMs = 0L
        pendingNetworkRunnable?.let { networkChangeHandler.removeCallbacks(it) }
        pendingNetworkRunnable = null

        try { wakeLock?.release() } catch (_: Exception) {}
        wakeLock = null

        var keptTunAsSink = false
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

            // Close TUN fd early so tun2socks goroutines reading from it get EOF and
            // unblock immediately (tun2socks works on a dup'd fd, so this is safe to
            // skip too). Kill-switch path keeps TUN open intentionally (traffic sink) —
            // including during internal reconnects: the next startVpn() closes the old
            // TUN only after the replacement is established, so app traffic is
            // blackholed by the sink instead of leaking past the VPN in between.
            val keepTunAsSink = killSwitchEnabled && !explicit && !proxyOnlyMode
                    && tunInterface != null
                    && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
            keptTunAsSink = keepTunAsSink
            if (!keepTunAsSink) {
                try {
                    tunInterface?.close()
                } catch (e: Exception) {
                    log("warning", "tunInterface.close (early) failed: ${e.message}")
                }
                tunInterface = null
            }

            log("info", "Stopping tun2socks")
            val tun2socksStopThread = Thread {
                try { Teapodcore.stopTun2Socks() } catch (e: Exception) {
                    log("warning", "stopTun2Socks failed: ${e.message}")
                }
            }
            tun2socksStopThread.isDaemon = true
            tun2socksStopThread.start()
            try {
                tun2socksStopThread.join(5000)
                if (tun2socksStopThread.isAlive) {
                    log("warning", "stopTun2Socks timed out after 5s, forcing continuation")
                } else {
                    log("info", "stopVpn: tun2socks stopped")
                }
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            }

            // Clean up saved credentials on explicit disconnect
            if (explicit) {
                try { File(filesDir, "socks_creds.json").delete() } catch (_: Exception) {}
            }

            log("info", "Stopping xray")
            // stopXray() can block indefinitely while Go goroutines drain open connections.
            // Run it in a daemon thread with a 3s deadline so disconnect always completes.
            val xrayStopThread = Thread {
                try { Teapodcore.stopXray() } catch (e: Exception) {
                    log("warning", "stopXray failed: ${e.message}")
                }
            }
            xrayStopThread.isDaemon = true
            xrayStopThread.start()
            try {
                xrayStopThread.join(3000)
                if (xrayStopThread.isAlive) {
                    log("warning", "stopXray timed out after 3s, forcing continuation")
                } else {
                    log("info", "stopVpn: xray stopped")
                }
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            }

            if (keepTunAsSink) {
                if (reconnecting) {
                    log("info", "Kill switch: TUN kept open as sink during reconnect")
                } else {
                    setUnderlyingNetworks(emptyArray())
                    log("info", "Kill switch active: TUN kept open, underlying networks cleared")
                }
            }

            // Keep xray_config.json for Quick Settings tile reconnect.
            // File is in process-private filesDir, not accessible to other apps.
            // if (explicit && !reconnecting) {
            //     try { File(filesDir, "xray_config.json").delete() } catch (_: Exception) {}
            // }
        } finally {
            // Don't overwrite "connecting" state when doing internal reconnect
            if (!reconnecting) {
                connectedAtMs = 0
                // TUN-sink остался открытым (kill switch) — трафик заблокирован,
                // сообщаем отличимое от disconnected состояние.
                setState(if (keptTunAsSink) "blocked" else resultState)
            } else {
                // Clear credentials so startVpn picks up fresh ones from configFile
                _socksCredentials.set(SocksCredentials(0, "", ""))
            }
            log("info", "stopVpn: done (state=${if (reconnecting) "reconnecting" else if (keptTunAsSink) "blocked" else resultState})")
        }
    }

    override fun onDestroy() {
        try { unregisterReceiver(screenReceiver) } catch (_: Exception) {}
        screenReceiver = null
        stopVpn()
        super.onDestroy()
    }

    private fun registerScreenReceiver() {
        screenReceiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(context: android.content.Context, intent: android.content.Intent) {
                when (intent.action) {
                    android.content.Intent.ACTION_SCREEN_OFF -> log("info", "Screen off")
                    android.content.Intent.ACTION_SCREEN_ON  -> {
                        log("info", "Screen on")
                        checkTunStallOnWake()
                    }
                    android.os.PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED -> {
                        val pm = context.getSystemService(POWER_SERVICE) as PowerManager
                        val idle = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) pm.isDeviceIdleMode else false
                        log("info", "Doze mode: ${if (idle) "entered" else "exited"}")
                    }
                }
            }
        }
        val filter = android.content.IntentFilter().apply {
            addAction(android.content.Intent.ACTION_SCREEN_OFF)
            addAction(android.content.Intent.ACTION_SCREEN_ON)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                addAction(android.os.PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
            }
        }
        registerReceiver(screenReceiver, filter)
    }

    private fun checkTunStallOnWake() {
        if (!tunModeActive || !isRunning.get()) return
        val lastRx = Teapodcore.getTunLastRxActivityMs()
        if (lastRx <= 0) return
        val idleSec = (System.currentTimeMillis() - lastRx) / 1000
        if (idleSec < HeartbeatMonitor.TUN_STALL_TIMEOUT_MS / 1000) return
        // Don't require activeConns >= 2: after Doze, connections drain to 0 naturally
        // but the tunnel session (xray upstream) may be stale for new connections.
        val activeConns = Teapodcore.tunActiveConnections()
        log("warning", "TUN stall on wake: no data for ${idleSec}s (conns=$activeConns), reconnecting")
        reconnectInternal()
    }

    private fun startStatsMonitoring() {
        var lastUp = 0L
        var lastDown = 0L
        var lastTime = System.currentTimeMillis()

        totalUpload = 0
        totalDownload = 0
        lastUploadSpeed = 0
        lastDownloadSpeed = 0
        lastUp = 0
        lastDown = 0
        lastTime = System.currentTimeMillis()
        statsHistory.clear()

        statsThread = Thread {
            while (isRunning.get()) {
                try {
                    Thread.sleep(STATS_INTERVAL_MS)
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
                    synchronized(statsHistory) {
                        if (statsHistory.size >= MAX_STATS_HISTORY) {
                            statsHistory.removeFirst()
                        }
                        statsHistory.addLast(Pair(lastUploadSpeed, lastDownloadSpeed))
                    }
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
                    // Force-close all active tun2socks connections immediately on network loss.
                    // Stale gVisor TCP connections survive across brief network blips and cause
                    // app-level freezes (Telegram, etc.) because the SOCKS5 heartbeat cannot
                    // observe per-connection gVisor state. Closing them now forces apps to
                    // reconnect through a clean path when the network comes back.
                    if (tunModeActive && isRunning.get()) {
                        val closed = Teapodcore.forceTunCloseAllConnections()
                        if (closed > 0) log("debug", "Network lost: force-closed $closed TUN connections")
                    }
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
                            // Captive portal / temporary internet loss: VALIDATED is removed
                            // without triggering onLost/onAvailable — detect and reconnect.
                            val validated = networkCapabilities.hasCapability(
                                NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                            if (!validated) scheduleNetworkChanged()
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

    private fun findPhysicalNetwork(): Network? {
        val cm = getSystemService(ConnectivityManager::class.java)
        val activeNetwork = cm.activeNetwork ?: return null

        val caps = cm.getNetworkCapabilities(activeNetwork)
        if (caps == null || caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
            // Active is VPN — find WiFi first (preferred over LTE)
            val wifiNetwork = try {
                cm.allNetworks.firstOrNull { n ->
                    val c = cm.getNetworkCapabilities(n)
                    c?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true &&
                    c?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
                }
            } catch (e: Exception) { null }

            if (wifiNetwork != null) return wifiNetwork

            // No WiFi — try any other internet network
            return try {
                cm.allNetworks.firstOrNull { n ->
                    val c = cm.getNetworkCapabilities(n)
                    c?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true &&
                    !c.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
                }
            } catch (e: Exception) { null }
        }

        // Active is not VPN — use it (WiFi or LTE)
        return activeNetwork
    }

    private fun updateUnderlyingNetworks(cm: ConnectivityManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val activeNetwork = cm.activeNetwork ?: run {
                setUnderlyingNetworks(null)
                lastUnderlyingNetwork = null
                return
            }

            // Use findPhysicalNetwork to get WiFi/LTE (not VPN)
            val physicalNetwork = findPhysicalNetwork()
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
        }
    }

    private fun scheduleNetworkChanged() {
        // Only reconnect when fully connected — prevents spurious reconnects during the
        // initial startVpn() phase when onAvailable fires right after registration.
        if (currentNativeState != "connected") return
        // On mobile data Android fires onAvailable/onCapabilitiesChanged right after VPN
        // connects, causing an immediate false reconnect loop. Ignore changes within 5s of
        // connection — real network switches happen on a longer timescale.
        val msSinceConnect = System.currentTimeMillis() - lastConnectedMs
        if (lastConnectedMs > 0 && msSinceConnect < 5_000L) {
            log("debug", "Network change: ignored (VPN just connected ${msSinceConnect}ms ago)")
            return
        }
        log("info", "Network change: reconnect scheduled in ${RECONNECT_DEBOUNCE_MS}ms")
        pendingNetworkRunnable?.let { networkChangeHandler.removeCallbacks(it) }
        val r = Runnable { reconnectInternal() }
        pendingNetworkRunnable = r
        networkChangeHandler.postDelayed(r, RECONNECT_DEBOUNCE_MS)
    }

    private fun reconnectInternal() {
        if (userRequestedDisconnect.get()) return
        if (!isRunning.get()) return
        networkChangeHandler.post {
            if (userRequestedDisconnect.get() || !isRunning.get()) return@post
            log("info", "reconnectInternal: starting reconnect cycle")
            reconnectAttempts.set(0)
            Thread {
                // Hold a WakeLock for the entire reconnect cycle so the CPU can't sleep
                // between stopVpn() releasing the main WakeLock and CONNECT_QUICK acquiring it.
                val reconnectWakeLock = try {
                    (getSystemService(POWER_SERVICE) as PowerManager)
                        .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "TeapodStream:Reconnect")
                        .also { it.acquire(40_000) }
                } catch (_: Exception) { null }
                try {
                    stopVpn(resultState = "connecting", reconnecting = true)
                    log("info", "reconnectInternal: waiting for direct internet (deadline +30s)")
                    val deadline = System.currentTimeMillis() + 30_000
                    while (!userRequestedDisconnect.get() && System.currentTimeMillis() < deadline) {
                        if (hasDirectInternet()) {
                            log("info", "reconnectInternal: internet available, launching CONNECT_QUICK")
                            break
                        }
                        Thread.sleep(RECONNECT_DEBOUNCE_MS)
                    }
                    if (userRequestedDisconnect.get()) {
                        log("info", "reconnectInternal: cancelled (user disconnect)")
                        return@Thread
                    }
                    if (System.currentTimeMillis() >= deadline) {
                        log("info", "reconnectInternal: internet wait expired, launching CONNECT_QUICK anyway")
                    }
                    val intent = Intent(this@XrayVpnService, XrayVpnService::class.java)
                        .setAction(ACTION_CONNECT_QUICK)
                    startService(intent)
                } finally {
                    try { reconnectWakeLock?.release() } catch (_: Exception) {}
                }
            }.start()
        }
    }

    // Index of the host in CONNECTIVITY_CHECK_HOSTS that answered last — tried first on
    // the next probe so the happy path stays a single connection attempt.
    @Volatile private var lastGoodCheckHost = 0

    // Returns true if the physical network (not through VPN) can reach any of the
    // CONNECTIVITY_CHECK_HOSTS on port 53 (DNS-over-TCP).
    // The VpnService process UID is excluded from the tunnel, so sockets here bypass TUN.
    // bindSocket() additionally pins the socket to the physical interface, avoiding
    // stale routing state during WiFi→LTE handover.
    private fun hasDirectInternet(): Boolean {
        val n = CONNECTIVITY_CHECK_HOSTS.size
        val physicalNetwork = findPhysicalNetwork()
        for (attempt in 0 until n) {
            val idx = (lastGoodCheckHost + attempt) % n
            try {
                Socket().use { socket ->
                    physicalNetwork?.bindSocket(socket)
                    socket.connect(
                        InetSocketAddress(CONNECTIVITY_CHECK_HOSTS[idx], 53),
                        RECONNECT_DEBOUNCE_MS.toInt()
                    )
                }
                lastGoodCheckHost = idx
                return true
            } catch (_: Exception) {
                // Try the next host — a single blocked/unreachable resolver must not
                // be mistaken for total loss of connectivity.
            }
        }
        return false
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

    private fun buildIntermediateNotification(isConnecting: Boolean): Notification {
        val text = if (isConnecting) "Подключение…" else "Отключение…"
        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("TeapodStream VPN")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setProgress(0, 0, true)
            .build()
    }

    private fun buildMinimalNotification(): Notification =
        NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_MINIMAL_ID)
            .setContentTitle("TeapodStream VPN")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .build()

    private fun ensureNotificationChannels(manager: NotificationManager) {
        if (notificationChannelsReady) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            notificationChannelsReady = true
            return
        }
        manager.createNotificationChannel(
            NotificationChannel(NOTIFICATION_CHANNEL_ID, "VPN статус", NotificationManager.IMPORTANCE_LOW)
                .apply { description = "Скорость и управление VPN" }
        )
        manager.createNotificationChannel(
            NotificationChannel(NOTIFICATION_CHANNEL_MINIMAL_ID, "VPN (фоновый режим)", NotificationManager.IMPORTANCE_MIN)
                .apply { description = "Фоновый VPN-сервис" }
        )
        notificationChannelsReady = true
    }

    private fun applyNotificationState(
        state: String,
        uploadSpeed: Long = 0,
        downloadSpeed: Long = 0,
    ) {
        val notification = when (VpnNotificationPolicy.variantFor(state, showNotification)) {
            VpnNotificationVariant.MINIMAL -> buildMinimalNotification()
            VpnNotificationVariant.CONNECTING -> buildIntermediateNotification(isConnecting = true)
            VpnNotificationVariant.DISCONNECTING -> buildIntermediateNotification(isConnecting = false)
            VpnNotificationVariant.CONNECTED -> buildConnectedNotification(uploadSpeed, downloadSpeed)
            VpnNotificationVariant.DISCONNECTED -> buildDisconnectedNotification()
            VpnNotificationVariant.KEEP_CURRENT -> return
        }
        try {
            val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            ensureNotificationChannels(manager)
            manager.notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            log("warning", "Notification update failed for state=$state: ${e.message}")
        }
    }

    /** Ensure the service is in foreground. Safe to call multiple times. */
    private fun ensureForeground() {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        ensureNotificationChannels(manager)
        val notification = if (showNotification) buildDisconnectedNotification() else buildMinimalNotification()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            log("warning", "startForeground failed: ${e.message}")
        }
    }

    private fun setState(state: String) {
        currentNativeState = state
        applyNotificationState(state)
        VpnEventStreamHandler.sendStateEvent(state)
        sendBroadcast(Intent("com.teapodstream.STATE_CHANGED").apply { putExtra("state", state) })
    }

    private fun setConnected(socksPort: Int, socksUser: String, socksPassword: String) {
        currentNativeState = "connected"
        reconnectAttempts.set(0)
        val now = System.currentTimeMillis()
        connectedAtMs = now
        lastConnectedMs = now
        _socksCredentials.set(SocksCredentials(socksPort, socksUser, socksPassword))
        // Save credentials to file for CONNECT_QUICK reconnect
        try {
            val credsFile = File(filesDir, "socks_creds.json")
            val json = org.json.JSONObject().apply {
                put("port", socksPort)
                put("user", socksUser)
                put("pass", socksPassword)
            }
            credsFile.writeText(json.toString())
        } catch (e: Exception) {
            log("warning", "Failed to save socks_creds: ${e.message}")
        }
        applyNotificationState("connected")
        VpnEventStreamHandler.sendConnectedEvent(socksPort, socksUser, socksPassword)
        sendBroadcast(Intent("com.teapodstream.STATE_CHANGED").apply {
            putExtra("state", "connected")
            putExtra("socksPort", socksPort)
        })
    }

    private fun updateNotification(uploadSpeed: Long, downloadSpeed: Long) {
        if (!showNotification) return
        applyNotificationState("connected", uploadSpeed, downloadSpeed)
    }

    private fun log(level: String, message: String) {
        android.util.Log.i("TeapodVPN", "[$level] $message")
        appendLogLine(level, message)
        if (level != "debug" || BuildConfig.DEBUG) {
            VpnEventStreamHandler.sendLogEvent(level, message)
        }
    }

    private fun appendLogLine(level: String, message: String) {
        try {
            val line = "${System.currentTimeMillis()}|$level|${message.replace("\n", " ")}\n"
            synchronized(LOG_FILE_LOCK) {
                java.io.FileWriter(File(filesDir, LOG_FILE_NAME), true).use { it.write(line) }
            }
        } catch (_: Exception) {}
    }

    // Rotate instead of wiping: the previous session's log survives one connect,
    // so a hang that forced the user to reconnect can still be diagnosed afterwards.
    private fun clearLogFile() {
        try {
            synchronized(LOG_FILE_LOCK) {
                val current = File(filesDir, LOG_FILE_NAME)
                val prev = File(filesDir, LOG_PREV_FILE_NAME)
                prev.delete()
                if (current.exists() && current.length() > 0) {
                    current.renameTo(prev)
                }
                current.writeText("")
            }
        } catch (_: Exception) {}
    }


}
