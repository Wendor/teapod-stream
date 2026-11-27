package com.teapodstream.teapodstream

import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.FileProvider
import com.teapodstream.teapodstream.core.CoreKind
import com.teapodstream.teapodstream.core.VpnCores
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * The platform half of `com.teapodstream/vpn` (Dart: `PlatformService`): available cores, their versions and binaries, installed apps
 * and their icons, files dir, ABI, IP country, device id and info, battery-optimization settings, APK install.
 */
internal class PlatformChannelHandler(
    private val activity: Activity,
    private val work: ChannelWork,
    private val battery: BatteryOptimization,
) {
    val methods: Map<String, ChannelMethod> = mapOf(
        "getAvailableEngines" to { _, result ->
            result.success(CoreKind.entries.filter { VpnCores.isAvailable(it) }.map { it.id })
        },
        "getBinaryVersions" to { _, result -> work.answer(result) { binaryVersions() } },
        "prepareBinaries" to { _, result -> work.answer(result) { XrayVpnService.prepareBinaries(activity) } },
        "getInstalledApps" to { _, result -> work.answer(result) { installedApps() } },
        "getAppIcon" to { call, result ->
            val packageName = call.argument<String>("packageName")
            if (packageName == null) result.success(null) else work.answer(result) { appIcon(packageName) }
        },
        "getFilesDir" to { _, result -> result.success(activity.filesDir.absolutePath) },
        "getAbi" to { _, result -> result.success(Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a") },
        // Country of an IP by the geoip.dat the cores route with; null when unknown. Reads the whole file.
        "countryForIp" to { call, result ->
            val ip = call.argument<String>("ip") ?: ""
            work.answer(result) {
                val code = try {
                    teapodcore.Teapodcore.countryForIp(activity.filesDir.absolutePath, ip)
                } catch (_: Throwable) {
                    ""
                }
                code.ifEmpty { null }
            }
        },
        "getDeviceId" to { _, result ->
            result.success(Settings.Secure.getString(activity.contentResolver, Settings.Secure.ANDROID_ID))
        },
        "getDeviceInfo" to { _, result ->
            result.success(mapOf("model" to Build.MODEL, "osVersion" to Build.VERSION.SDK_INT))
        },
        "openBatteryOptimizationSettings" to { _, result ->
            battery.openSettings()
            result.success(null)
        },
        "installApk" to ::installApk,
    )

    private fun installApk(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("filePath") ?: run {
            result.error("INVALID_ARGS", "filePath required", null)
            return
        }
        val file = File(filePath)
        if (!file.exists()) {
            result.error("FILE_NOT_FOUND", "APK not found: $filePath", null)
            return
        }
        val packageName = activity.packageName
        if (!activity.packageManager.canRequestPackageInstalls()) {
            activity.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
            )
            result.error("PERMISSION_REQUIRED", "Install unknown apps permission needed", null)
            return
        }
        val uri = FileProvider.getUriForFile(activity, "$packageName.fileprovider", file)
        activity.startActivity(
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
            }
        )
        result.success(null)
    }

    private fun installedApps(): List<Map<String, Any?>> {
        val pm = activity.packageManager
        return pm.getInstalledPackages(0)
            .filter { it.packageName != activity.packageName }
            .mapNotNull { pkg ->
                try {
                    val appInfo = pkg.applicationInfo ?: return@mapNotNull null
                    mapOf(
                        "packageName" to pkg.packageName,
                        "appName" to pm.getApplicationLabel(appInfo).toString(),
                        "isSystem" to ((appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                    )
                } catch (_: Exception) {
                    null
                }
            }
            .sortedBy { it["appName"] as? String }
    }

    private fun appIcon(packageName: String): ByteArray? = try {
        val pm = activity.packageManager
        val drawable = pm.getApplicationInfo(packageName, 0).loadIcon(pm)
        val size = (48 * activity.resources.displayMetrics.density).toInt().coerceAtLeast(72)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(Canvas(bitmap))
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 80, stream)
        bitmap.recycle()
        stream.toByteArray()
    } catch (_: Exception) {
        null
    }

    private fun binaryVersions(): Map<String, String> {
        val versions = mutableMapOf<String, String>()
        try {
            versions.putAll(VpnCores.versions())
            versions["xray"] = VpnCores.get(XrayVpnService.snapshot.core).version()
            versions["tun2socks"] = "teapod-core (AAR)"
        } catch (_: Exception) {
            versions["xray"] = "Error"
            versions["tun2socks"] = "Error"
        }
        return versions
    }
}

/** The system "ignore battery optimizations" prompt and settings. */
internal class BatteryOptimization(private val activity: Activity) {

    /** The prompt once per install: a user who declined isn't asked on every connect. Settings → Battery opens it
     *  again ([openSettings]). */
    fun promptOnce() {
        val prefs = activity.getSharedPreferences(XrayVpnService.PREFS_NAME, Activity.MODE_PRIVATE)
        // An exempt app isn't asked and the flag stays unset: if the exemption is removed later, the next connect asks.
        if (prefs.getBoolean(PREF_PROMPT_SHOWN, false) || ignoring()) return
        // Recorded only once the prompt has opened: a failed launch is retried on the next connect.
        if (openSettings()) prefs.edit().putBoolean(PREF_PROMPT_SHOWN, true).apply()
    }

    /** The exemption prompt while the app is optimized; the system list (to revert it) once it is exempt.
     *  False when the launch failed. */
    fun openSettings(): Boolean {
        val intent = if (ignoring()) {
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        } else {
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).setData(Uri.parse("package:${activity.packageName}"))
        }
        return try {
            activity.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun ignoring(): Boolean =
        (activity.getSystemService(Activity.POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(activity.packageName)

    private companion object {
        const val PREF_PROMPT_SHOWN = "battery_prompt_shown"
    }
}
