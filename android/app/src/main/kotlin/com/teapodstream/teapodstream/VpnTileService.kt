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
        private const val PREF_CONFIG_NAME = "tile_config_name"

        /** Имя конфига quick-reconnect — его и подключит плитка; null — сброс на «TeapodStream». */
        fun saveConfigName(context: Context, name: String?) {
            context.getSharedPreferences(XrayVpnService.PREFS_NAME, Context.MODE_PRIVATE).edit()
                .putString(PREF_CONFIG_NAME, name?.takeIf { it.isNotBlank() })
                .apply()
            updateTile(context)
        }

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
        val isDisconnect = currentState in setOf("connected", "connecting", "reconnecting")
        val toggle = {
            setIntermediateState(isDisconnect)
            XrayVpnService.onStateNotification(this, if (isDisconnect) "disconnecting" else "connecting")
            startService(Intent(this, XrayVpnService::class.java).apply {
                action = if (isDisconnect) XrayVpnService.ACTION_DISCONNECT else XrayVpnService.ACTION_CONNECT_QUICK
            })
        }
        // Выключить VPN с экрана блокировки может кто угодно — только после разблокировки.
        if (isDisconnect && isLocked) unlockAndRun { toggle() } else toggle()
    }

    private fun setIntermediateState(isDisconnect: Boolean) {
        val tile = qsTile ?: return
        setTileBase(tile, active = true)
        tile.state = Tile.STATE_UNAVAILABLE
        setSubtitle(if (isDisconnect) "Отключение…" else "Подключение…")
        tile.updateTile()
    }

    private fun updateTile() {
        val tile = qsTile ?: return
        val vpnState = XrayVpnService.getNativeState()

        setTileBase(tile, active = vpnState in setOf("connected", "connecting", "reconnecting", "disconnecting", "blocked"))
        when (vpnState) {
            "connected" -> {
                tile.state = Tile.STATE_ACTIVE
                setSubtitle("Подключено")
            }
            "connecting", "reconnecting", "disconnecting" -> {
                tile.state = Tile.STATE_UNAVAILABLE
                setSubtitle(if (vpnState == "disconnecting") "Отключение…" else "Подключение…")
            }
            "blocked" -> {
                tile.state = Tile.STATE_INACTIVE
                setSubtitle("Kill switch")
            }
            else -> {
                tile.state = Tile.STATE_INACTIVE
                // Выключено: заголовок — приложение, подпись — что подключит плитка.
                setSubtitle(configName())
            }
        }
        tile.updateTile()
    }

    private fun configName(): String? =
        getSharedPreferences(XrayVpnService.PREFS_NAME, MODE_PRIVATE).getString(PREF_CONFIG_NAME, null)

    /** [active] — VPN включён или переходит: в заголовке имя конфига, иначе «TeapodStream». */
    private fun setTileBase(tile: Tile, active: Boolean) {
        tile.icon = Icon.createWithResource(this, R.drawable.ic_vpn_tile)
        tile.label = configName()?.takeIf { active } ?: "TeapodStream"
    }

    private fun setSubtitle(text: String?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            qsTile?.subtitle = text
        }
    }
}
