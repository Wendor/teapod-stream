package com.teapodstream.teapodstream

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import java.lang.ref.WeakReference

/**
 * Singleton EventChannel stream handler.
 * The VpnService calls sendEvent() to push events to Flutter.
 */
object VpnEventStreamHandler : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null
    private val handler = Handler(Looper.getMainLooper())
    private val eventBuffer = mutableListOf<Map<String, Any?>>()
    // Application context for the tile and notifications; not cleared when the UI closes —
    // the service updates them without an Activity (WeakReference: holding an Activity is not allowed)
    private var _appContextRef: WeakReference<android.content.Context>? = null
    var appContext: android.content.Context?
        get() = _appContextRef?.get()
        set(value) { _appContextRef = if (value != null) WeakReference(value) else null }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        // Flush buffered events
        synchronized(eventBuffer) {
            for (event in eventBuffer) {
                sendEventInternal(event)
            }
            eventBuffer.clear()
        }
        // Replay current state and stats when Flutter starts listening
        val state = XrayVpnService.getNativeState()
        when (state) {
            "connected" -> {
                sendConnectedEvent(
                    XrayVpnService.activeSocksPort,
                    XrayVpnService.activeSocksUser,
                    XrayVpnService.activeSocksPassword,
                )
                // Send current stats
                val currentStats = XrayVpnService.getStats()
                sendEvent(mapOf(
                    "type" to "stats",
                    "upload" to currentStats["upload"],
                    "download" to currentStats["download"],
                    "uploadSpeed" to currentStats["uploadSpeed"],
                    "downloadSpeed" to currentStats["downloadSpeed"],
                ))
                // The whole chart history buffer (full) — the client syncs the epoch
                sendEvent(XrayVpnService.getStatsHistory(-1, 0) + ("type" to "statsHistory"))
            }
            "connecting", "disconnecting", "reconnecting", "blocked", "error" -> sendStateEvent(state)
            else -> sendStateEvent("disconnected")
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun sendEvent(event: Map<String, Any?>) {
        handler.post {
            if (eventSink != null) {
                sendEventInternal(event)
            } else {
                synchronized(eventBuffer) {
                    if (eventBuffer.size < 500) {
                        eventBuffer.add(event)
                    }
                }
            }
        }
    }

    private fun sendEventInternal(event: Map<String, Any?>) {
        try {
            eventSink?.success(event)
        } catch (e: Exception) {
            android.util.Log.e("VpnEventStreamHandler", "Error sending event: ${e.message}")
        }
    }

    fun sendStateEvent(state: String) {
        val error = XrayVpnService.lastError?.takeIf { state == "error" || state == "blocked" }
        sendEvent(mapOf("type" to "state", "value" to state, "error" to error) + attemptField())
        ItestBridge.state(state)
        // Update the tile and notification on state change
        appContext?.let { ctx ->
            VpnTileService.updateTile(ctx)
            XrayVpnService.onStateNotification(ctx, state)
        }
    }

    fun sendConnectedEvent(socksPort: Int, socksUser: String, socksPassword: String) {
        sendEvent(mapOf(
            "type" to "state",
            "value" to "connected",
            "socksPort" to socksPort,
            "socksUser" to socksUser,
            "socksPassword" to socksPassword,
            "connectedAtMs" to XrayVpnService.connectedAtMs,
        ) + attemptField())
        ItestBridge.emit(mapOf(
            "ev" to "state", "value" to "connected", "t" to System.currentTimeMillis(),
            "socksPort" to socksPort, "socksUser" to socksUser, "socksPassword" to socksPassword,
        ))
        appContext?.let { VpnTileService.updateTile(it) }
    }

    /** The session's connect attempt, when Flutter started it; see [XrayVpnService.sessionAttempt]. */
    private fun attemptField(): Map<String, Any?> =
        XrayVpnService.sessionAttempt.takeIf { it > 0 }?.let { mapOf("attempt" to it) } ?: emptyMap()

    fun sendLogEvent(level: String, message: String) {
        sendEvent(mapOf("type" to "log", "level" to level, "message" to message))
    }

    fun sendDeeplinkEvent(uri: String) {
        sendEvent(mapOf("type" to "deeplink", "uri" to uri))
    }

    /// The tunnel doesn't answer and the heartbeat mode is urltest: Flutter must pick
    /// a live config and reconnect. If it stays silent, the service reconnects itself.
    fun sendTunnelDeadEvent(failures: Int) {
        sendEvent(mapOf("type" to "tunnel_dead", "failures" to failures))
    }
}
