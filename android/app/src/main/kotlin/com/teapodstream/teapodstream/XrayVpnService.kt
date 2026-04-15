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
import android.os.ParcelFileDescriptor
import android.system.OsConstants
import android.net.TrafficStats
import androidx.core.app.NotificationCompat
import java.io.File
import com.teapodstream.tun2socks.TeapodVpnManager
import com.teapodstream.tun2socks.WhitelistMode

class XrayVpnService : VpnService() {

    companion object {
        init {
            System.loadLibrary("vpnhelper")
        }

        @JvmStatic external fun nativeKillProcess(pid: Long): Int
        @JvmStatic external fun nativeSetMaxFds(maxFds: Int): Int
        const val ACTION_CONNECT = "com.teapodstream.CONNECT"
        const val ACTION_DISCONNECT = "com.teapodstream.DISCONNECT"
        const val EXTRA_XRAY_CONFIG = "xray_config"
        const val EXTRA_SOCKS_PORT = "socks_port"
        const val EXTRA_SOCKS_USER = "socks_user"
        const val EXTRA_SOCKS_PASSWORD = "socks_password"
        const val EXTRA_EXCLUDED_PACKAGES = "excluded_packages"
        const val EXTRA_INCLUDED_PACKAGES = "included_packages"
        const val EXTRA_VPN_MODE = "vpn_mode"
        const val EXTRA_TUN_ADDRESS = "tun_address"
        const val EXTRA_TUN_NETMASK = "tun_netmask"
        const val EXTRA_TUN_MTU = "tun_mtu"
        const val EXTRA_TUN_DNS = "tun_dns"
        const val EXTRA_ENABLE_UDP = "enable_udp"
        const val EXTRA_SS_PREFIX = "ss_prefix" // hex-encoded Outline prefix bytes
        const val EXTRA_PROXY_ONLY = "proxy_only" // start only SOCKS proxy, no VPN tunnel

        // Static state tracker for querying from Dart
        @Volatile private var currentNativeState: String = "disconnected"
        @JvmStatic fun getNativeState(): String = currentNativeState

        private const val NOTIFICATION_CHANNEL_ID = "vpn_service"
        private const val NOTIFICATION_ID = 1

        @Volatile private var totalUpload: Long = 0
        @Volatile private var totalDownload: Long = 0
        @Volatile private var lastUploadSpeed: Long = 0
        @Volatile private var lastDownloadSpeed: Long = 0
        @Volatile private var baseUpload: Long = 0
        @Volatile private var baseDownload: Long = 0

        fun getStats(): Map<String, Long> = mapOf(
            "upload" to totalUpload,
            "download" to totalDownload,
            "uploadSpeed" to lastUploadSpeed,
            "downloadSpeed" to lastDownloadSpeed,
        )

        fun prepareBinaries(context: android.content.Context): Boolean {
            val abi = android.os.Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a"
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
    private var xrayProcess: Process? = null
    private var xrayPid: Long = -1L
    private var teapodVpnManager: TeapodVpnManager? = null
    private var statsThread: Thread? = null
    private var isRunning = false
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var lastNetworkUpdate: Long = 0
    private val networkUpdateDebounceMs = 5000L // 5 seconds
    private var prefixProxy: PrefixTcpProxy? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_DISCONNECT) {
            stopVpn()
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_CONNECT) {
            startForegroundNotification()
            val xrayConfig = intent.getStringExtra(EXTRA_XRAY_CONFIG) ?: ""
            val socksPort = intent.getIntExtra(EXTRA_SOCKS_PORT, 10808)
            val socksUser = intent.getStringExtra(EXTRA_SOCKS_USER) ?: ""
            val socksPassword = intent.getStringExtra(EXTRA_SOCKS_PASSWORD) ?: ""
            val excludedPackages = intent.getStringArrayListExtra(EXTRA_EXCLUDED_PACKAGES) ?: arrayListOf()
            val includedPackages = intent.getStringArrayListExtra(EXTRA_INCLUDED_PACKAGES) ?: arrayListOf()
            val vpnMode = intent.getStringExtra(EXTRA_VPN_MODE) ?: "allExcept"
            val tunAddress = intent.getStringExtra(EXTRA_TUN_ADDRESS) ?: "10.0.0.1"
            val tunNetmask = intent.getStringExtra(EXTRA_TUN_NETMASK) ?: "255.255.255.0"
            val tunMtu = intent.getIntExtra(EXTRA_TUN_MTU, 1500)
            val tunDns = intent.getStringExtra(EXTRA_TUN_DNS) ?: "1.1.1.1"
            val ssPrefix = intent.getStringExtra(EXTRA_SS_PREFIX)
            val proxyOnly = intent.getBooleanExtra(EXTRA_PROXY_ONLY, false)
            startVpn(xrayConfig, socksPort, socksUser, socksPassword,
                excludedPackages, includedPackages, vpnMode,
                tunAddress, tunNetmask, tunMtu, tunDns, ssPrefix, proxyOnly)
            return START_STICKY
        }
        return START_NOT_STICKY
    }

    private fun startVpn(
        xrayConfig: String,
        socksPort: Int,
        socksUser: String,
        socksPassword: String,
        excludedPackages: List<String>,
        includedPackages: List<String>,
        vpnMode: String,
        tunAddress: String,
        tunNetmask: String,
        tunMtu: Int,
        tunDns: String,
        ssPrefix: String? = null,
        proxyOnly: Boolean = false,
    ) {
        if (isRunning) return
        isRunning = true
        currentNativeState = "connecting"
            VpnEventStreamHandler.sendStateEvent("connecting")
        log("info", "Starting VPN")

        try {
            // Enable prefix proxy only when the ss:// URL contains ?prefix=.
            // That parameter signals the server supports Outline prefix-stripping.
            val finalConfig = if (ssPrefix != null) {
                injectPrefixProxy(xrayConfig, ssPrefix) ?: xrayConfig
            } else {
                xrayConfig
            }

            val configFile = File(filesDir, "xray_config.json")
            configFile.writeText(finalConfig)
            prepareBinaries(this)

            if (proxyOnly) {
                // Proxy-only mode: start Xray SOCKS proxy without TUN tunnel or tun2socks
                log("info", "Proxy-only mode: skipping TUN tunnel")

                val xrayBin = File(applicationInfo.nativeLibraryDir, "libxray.so")
                val xrayPb = ProcessBuilder(xrayBin.absolutePath, "run", "-c", configFile.absolutePath)
                xrayPb.environment()["XRAY_LOCATION_ASSET"] = filesDir.absolutePath
                xrayPb.redirectErrorStream(true)
                xrayProcess = xrayPb.start()

                Thread {
                    try {
                        xrayProcess?.inputStream?.bufferedReader()?.forEachLine { line ->
                            log("debug", "[xray] $line")
                        }
                    } catch (_: Exception) {}
                }.also { it.isDaemon = true; it.name = "xray-log"; it.start() }

                Thread.sleep(800)

                if (!isProcessAlive(xrayProcess)) {
                    throw IllegalStateException("xray process died on startup")
                }
                log("info", "xray started (proxy-only, SOCKS on port $socksPort)")

                startStatsMonitoring()
                currentNativeState = "connected"
                VpnEventStreamHandler.sendStateEvent("connected")
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

                // On Android 8+, set underlying networks for better routing
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val connectivityManager = getSystemService(CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
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
                log("info", "nativeSetMaxFds result (parent): $fdResult")

                tunInterface = builder.establish() ?: throw IllegalStateException("Failed to establish TUN")

                log("info", "TUN established")

                // 1. Start Xray directly (FD limit set by parent process)
                val xrayBin = File(applicationInfo.nativeLibraryDir, "libxray.so")
                val xrayPb = ProcessBuilder(xrayBin.absolutePath, "run", "-c", configFile.absolutePath)
                xrayPb.environment()["XRAY_LOCATION_ASSET"] = filesDir.absolutePath
                xrayPb.redirectErrorStream(true)
                xrayProcess = xrayPb.start()

                Thread {
                    try {
                        xrayProcess?.inputStream?.bufferedReader()?.forEachLine { line ->
                            log("debug", "[xray] $line")
                        }
                    } catch (_: Exception) {}
                }.also { it.isDaemon = true; it.name = "xray-log"; it.start() }

                Thread.sleep(800)

                if (!isProcessAlive(xrayProcess)) {
                    throw IllegalStateException("xray process died on startup")
                }
                log("info", "xray started")

                // 2. Start teapod-tun2socks (with strict split-tunneling UID validation)
                teapodVpnManager = TeapodVpnManager(this)

                // Convert package names to UIDs for split tunneling
                val allowedUids = mutableSetOf<Int>()
                val whitelistMode = when (vpnMode) {
                    "onlySelected" -> {
                        // Only selected apps go through VPN
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            for (pkg in includedPackages) {
                                try {
                                    val uid = packageManager.getPackageUid(pkg, PackageManager.GET_META_DATA)
                                    allowedUids.add(uid)
                                    log("info", "Allowed UID for $pkg: $uid")
                                } catch (e: Exception) {
                                    log("warning", "Failed to get UID for $pkg: ${e.message}")
                                }
                            }
                        }
                        WhitelistMode.ALLOW_ONLY
                    }
                    else -> {
                        // All apps go through VPN, except excluded
                        for (pkg in excludedPackages) {
                            try {
                                val uid = packageManager.getPackageUid(pkg, PackageManager.GET_META_DATA)
                                allowedUids.add(uid)
                                log("info", "Excluded UID for $pkg: $uid")
                            } catch (e: Exception) {
                                log("warning", "Failed to get UID for $pkg: ${e.message}")
                            }
                        }
                        // Always exclude own app to prevent routing loops
                        try {
                            val uid = packageManager.getPackageUid(packageName, PackageManager.GET_META_DATA)
                            allowedUids.add(uid)
                            log("info", "Excluded own UID ($packageName): $uid")
                        } catch (e: Exception) {
                            log("warning", "Failed to get own UID: ${e.message}")
                        }
                        WhitelistMode.DENY_ONLY
                    }
                }

                log("info", "Starting teapod-tun2socks: mode=$whitelistMode uids=${allowedUids.size}")

                teapodVpnManager!!.start(
                    tunFd = tunInterface!!,
                    socksHost = "127.0.0.1",
                    socksPort = socksPort,
                    socksUsername = socksUser,
                    socksPassword = socksPassword,
                    allowedUids = allowedUids,
                    whitelistMode = whitelistMode
                )

                log("info", "teapod-tun2socks started successfully")

                startStatsMonitoring()
                registerNetworkCallback()
                currentNativeState = "connected"
                VpnEventStreamHandler.sendStateEvent("connected")
                log("info", "VPN connected successfully")
            }
        } catch (e: Exception) {
            log("error", "Start failed: ${e.message}")
            currentNativeState = "error"
            VpnEventStreamHandler.sendStateEvent("error")
            stopVpn()
        }
    }

    /** Returns true if the process is still running. Uses exitValue() for API < 26 compatibility. */
    private fun isProcessAlive(p: Process?): Boolean {
        p ?: return false
        return try {
            p.exitValue()
            false  // process has exited
        } catch (_: IllegalThreadStateException) {
            true   // still running
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

    private fun stopVpn() {
        isRunning = false
        unregisterNetworkCallback()
        statsThread?.interrupt()

        prefixProxy?.stop()
        prefixProxy = null

        // Stop teapod-tun2socks
        try {
            teapodVpnManager?.stop()
        } catch (e: Exception) {
            log("warning", "Error stopping teapod-tun2socks: ${e.message}")
        }
        teapodVpnManager = null
        
        if (xrayPid > 0) {
            nativeKillProcess(xrayPid)
            xrayPid = -1L
        }
        xrayProcess?.destroy()
        tunInterface?.close()
        tunInterface = null
        currentNativeState = "disconnected"
        VpnEventStreamHandler.sendStateEvent("disconnected")
    }

    private fun startStatsMonitoring() {
        // Capture baseline TrafficStats at connection time
        baseUpload = TrafficStats.getUidTxBytes(applicationInfo.uid).coerceAtLeast(0)
        baseDownload = TrafficStats.getUidRxBytes(applicationInfo.uid).coerceAtLeast(0)

        var lastUp = 0L
        var lastDown = 0L
        var lastTime = System.currentTimeMillis()

        totalUpload = 0
        totalDownload = 0
        lastUploadSpeed = 0
        lastDownloadSpeed = 0

        statsThread = Thread {
            while (isRunning) {
                try {
                    Thread.sleep(1000)
                    val now = System.currentTimeMillis()
                    val elapsed = (now - lastTime) / 1000.0

                    // Get current TrafficStats and subtract baseline
                    val rawTx = TrafficStats.getUidTxBytes(applicationInfo.uid).coerceAtLeast(0)
                    val rawRx = TrafficStats.getUidRxBytes(applicationInfo.uid).coerceAtLeast(0)
                    val currentTx = (rawTx - baseUpload).coerceAtLeast(0)
                    val currentRx = (rawRx - baseDownload).coerceAtLeast(0)

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
                } catch (_: InterruptedException) { break } catch (_: Exception) {}
            }
        }.also { it.isDaemon = true; it.start() }
    }

    private fun registerNetworkCallback() {
        try {
            val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
            networkCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    log("info", "Network available, updating underlying networks")
                    updateUnderlyingNetworks(cm)
                }

                override fun onLost(network: Network) {
                    log("info", "Network lost, updating underlying networks")
                    updateUnderlyingNetworks(cm)
                }

                override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
                    // Ignored: fires too frequently on some devices (Huawei)
                    // and repeated setUnderlyingNetworks() breaks xray TCP connections
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
        val now = System.currentTimeMillis()
        if (now - lastNetworkUpdate < networkUpdateDebounceMs) {
            return // Debounce: skip updates within 5 seconds
        }
        lastNetworkUpdate = now

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val activeNetwork = cm.activeNetwork
            if (activeNetwork != null) {
                setUnderlyingNetworks(arrayOf(activeNetwork))
                log("info", "Updated underlying network")
            }
        }
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

    private fun startForegroundNotification() {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(NOTIFICATION_CHANNEL_ID, "VPN Service", NotificationManager.IMPORTANCE_LOW)
            manager.createNotificationChannel(channel)
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val stopIntent = PendingIntent.getService(this, 0,
            Intent(this, XrayVpnService::class.java).apply { action = ACTION_DISCONNECT }, flags)
        val notification = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("TeapodStream VPN")
            .setContentText("Защищенное соединение активно")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Отключить", stopIntent)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
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
