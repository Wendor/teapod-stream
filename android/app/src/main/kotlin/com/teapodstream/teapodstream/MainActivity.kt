package com.teapodstream.teapodstream

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val METHOD_CHANNEL = "com.teapodstream/vpn"
        private const val EVENT_CHANNEL = "com.teapodstream/vpn/events"
    }

    private var vpnChannel: VpnChannelHandler? = null
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

        // Before the channel can save a name.
        VpnTileService.migrateLegacyConfigName(this)
        // Method channel for Flutter → native calls: one channel, two handlers (Dart: XrayEngine, PlatformService).
        val work = ChannelWork(Handler(Looper.getMainLooper())::post)
        val battery = BatteryOptimization(this)
        val vpn = VpnChannelHandler(this, work, battery).also { vpnChannel = it }
        val methods = vpn.methods + PlatformChannelHandler(this, work, battery).methods
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                methods[call.method]?.invoke(call, result) ?: result.notImplemented()
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

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VpnChannelHandler.VPN_PERMISSION_REQUEST) {
            vpnChannel?.onPermissionResult(granted = resultCode == Activity.RESULT_OK)
        }
    }
}
