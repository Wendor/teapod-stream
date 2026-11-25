package com.teapodstream.teapodstream

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Singleton EventChannel stream handler.
 * The VpnService calls sendEvent() to push events to Flutter; session states come only from its publish().
 */
object VpnEventStreamHandler : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null
    private val handler = Handler(Looper.getMainLooper())
    private val eventBuffer = mutableListOf<Map<String, Any?>>()

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        // Flush buffered events
        synchronized(eventBuffer) {
            for (event in eventBuffer) {
                sendEventInternal(event)
            }
            eventBuffer.clear()
        }
        // Replay the current session (the state event's map) and, when connected, the stats
        val snapshot = XrayVpnService.snapshot
        sendEvent(snapshot.toMap())
        if (snapshot.state == SessionState.CONNECTED) {
            // Send current stats
            val currentStats = SessionStats.get()
            sendEvent(mapOf(
                "type" to "stats",
                "upload" to currentStats["upload"],
                "download" to currentStats["download"],
                "uploadSpeed" to currentStats["uploadSpeed"],
                "downloadSpeed" to currentStats["downloadSpeed"],
            ))
            // The whole chart history buffer (full) — the client syncs the epoch
            sendEvent(SessionStats.history(-1, 0) + ("type" to "statsHistory"))
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
