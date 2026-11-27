package com.teapodstream.teapodstream

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

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
        @Volatile
        private var tileService: VpnTileService? = null
        private val main = android.os.Handler(android.os.Looper.getMainLooper())
        /** Where the name was kept before [QuickConnectStore]. */
        private const val LEGACY_PREF_CONFIG_NAME = "tile_config_name"

        /**
         * Moves a name kept before [QuickConnectStore] into it (unless the store has one) and drops the old one, in
         * one step under the store's lock: a save or quick start never sees both. Run before anything reads or writes
         * the name (the activity, the service, the tile).
         */
        fun migrateLegacyConfigName(context: Context) {
            val prefs = context.getSharedPreferences(XrayVpnService.PREFS_NAME, Context.MODE_PRIVATE)
            if (!prefs.contains(LEGACY_PREF_CONFIG_NAME)) return
            val store = QuickConnectStore(context.filesDir)
            store.locked {
                store.adoptLegacyTileName(prefs.getString(LEGACY_PREF_CONFIG_NAME, null))
                prefs.edit().remove(LEGACY_PREF_CONFIG_NAME).commit()
            }
        }

        /** The name in [QuickConnectStore] changed (saved with the quick-connect data): the tile shows it. From any
         *  thread: the tile is updated on the main one. */
        fun configNameChanged(context: Context) {
            val app = context.applicationContext
            main.post { updateTile(app) }
        }

        fun registerTileService(service: VpnTileService) {
            tileService = service
        }

        fun unregisterTileService() {
            tileService = null
        }

        fun updateTile(context: Context) {
            tileService?.requestUpdate() ?: run {
                try {
                    TileService.requestListeningState(
                        context,
                        ComponentName(context, VpnTileService::class.java)
                    )
                } catch (_: Exception) { }
            }
        }
    }

    override fun onClick() {
        super.onClick()
        val isDisconnect = XrayVpnService.snapshot.state in
            setOf(SessionState.CONNECTED, SessionState.CONNECTING, SessionState.RECONNECTING)
        val toggle = {
            setIntermediateState(isDisconnect)
            ServiceNotifications.onState(this, if (isDisconnect) SessionState.DISCONNECTING else SessionState.CONNECTING)
            startService(Intent(this, XrayVpnService::class.java).apply {
                action = if (isDisconnect) XrayVpnService.ACTION_DISCONNECT else XrayVpnService.ACTION_CONNECT_QUICK
            })
        }
        // Anyone can turn the VPN off from the lock screen — only after unlocking.
        if (isDisconnect && isLocked) unlockAndRun { toggle() } else toggle()
    }

    private fun setIntermediateState(isDisconnect: Boolean) {
        val tile = qsTile ?: return
        setTileBase(tile, active = true)
        tile.state = Tile.STATE_UNAVAILABLE
        setSubtitle(appString(if (isDisconnect) R.string.state_disconnecting else R.string.state_connecting))
        tile.updateTile()
    }

    private fun updateTile() {
        val tile = qsTile ?: return
        val vpnState = XrayVpnService.snapshot.state

        setTileBase(tile, active = vpnState != SessionState.DISCONNECTED && vpnState != SessionState.ERROR)
        when (vpnState) {
            SessionState.CONNECTED -> {
                tile.state = Tile.STATE_ACTIVE
                setSubtitle(appString(R.string.state_connected))
            }
            SessionState.CONNECTING, SessionState.RECONNECTING, SessionState.DISCONNECTING -> {
                tile.state = Tile.STATE_UNAVAILABLE
                setSubtitle(appString(
                    if (vpnState == SessionState.DISCONNECTING) R.string.state_disconnecting else R.string.state_connecting))
            }
            SessionState.BLOCKED -> {
                tile.state = Tile.STATE_INACTIVE
                setSubtitle("Kill switch")
            }
            SessionState.DISCONNECTED, SessionState.ERROR -> {
                tile.state = Tile.STATE_INACTIVE
                // Off: the title is the app, the subtitle is what the tile will connect.
                setSubtitle(configName())
            }
        }
        tile.updateTile()
    }

    private fun configName(): String? {
        migrateLegacyConfigName(this)
        return QuickConnectStore(filesDir).tileName()
    }

    /** [active] — VPN is on or transitioning: the title is the config name, otherwise "TeapodStream". */
    private fun setTileBase(tile: Tile, active: Boolean) {
        tile.icon = Icon.createWithResource(this, R.drawable.ic_vpn_tile)
        tile.label = configName()?.takeIf { active } ?: "TeapodStream"
    }

    private fun setSubtitle(text: String?) {
        qsTile?.subtitle = text
    }
}
