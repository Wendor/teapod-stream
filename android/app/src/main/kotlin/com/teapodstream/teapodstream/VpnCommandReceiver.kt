package com.teapodstream.teapodstream

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class VpnCommandReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Receiver is exported: without the option any app could turn off the VPN
        // and see the real IP.
        if (!XrayVpnService.automationEnabled(context)) return
        val serviceAction = when (intent.action) {
            ACTION_CONNECT -> XrayVpnService.ACTION_CONNECT_QUICK
            ACTION_DISCONNECT -> XrayVpnService.ACTION_DISCONNECT
            else -> return
        }
        context.startForegroundService(
            Intent(context, XrayVpnService::class.java).apply { action = serviceAction }
        )
    }

    companion object {
        const val ACTION_CONNECT = "com.teapodstream.CONNECT"
        const val ACTION_DISCONNECT = "com.teapodstream.DISCONNECT"
    }
}
