package com.teapodstream.teapodstream

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.drawable.Icon
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import java.io.File
import java.lang.ref.WeakReference

@RequiresApi(Build.VERSION_CODES.N)
class VpnTileService : TileService() {

    private var stateReceiver: BroadcastReceiver? = null

    override fun onStartListening() {
        super.onStartListening()
        registerTileService(this)
        updateTile()

        // Register broadcast receiver to respond immediately to state changes from XrayVpnService
        if (stateReceiver == null) {
            stateReceiver = StateReceiver(this)
            val filter = IntentFilter("com.teapodstream.STATE_CHANGED")
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    registerReceiver(stateReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
                } else {
                    registerReceiver(stateReceiver, filter)
                }
            } catch (_: Exception) {
                try {
                    registerReceiver(stateReceiver, filter)
                } catch (_: Exception) {}
            }
        }
    }

    override fun onStopListening() {
        super.onStopListening()
        unregisterTileService()
        stateReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {}
            stateReceiver = null
        }
    }

    override fun onClick() {
        super.onClick()
        val currentState = XrayVpnService.getNativeState()
        val isDisconnect = currentState == "connected" || currentState == "connecting"

        val tile = qsTile

        if (isDisconnect) {
            // Disconnect requested
            if (tile != null) {
                tile.state = Tile.STATE_INACTIVE
                tile.label = "TeapodStream"
                setSubtitle("Отключение…")
                tile.updateTile()
            }
            val intent = Intent(this, XrayVpnService::class.java).apply {
                action = XrayVpnService.ACTION_DISCONNECT
            }
            startService(intent)
        } else {
            // Connect requested
            // 1. Check if system VPN permission is granted
            if (VpnService.prepare(this) != null) {
                openAppAndCollapse()
                return
            }

            // 2. Check if configuration file exists
            val configFile = File(filesDir, "xray_config.json")
            if (!configFile.exists() || configFile.length() == 0L) {
                openAppAndCollapse()
                return
            }

            // 3. Connect via XrayVpnService
            if (tile != null) {
                tile.state = Tile.STATE_ACTIVE
                tile.label = "TeapodStream"
                setSubtitle("Подключение…")
                tile.updateTile()
            }
            val intent = Intent(this, XrayVpnService::class.java).apply {
                action = XrayVpnService.ACTION_CONNECT_QUICK
            }
            try {
                ContextCompat.startForegroundService(this, intent)
            } catch (e: Exception) {
                try {
                    startService(intent)
                } catch (_: Exception) {}
            }
        }
    }

    private fun openAppAndCollapse() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        } ?: return

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                val pendingIntent = PendingIntent.getActivity(
                    this,
                    0,
                    launchIntent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
                startActivityAndCollapse(pendingIntent)
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(launchIntent)
            }
        } catch (_: Exception) {
            try {
                startActivity(launchIntent)
            } catch (_: Exception) {}
        }
    }

    fun requestUpdate() = updateTile()

    private fun updateTile() {
        val tile = qsTile ?: return
        val vpnState = XrayVpnService.getNativeState()
        val cfgName = XrayVpnService.getActiveConfigName(this)

        tile.icon = Icon.createWithResource(this, R.drawable.ic_vpn_tile)

        when (vpnState) {
            "connected" -> {
                tile.state = Tile.STATE_ACTIVE
                tile.label = if (!cfgName.isNullOrBlank()) cfgName else "TeapodStream"
                setSubtitle("Подключено")
            }
            "connecting", "reconnecting" -> {
                tile.state = Tile.STATE_ACTIVE
                tile.label = "TeapodStream"
                setSubtitle("Подключение…")
            }
            "disconnecting" -> {
                tile.state = Tile.STATE_INACTIVE
                tile.label = "TeapodStream"
                setSubtitle("Отключение…")
            }
            "blocked" -> {
                tile.state = Tile.STATE_INACTIVE
                tile.label = "TeapodStream"
                setSubtitle("Kill switch")
            }
            else -> {
                tile.state = Tile.STATE_INACTIVE
                tile.label = "TeapodStream"
                setSubtitle(null)
            }
        }
        tile.updateTile()
    }

    private fun setSubtitle(text: String?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            qsTile?.subtitle = text
        }
    }

    private class StateReceiver(service: VpnTileService) : BroadcastReceiver() {
        private val ref = WeakReference(service)
        override fun onReceive(context: Context?, intent: Intent?) {
            ref.get()?.requestUpdate()
        }
    }

    companion object {
        private var tileService: VpnTileService? = null

        fun registerTileService(service: VpnTileService) {
            tileService = service
        }

        fun unregisterTileService() {
            tileService = null
        }

        fun updateTile(context: Context) {
            tileService?.requestUpdate() ?: run {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    try {
                        TileService.requestListeningState(
                            context,
                            ComponentName(context, VpnTileService::class.java)
                        )
                    } catch (_: Exception) { }
                }
            }
        }
    }
}
