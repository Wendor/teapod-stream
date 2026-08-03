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
    // Контекст приложения для обновления Quick Settings плитки — WeakReference чтобы не удерживать Activity
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
                // Send stats history for chart
                val history = XrayVpnService.getStatsHistory()
                if (history.isNotEmpty()) {
                    sendEvent(mapOf(
                        "type" to "statsHistory",
                        "history" to history,
                    ))
                }
            }
            "connecting", "disconnecting", "reconnecting", "blocked" -> sendStateEvent(state)
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
        sendEvent(mapOf("type" to "state", "value" to state))
        // Обновляем плитку и уведомление при изменении состояния
        appContext?.let { ctx ->
            VpnTileService.updateTile(ctx)
            if (state == "connecting" || state == "disconnecting" || state == "reconnecting") {
                XrayVpnService.showIntermediateNotification(ctx, state != "disconnecting")
            }
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
            // Какое сетевое правило применил native — Flutter показывает именно этот сервер.
            "networkProfile" to (XrayVpnService.activeProfile ?: ""),
            // Фактический транспорт сессии — для подписи «Wi-Fi · правило недоступно».
            "networkTransport" to XrayVpnService.currentTransport(),
        ))
        appContext?.let { VpnTileService.updateTile(it) }
    }

    fun sendLogEvent(level: String, message: String) {
        sendEvent(mapOf("type" to "log", "level" to level, "message" to message))
    }

    fun sendDeeplinkEvent(uri: String) {
        sendEvent(mapOf("type" to "deeplink", "uri" to uri))
    }

    /// Туннель не отвечает, а режим heartbeat — urltest: Flutter должен подобрать
    /// живой конфиг и переподключиться. Если он молчит, сервис сам реконнектится.
    fun sendTunnelDeadEvent(failures: Int) {
        sendEvent(mapOf("type" to "tunnel_dead", "failures" to failures))
    }
}
