package com.teapodstream.teapodstream

import com.teapodstream.teapodstream.core.CoreKind
import com.teapodstream.teapodstream.core.VpnCores

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.drawable.Drawable
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.net.InetSocketAddress

class MainActivity : FlutterActivity() {

    companion object {
        // Pinging all configs and urltest over candidates send bursts of calls: without a limit —
        // a `ping` process / temporary core instance per config at once.
        private val pingPool = java.util.concurrent.Executors.newFixedThreadPool(8)
        private val measurePool = java.util.concurrent.Executors.newFixedThreadPool(4)
        private const val METHOD_CHANNEL = "com.teapodstream/vpn"
        private const val EVENT_CHANNEL = "com.teapodstream/vpn/events"
        private const val VPN_PERMISSION_REQUEST = 1001
        private const val PREF_BATTERY_PROMPT_SHOWN = "battery_prompt_shown"
    }

    private val pendingVpnStart = PendingVpnStart()
    private var pendingDeeplink: String? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (BuildConfig.ITEST) {
            // Runner commands arrive as an intent to the activity: with the screen off or on
            // the lock screen it doesn't resume and the intent doesn't reach Dart.
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        if (ItestBridge.onIntent(this, intent)) return
        intent?.let { handleIncomingIntentForPending(it) }
    }

    private fun handleIncomingIntentForPending(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme == "teapod" && uri.host == "import") {
            pendingDeeplink = uri.toString()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Event channel for native → Flutter events
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(VpnEventStreamHandler)
        ItestBridge.attach(flutterEngine.dartExecutor.binaryMessenger)

        // Send pending deeplink if the app was launched via a link
        pendingDeeplink?.let { uri ->
            VpnEventStreamHandler.sendDeeplinkEvent(uri)
            pendingDeeplink = null
        }

        // Method channel for Flutter → native calls
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connect" -> {
                        val xrayConfig = call.argument<String>("xrayConfig") ?: run {
                            result.error("INVALID_ARGS", "xrayConfig required", null)
                            return@setMethodCallHandler
                        }
                        val socksUser = call.argument<String>("socksUser") ?: ""
                        val socksPassword = call.argument<String>("socksPassword") ?: ""
                        val params = ConnectionParams.fromArgs(call.arguments as Map<*, *>)
                        val start = {
                            startVpnService(
                                xrayConfig, socksUser, socksPassword, params,
                                configName = call.argument<String>("configName"),
                                attempt = call.argument<Number>("attempt")?.toLong() ?: 0,
                            )
                            result.success(null)
                        }
                        // Proxy-only: no TUN tunnel, no VPN permission needed
                        if (params.proxyOnly) {
                            pendingVpnStart.cancel(PendingVpnStart.SUPERSEDED)
                            start()
                        } else {
                            requestVpnPermission(result, start)
                        }
                    }

                    "disconnect" -> {
                        // A connect still waiting for the permission dialog must not start after this.
                        pendingVpnStart.cancel(PendingVpnStart.CANCELLED)
                        stopVpnService()
                        result.success(null)
                    }

                    "getAvailableEngines" -> {
                        result.success(CoreKind.entries.filter { VpnCores.isAvailable(it) }.map { it.id })
                    }

                    // Re-save the quick-reconnect config (tile, autostart) without connecting —
                    // on a core change while disconnected. During a session — a no-op.
                    "saveQuickConnect" -> {
                        if (XrayVpnService.snapshot.state !in setOf(SessionState.DISCONNECTED, SessionState.ERROR)) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val xrayConfig = call.argument<String>("xrayConfig") ?: run {
                            result.error("INVALID_ARGS", "xrayConfig required", null)
                            return@setMethodCallHandler
                        }
                        val params = ConnectionParams.fromArgs(call.arguments as Map<*, *>)
                        try {
                            QuickConnectStore(filesDir).save(
                                xrayConfig, params,
                                socksUser = call.argument<String>("socksUser") ?: "",
                                socksPassword = call.argument<String>("socksPassword") ?: "",
                            )
                        } catch (e: Exception) {
                            result.error("IO", "saveQuickConnect: ${e.message}", null)
                            return@setMethodCallHandler
                        }
                        VpnTileService.saveConfigName(this, call.argument<String>("configName"))
                        result.success(true)
                    }

                    "clearQuickConnect" -> {
                        if (XrayVpnService.snapshot.state !in setOf(SessionState.DISCONNECTED, SessionState.ERROR)) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        QuickConnectStore(filesDir).clear()
                        VpnTileService.saveConfigName(this, null)
                        result.success(true)
                    }

                    "getStats" -> {
                        val stats = XrayVpnService.getStats()
                        result.success(stats)
                    }

                    "getAbi" -> {
                        result.success(android.os.Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a")
                    }

                    "prepareBinaries" -> {
                        Thread {
                            val success = XrayVpnService.prepareBinaries(this)
                            runOnUiThread { result.success(success) }
                        }.start()
                    }

                    "getFilesDir" -> {
                        result.success(filesDir.absolutePath)
                    }

                    "ping" -> {
                        val address = call.argument<String>("address") ?: ""
                        val port = call.argument<Int>("port") ?: 443
                        // Run ping in background thread
                        pingPool.execute {
                            val latency = pingHost(address, port)
                            runOnUiThread { result.success(latency) }
                        }
                    }

                    // A real latency measurement through a candidate: brings up a temporary
                    // xray instance with its config. Unlike a TCP ping it sees
                    // that the server is alive at the protocol level, not just listening on the port.
                    "measureOutbound" -> {
                        val config = call.argument<String>("config") ?: ""
                        val url = call.argument<String>("url") ?: ""
                        measurePool.execute {
                            val latency = try {
                                VpnCores.get(CoreKind.fromId(call.argument<String>("engine"))).measureOutbound(applicationContext, config, url)
                            } catch (e: Exception) {
                                -1L
                            }
                            runOnUiThread { result.success(if (latency >= 0) latency.toInt() else null) }
                        }
                    }

                    "getInstalledApps" -> {
                        Thread {
                            val apps = getInstalledApps()
                            runOnUiThread { result.success(apps) }
                        }.start()
                    }

                    "getAppIcon" -> {
                        val packageName = call.argument<String>("packageName") ?: run {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            val bytes = getAppIconBytes(packageName)
                            runOnUiThread { result.success(bytes) }
                        }.start()
                    }

                    "getBinaryVersions" -> {
                        Thread {
                            val versions = getBinaryVersions()
                            runOnUiThread { result.success(versions) }
                        }.start()
                    }

                    // Country of an IP by the geoip.dat the cores route with; null when unknown.
                    // Reads the whole file, so off the main thread.
                    "countryForIp" -> {
                        val ip = call.argument<String>("ip") ?: ""
                        Thread {
                            val code = try {
                                teapodcore.Teapodcore.countryForIp(filesDir.absolutePath, ip)
                            } catch (_: Throwable) {
                                ""
                            }
                            runOnUiThread { result.success(code.ifEmpty { null }) }
                        }.start()
                    }

                    "getDeviceId" -> {
                        val deviceId = android.provider.Settings.Secure.getString(
                            contentResolver,
                            android.provider.Settings.Secure.ANDROID_ID
                        )
                        result.success(deviceId)
                    }

                    "getDeviceInfo" -> {
                        val deviceModel = android.os.Build.MODEL
                        val osVersion = android.os.Build.VERSION.SDK_INT
                        result.success(mapOf(
                            "model" to deviceModel,
                            "osVersion" to osVersion
                        ))
                    }

                    "getState" -> {
                        // The SOCKS login and connectedAtMs are set only while connected (SessionSnapshot)
                        val s = XrayVpnService.snapshot
                        result.success(mapOf(
                            "state" to s.state.wire,
                            "socksPort" to s.socksPort,
                            "socksUser" to s.socksUser,
                            "socksPassword" to s.socksPassword,
                            "connectedAtMs" to s.connectedAtMs,
                            "attempt" to s.attempt,
                        ))
                    }

                    "getLogFilePath" -> {
                        result.success("${filesDir.absolutePath}/${XrayVpnService.LOG_FILE_NAME}")
                    }

                    "getTunnelDiag" -> {
                        result.success(VpnCores.active.diagnostics())
                    }

                    "setLogsEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        getSharedPreferences(XrayVpnService.PREFS_NAME, MODE_PRIVATE)
                            .edit().putBoolean(XrayVpnService.PREF_LOGS_ENABLED, enabled).apply()
                        XrayVpnService.logsEnabled = enabled
                        result.success(null)
                    }

                    "getLogs" -> {
                        Thread {
                            val lines = synchronized(XrayVpnService.LOG_FILE_LOCK) {
                                XrayVpnService.flushLogBuffer(filesDir)
                                listOf(XrayVpnService.LOG_PREV_FILE_NAME, XrayVpnService.LOG_FILE_NAME)
                                    .map { java.io.File(filesDir, it) }
                                    .filter { it.exists() }
                                    .flatMap { it.readLines() }
                                    .filter { it.isNotBlank() }
                                    .takeLast(2000)
                            }
                            runOnUiThread { result.success(lines) }
                        }.start()
                    }

                    "clearLogs" -> {
                        Thread {
                            try {
                                synchronized(XrayVpnService.LOG_FILE_LOCK) {
                                    XrayVpnService.flushLogBuffer(filesDir)
                                    java.io.File(filesDir, XrayVpnService.LOG_FILE_NAME).writeText("")
                                    java.io.File(filesDir, XrayVpnService.LOG_PREV_FILE_NAME).delete()
                                }
                            } catch (_: Exception) {}
                            runOnUiThread { result.success(null) }
                        }.start()
                    }

                    "getStatsHistory" -> {
                        result.success(XrayVpnService.getStatsHistory(
                            call.argument<Int>("epoch") ?: -1,
                            (call.argument<Number>("since") ?: 0).toLong(),
                        ))
                    }

                    "openBatteryOptimizationSettings" -> {
                        openBatteryOptimizationSettings()
                        result.success(null)
                    }

                    "installApk" -> {
                        val filePath = call.argument<String>("filePath") ?: run {
                            result.error("INVALID_ARGS", "filePath required", null)
                            return@setMethodCallHandler
                        }
                        val file = java.io.File(filePath)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "APK not found: $filePath", null)
                            return@setMethodCallHandler
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            !packageManager.canRequestPackageInstalls()) {
                            val intent = Intent(
                                android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                            result.error("PERMISSION_REQUIRED", "Install unknown apps permission needed", null)
                            return@setMethodCallHandler
                        }
                        val uri = androidx.core.content.FileProvider.getUriForFile(
                            this, "$packageName.fileprovider", file
                        )
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                        }
                        startActivity(intent)
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (ItestBridge.onIntent(this, intent)) return
        handleIncomingIntent(intent)
    }

    private fun handleIncomingIntent(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme == "teapod" && uri.host == "import") {
            VpnEventStreamHandler.sendDeeplinkEvent(uri.toString())
        }
    }

    private fun requestVpnPermission(result: MethodChannel.Result, action: () -> Unit) {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            // Need to ask for permission; a connect arriving while the dialog is open replaces the waiting one.
            val reject = { code: String ->
                val message = if (code == PendingVpnStart.DENIED) "User denied VPN permission" else "VPN start $code"
                result.error(code, message, null)
            }
            if (pendingVpnStart.offer(action, reject)) {
                try {
                    startActivityForResult(intent, VPN_PERMISSION_REQUEST)
                } catch (e: Exception) {
                    android.util.Log.w("TeapodVPN", "VPN permission dialog failed: ${e.message}")
                    pendingVpnStart.dialogFailed()
                }
            }
        } else {
            // Already have permission
            pendingVpnStart.cancel(PendingVpnStart.SUPERSEDED)
            action()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_PERMISSION_REQUEST) {
            pendingVpnStart.complete(granted = resultCode == Activity.RESULT_OK)
        }
    }

    /** The system "ignore battery optimizations" prompt, once per install: a user who declined isn't asked on every
     *  connect. Settings → Battery opens it again ([openBatteryOptimizationSettings]). */
    private fun requestBatteryOptimizationExemptionOnce() {
        val prefs = getSharedPreferences(XrayVpnService.PREFS_NAME, MODE_PRIVATE)
        // An exempt app isn't asked and the flag stays unset: if the exemption is removed later, the next connect asks.
        if (prefs.getBoolean(PREF_BATTERY_PROMPT_SHOWN, false) || isIgnoringBatteryOptimizations()) return
        // Recorded only once the prompt has opened: a failed launch is retried on the next connect.
        if (openBatteryOptimizationSettings()) prefs.edit().putBoolean(PREF_BATTERY_PROMPT_SHOWN, true).apply()
    }

    private fun isIgnoringBatteryOptimizations(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            (getSystemService(POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(packageName)

    /** The exemption prompt while the app is optimized; the system list (to revert it) once it is exempt.
     *  False when there is nothing to open (before Android 6) or the launch failed. */
    private fun openBatteryOptimizationSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val intent = if (isIgnoringBatteryOptimizations()) {
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        } else {
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).setData(Uri.parse("package:$packageName"))
        }
        return try {
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun startVpnService(
        xrayConfig: String,
        socksUser: String,
        socksPassword: String,
        params: ConnectionParams,
        configName: String?,
        attempt: Long,
    ) {
        requestBatteryOptimizationExemptionOnce()
        val intent = Intent(this, XrayVpnService::class.java).apply {
            action = XrayVpnService.ACTION_CONNECT
            putExtra(XrayVpnService.EXTRA_XRAY_CONFIG, xrayConfig)
            putExtra(XrayVpnService.EXTRA_SOCKS_USER, socksUser)
            putExtra(XrayVpnService.EXTRA_SOCKS_PASSWORD, socksPassword)
            putExtra(XrayVpnService.EXTRA_PARAMS, params.toJson().toString())
            putExtra(XrayVpnService.EXTRA_CONFIG_NAME, configName)
            putExtra(XrayVpnService.EXTRA_ATTEMPT, attempt)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopVpnService() {
        val intent = Intent(this, XrayVpnService::class.java).apply {
            action = XrayVpnService.ACTION_DISCONNECT
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun pingHost(address: String, port: Int): Int? {
        return icmpPing(address) ?: tcpPing(address, port)
    }

    private fun icmpPing(address: String): Int? {
        if (!isPingableAddress(address)) return null
        return try {
            val proc = Runtime.getRuntime().exec(arrayOf("ping", "-c", "1", "-w", "3", address))
            val exited = proc.waitFor(5, java.util.concurrent.TimeUnit.SECONDS)
            if (!exited || proc.exitValue() != 0) {
                proc.destroy()
                return null
            }
            val output = proc.inputStream.bufferedReader().readText()
            Regex("time=(\\d+\\.?\\d*)").find(output)
                ?.groupValues?.get(1)?.toFloatOrNull()?.toInt()
        } catch (e: Exception) {
            null
        }
    }

    private fun tcpPing(address: String, port: Int): Int? {
        return try {
            val start = System.currentTimeMillis()
            val socket = java.net.Socket()
            socket.connect(java.net.InetSocketAddress(address, port), 5000)
            val elapsed = (System.currentTimeMillis() - start).toInt()
            socket.close()
            elapsed
        } catch (e: Exception) {
            null
        }
    }

    private fun getInstalledApps(): List<Map<String, Any?>> {
        val pm = packageManager
        val packages = pm.getInstalledPackages(0)
        return packages
            .filter { it.packageName != packageName }
            .mapNotNull { pkg ->
                try {
                    val appInfo = pkg.applicationInfo ?: return@mapNotNull null
                    val appName = pm.getApplicationLabel(appInfo).toString()
                    val isSystem = (appInfo.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
                    mapOf(
                        "packageName" to pkg.packageName,
                        "appName" to appName,
                        "isSystem" to isSystem,
                    )
                } catch (e: Exception) {
                    null
                }
            }
            .sortedBy { it["appName"] as? String }
    }

    private fun getAppIconBytes(packageName: String): ByteArray? {
        return try {
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            val drawable = appInfo.loadIcon(packageManager)
            val size = (48 * resources.displayMetrics.density).toInt().coerceAtLeast(72)
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = android.graphics.Canvas(bitmap)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 80, stream)
            bitmap.recycle()
            stream.toByteArray()
        } catch (e: Exception) {
            null
        }
    }

    private fun getBinaryVersions(): Map<String, String> {
        val versions = mutableMapOf<String, String>()
        try {
            versions.putAll(VpnCores.versions())
            versions["xray"] = VpnCores.active.version()
            versions["tun2socks"] = "teapod-core (AAR)"
        } catch (e: Exception) {
            versions["xray"] = "Error"
            versions["tun2socks"] = "Error"
        }
        return versions
    }
}
