package com.teapodstream.teapodstream

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != "android.intent.action.QUICKBOOT_POWERON"
        ) return

        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("flutter.auto_start_on_boot", false)) return

        // Not after the user turned the VPN off, and not without a saved connection.
        val store = QuickConnectStore(context.filesDir, KeystoreCipher)
        if (store.userOff() || store.params() == null || store.config() == null) return

        context.startForegroundService(
            Intent(context, XrayVpnService::class.java).apply {
                action = XrayVpnService.ACTION_CONNECT_QUICK
            }
        )
    }
}
