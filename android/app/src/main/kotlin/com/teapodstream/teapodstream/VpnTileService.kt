package com.teapodstream.teapodstream

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.N)
class VpnTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        registerTileService(this)
        updateTile()
    }

    override fun onStopListening() {
        super.onStopListening()
        unregisterTileService()
    }

    fun requestUpdate() = updateTile()

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

    override fun onClick() {
        super.onClick()
        val currentState = XrayVpnService.getNativeState()
        val isDisconnect = currentState == "connected" || currentState == "connecting"

        setIntermediateState(isDisconnect)

        val intent = Intent(this, XrayVpnService::class.java).apply {
            action = if (isDisconnect) XrayVpnService.ACTION_DISCONNECT else XrayVpnService.ACTION_CONNECT_QUICK
        }
        startService(intent)
    }

    private fun setIntermediateState(isDisconnect: Boolean) {
        val tile = qsTile ?: return
        setTileBase(tile)
        tile.state = Tile.STATE_UNAVAILABLE
        setSubtitle(if (isDisconnect) "Отключение…" else "Подключение…")
        tile.updateTile()
    }

    private fun updateTile() {
        val tile = qsTile ?: return
        val vpnState = XrayVpnService.getNativeState()

        setTileBase(tile)
        when (vpnState) {
            "connected" -> {
                tile.state = Tile.STATE_ACTIVE
                setSubtitle("Подключено")
            }
            "connecting", "disconnecting" -> {
                tile.state = Tile.STATE_UNAVAILABLE
                setSubtitle(if (vpnState == "connecting") "Подключение…" else "Отключение…")
            }
            "blocked" -> {
                tile.state = Tile.STATE_INACTIVE
                setSubtitle("Kill switch")
            }
            else -> {
                tile.state = Tile.STATE_INACTIVE
                setSubtitle(null)
            }
        }
        tile.updateTile()
    }

    private fun setTileBase(tile: Tile) {
        tile.icon = Icon.createWithResource(this, R.drawable.ic_vpn_tile)
        tile.label = "TeapodStream"
    }

    private fun setSubtitle(text: String?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            qsTile?.subtitle = text
        }
    }
}
