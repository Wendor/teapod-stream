package com.teapodstream.teapodstream

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
        private const val METHOD_CHANNEL = "com.teapodstream/vpn"
        private const val EVENT_CHANNEL = "com.teapodstream/vpn/events"
        private const val VPN_PERMISSION_REQUEST = 1001
    }

    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Инициализируем контекст для обновления Quick Settings плитки
        VpnEventStreamHandler.appContext = applicationContext

        // Event channel for native → Flutter events
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(VpnEventStreamHandler)

        // Method channel for Flutter → native calls
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connect" -> {
                        val xrayConfig = call.argument<String>("xrayConfig") ?: run {
                            result.error("INVALID_ARGS", "xrayConfig required", null)
                            return@setMethodCallHandler
                        }
                        val socksPort = call.argument<Int>("socksPort") ?: 10808
                        val socksUser = call.argument<String>("socksUser") ?: ""
                        val socksPassword = call.argument<String>("socksPassword") ?: ""
                        val excludedPackages = call.argument<List<String>>("excludedPackages") ?: emptyList()
                        val includedPackages = call.argument<List<String>>("includedPackages") ?: emptyList()
                        val vpnMode = call.argument<String>("vpnMode") ?: "allExcept"
                        val ssPrefix = call.argument<String>("ssPrefix")
                        val proxyOnly = call.argument<Boolean>("proxyOnly") ?: false
                        val showNotification = call.argument<Boolean>("showNotification") ?: true
                        val killSwitch = call.argument<Boolean>("killSwitch") ?: false
                        val allowIcmp = call.argument<Boolean>("allowIcmp") ?: true

                        if (proxyOnly) {
                            // Proxy-only: no TUN tunnel, no VPN permission needed
                            startVpnService(
                                xrayConfig, socksPort, socksUser, socksPassword,
                                excludedPackages, includedPackages, vpnMode,
                                ssPrefix, proxyOnly = true, showNotification = showNotification,
                                killSwitch = killSwitch, allowIcmp = allowIcmp
                            )
                            result.success(null)
                        } else {
                            requestVpnPermission(result) {
                                startVpnService(
                                    xrayConfig, socksPort, socksUser, socksPassword,
                                    excludedPackages, includedPackages, vpnMode,
                                    ssPrefix, proxyOnly = false, showNotification = showNotification,
                                    killSwitch = killSwitch, allowIcmp = allowIcmp
                                )
                                result.success(null)
                            }
                        }
                    }

                    "disconnect" -> {
                        stopVpnService()
                        result.success(null)
                    }

                    "getStats" -> {
                        val stats = XrayVpnService.getStats()
                        result.success(stats)
                    }

                    "getAbi" -> {
                        result.success(android.os.Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a")
                    }

                    "isBinaryReady" -> {
                        val geoip = java.io.File(filesDir, "geoip.dat")
                        val geosite = java.io.File(filesDir, "geosite.dat")

                        // If geodata is missing, try to extract it now (it's fast)
                        if (!geoip.exists() || !geosite.exists()) {
                            XrayVpnService.prepareBinaries(this)
                        }

                        // teapod-core is an AAR library — no separate binary needed
                        result.success(geoip.exists() && geosite.exists())
                    }

                    "prepareBinaries" -> {
                        Thread {
                            val success = XrayVpnService.prepareBinaries(this)
                            runOnUiThread { result.success(success) }
                        }.start()
                    }

                    "ping" -> {
                        val address = call.argument<String>("address") ?: ""
                        val port = call.argument<Int>("port") ?: 443
                        // Run ping in background thread
                        Thread {
                            val latency = pingHost(address, port)
                            runOnUiThread { result.success(latency) }
                        }.start()
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
                        val state = XrayVpnService.getNativeState()
                        val socks = if (state == "connected") {
                            XrayVpnService.getSocksCredentials()
                        } else {
                            mapOf("port" to 0, "user" to "", "password" to "")
                        }
                        result.success(mapOf(
                            "state" to state,
                            "socksPort" to socks["port"],
                            "socksUser" to socks["user"],
                            "socksPassword" to socks["password"]
                        ))
                    }

                    "getStatsHistory" -> {
                        val history = XrayVpnService.getStatsHistory()
                        result.success(history)
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

    private var pendingVpnAction: (() -> Unit)? = null

    override fun onDestroy() {
        super.onDestroy()
        VpnEventStreamHandler.appContext = null
    }

    private fun requestVpnPermission(result: MethodChannel.Result, action: () -> Unit) {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            // Need to ask for permission
            pendingResult = result
            pendingVpnAction = action
            startActivityForResult(intent, VPN_PERMISSION_REQUEST)
        } else {
            // Already have permission
            action()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_PERMISSION_REQUEST) {
            if (resultCode == Activity.RESULT_OK) {
                pendingVpnAction?.invoke()
                pendingVpnAction = null
                pendingResult = null
            } else {
                pendingResult?.error("VPN_PERMISSION_DENIED", "User denied VPN permission", null)
                pendingResult = null
                pendingVpnAction = null
            }
        }
    }

    private fun requestBatteryOptimizationExemption() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                try {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                        .setData(Uri.parse("package:$packageName"))
                    startActivity(intent)
                } catch (_: Exception) {}
            }
        }
    }

    private fun startVpnService(
        xrayConfig: String,
        socksPort: Int,
        socksUser: String,
        socksPassword: String,
        excludedPackages: List<String>,
        includedPackages: List<String>,
        vpnMode: String,
        ssPrefix: String? = null,
        proxyOnly: Boolean = false,
        showNotification: Boolean = true,
        killSwitch: Boolean = false,
        allowIcmp: Boolean = true,
    ) {
        requestBatteryOptimizationExemption()
        val intent = Intent(this, XrayVpnService::class.java).apply {
            action = XrayVpnService.ACTION_CONNECT
            putExtra(XrayVpnService.EXTRA_XRAY_CONFIG, xrayConfig)
            putExtra(XrayVpnService.EXTRA_SOCKS_PORT, socksPort)
            putExtra(XrayVpnService.EXTRA_SOCKS_USER, socksUser)
            putExtra(XrayVpnService.EXTRA_SOCKS_PASSWORD, socksPassword)
            putExtra(XrayVpnService.EXTRA_EXCLUDED_PACKAGES, ArrayList(excludedPackages))
            putExtra(XrayVpnService.EXTRA_INCLUDED_PACKAGES, ArrayList(includedPackages))
            putExtra(XrayVpnService.EXTRA_VPN_MODE, vpnMode)
            if (ssPrefix != null) putExtra(XrayVpnService.EXTRA_SS_PREFIX, ssPrefix)
            putExtra(XrayVpnService.EXTRA_PROXY_ONLY, proxyOnly)
            putExtra(XrayVpnService.EXTRA_SHOW_NOTIFICATION, showNotification)
            putExtra(XrayVpnService.EXTRA_KILL_SWITCH, killSwitch)
            putExtra(XrayVpnService.EXTRA_ALLOW_ICMP, allowIcmp)
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
            versions["xray"] = teapodcore.Teapodcore.getXrayVersion()
            versions["tun2socks"] = "teapod-core (AAR)"
        } catch (e: Exception) {
            versions["xray"] = "Error"
            versions["tun2socks"] = "Error"
        }
        return versions
    }
}
