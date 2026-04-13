package com.teapodstream.teapodstream

import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

/**
 * Quick Settings плитка для управления VPN из шторки уведомлений.
 * Позволяет включать/выключать VPN одним нажатием.
 */
@RequiresApi(Build.VERSION_CODES.N)
class VpnTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTile()
    }

    override fun onClick() {
        super.onClick()
        val currentState = XrayVpnService.getNativeState()

        if (currentState == "connected" || currentState == "connecting") {
            // Отключаем VPN
            val intent = Intent(this, XrayVpnService::class.java).apply {
                action = XrayVpnService.ACTION_DISCONNECT
            }
            startService(intent)
        } else {
            // Подключаем VPN через ACTION_CONNECT_QUICK —
            // сервис сам загрузит сохранённый конфиг или откроет приложение
            val connectIntent = Intent(this, XrayVpnService::class.java).apply {
                action = XrayVpnService.ACTION_CONNECT_QUICK
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(connectIntent)
            } else {
                startService(connectIntent)
            }
        }
    }

    /** Открывает приложение (fallback, если нет конфига или разрешения). */
    private fun openApp() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        launchIntent?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra("action", "connect")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(
                android.app.PendingIntent.getActivity(
                    this@VpnTileService, 0, launchIntent!!,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
                )
            )
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(launchIntent)
        }
    }

    /**
     * Обновляет состояние плитки в соответствии с текущим состоянием VPN.
     */
    private fun updateTile() {
        val tile = qsTile ?: return
        val vpnState = XrayVpnService.getNativeState()

        when (vpnState) {
            "connected" -> {
                tile.state = Tile.STATE_ACTIVE
                tile.label = "VPN включён"
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    tile.subtitle = "Нажмите для отключения"
                }
            }
            "connecting" -> {
                tile.state = Tile.STATE_ACTIVE
                tile.label = "VPN"
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    tile.subtitle = "Подключение..."
                }
            }
            else -> {
                tile.state = Tile.STATE_INACTIVE
                tile.label = "VPN выключен"
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    tile.subtitle = "Нажмите для включения"
                }
            }
        }
        tile.updateTile()
    }
}
