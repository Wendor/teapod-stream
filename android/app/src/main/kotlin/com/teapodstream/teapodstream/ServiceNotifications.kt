package com.teapodstream.teapodstream

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.SystemClock
import androidx.core.app.NotificationCompat

/// The service's notification: the intermediate one for a state change ([onState], also posted by
/// the tile before the service runs), the foreground one, connected with speeds, and the kill
/// switch's block. One notification id; `showNotification` off — the minimal channel only.
class ServiceNotifications(private val service: Service, private val log: (String, String) -> Unit) {
    companion object {
        const val ID = 1
        private const val CHANNEL_ID = "vpn_service"
        private const val CHANNEL_MINIMAL_ID = "vpn_service_minimal"
        private const val MIN_INTERVAL_MS = 5_000L

        // showNotification of the last connection. null — the service in this process hasn't
        // loaded parameters yet (tile/events before the service): read from disk (issue #76).
        @Volatile private var enabledFlag: Boolean? = null
        // The last posted intermediate state: re-notify() with the same text
        // eats the update rate limit (the system silently drops extra ones), and the final
        // "connected" got lost — the notification "hung" on "Connecting…" (issue #76).
        @Volatile private var lastIntermediate: Boolean? = null
        // A constant `when`: otherwise every update lifts the notification to the top of the shade.
        private val notificationWhen = System.currentTimeMillis()

        fun enabled(context: Context): Boolean =
            enabledFlag
                ?: (QuickConnectStore(context.filesDir).params()?.showNotification ?: true).also { enabledFlag = it }

        /** The session's `showNotification` (set with its parameters). */
        fun setEnabled(value: Boolean) {
            enabledFlag = value
        }

        /** Notification on state change: intermediate for connecting/disconnecting/reconnecting. */
        @JvmStatic fun onState(context: Context, state: SessionState) {
            val connecting = when (state) {
                SessionState.CONNECTING, SessionState.RECONNECTING -> true
                SessionState.DISCONNECTING -> false
                else -> { lastIntermediate = null; return }
            }
            if (!enabled(context) || lastIntermediate == connecting) return
            try {
                val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                ensureChannels(context, manager)
                manager.notify(ID, intermediate(context, connecting))
                lastIntermediate = connecting
            } catch (_: Exception) { }
        }

        private fun intermediate(context: Context, connecting: Boolean): Notification =
            base(context, CHANNEL_ID)
                .setContentText(context.appString(if (connecting) R.string.state_connecting else R.string.state_disconnecting))
                .setProgress(0, 0, true)
                .build()

        private fun base(context: Context, channel: String): NotificationCompat.Builder =
            NotificationCompat.Builder(context, channel)
                .setContentTitle("TeapodStream VPN")
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setWhen(notificationWhen)
                .setShowWhen(false)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                // Android 12+ otherwise delays showing the FGS notification by 10 s.
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)

        private fun ensureChannels(context: Context, manager: NotificationManager) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, context.appString(R.string.channel_status_name), NotificationManager.IMPORTANCE_LOW)
                    .apply { description = context.appString(R.string.channel_status_description) }
            )
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_MINIMAL_ID, context.appString(R.string.channel_minimal_name), NotificationManager.IMPORTANCE_MIN)
                    .apply { description = context.appString(R.string.channel_minimal_description) }
            )
        }
    }

    @Volatile private var lastText: String? = null
    @Volatile private var lastMs = 0L

    private val enabled get() = enabled(service)
    private val manager get() = service.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    /**
     * Puts the service in the foreground; safe to call repeatedly. Intermediate ([connecting] or disconnecting)
     * right away — "Disconnected" during connecting was confusing; [connected] — the speeds layout of a live session.
     */
    fun foreground(connecting: Boolean = true, connected: Boolean = false) {
        ensureChannels(service, manager)
        val live = connected && enabled
        if (live) lastText = null  // the next stats tick updates the speed
        val notification = when {
            live -> connected(0, 0)
            enabled -> intermediate(service, connecting)
            else -> minimal()
        }
        lastIntermediate = if (enabled && !live) connecting else null
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                service.startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                service.startForeground(ID, notification)
            }
        } catch (e: Exception) {
            log("warning", "startForeground failed: ${e.message}")
        }
    }

    /** The session connected: the speeds layout, bypassing the dedupe of the intermediate one. */
    fun connected(screenOn: Boolean) {
        lastIntermediate = null
        refresh(0, 0, screenOn)
    }

    /** The speeds now, past the dedupe and the rate limit. */
    fun refresh(upload: Long, download: Long, screenOn: Boolean) {
        lastText = null
        speeds(upload, download, screenOn)
    }

    fun speeds(upload: Long, download: Long, screenOn: Boolean) {
        if (!enabled) return
        // notify() is an IPC into system_server on every call — skip while the screen
        // is off (SCREEN_ON refreshes once) and when the rendered text hasn't changed.
        if (!screenOn) return
        val text = speedText(upload, download)
        if (text == lastText) return
        // Every notify() wakes third-party NotificationListeners (watches, sync) —
        // at most once per 5 s; resetting the cache (null) updates right away.
        val now = SystemClock.elapsedRealtime()
        if (lastText != null && now - lastMs < MIN_INTERVAL_MS) return
        lastText = text
        lastMs = now
        manager.notify(ID, connected(upload, download))
    }

    /** The kill switch holds the TUN sink: the service stays, its notification offers to connect again. */
    fun blocked() {
        lastIntermediate = null
        if (!enabled) return
        try {
            manager.notify(ID, blockedNotification())
        } catch (_: Exception) {}
    }

    /** The service dies: a notification posted after it would stay an orphan. */
    fun cancel() {
        try { manager.cancel(ID) } catch (_: Exception) {}
    }

    private fun speedText(upload: Long, download: Long) = "↑ ${formatSpeed(upload)}  ↓ ${formatSpeed(download)}"

    private fun pendingFlags() =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else
            PendingIntent.FLAG_UPDATE_CURRENT

    private fun openIntent(): PendingIntent = PendingIntent.getActivity(service, 0,
        service.packageManager.getLaunchIntentForPackage(service.packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), pendingFlags())

    private fun connected(upload: Long, download: Long): Notification {
        val stopIntent = PendingIntent.getService(service, 0,
            Intent(service, XrayVpnService::class.java).apply { action = XrayVpnService.ACTION_DISCONNECT }, pendingFlags())
        return base(service, CHANNEL_ID)
            .setContentText(speedText(upload, download))
            .setContentIntent(openIntent())
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, service.appString(R.string.action_disconnect), stopIntent)
            .build()
    }

    private fun blockedNotification(): Notification {
        val connectIntent = PendingIntent.getService(service, 1,
            Intent(service, XrayVpnService::class.java).apply { action = XrayVpnService.ACTION_CONNECT_QUICK }, pendingFlags())
        return base(service, CHANNEL_ID)
            .setContentText(service.appString(R.string.state_kill_switch))
            .setContentIntent(openIntent())
            .addAction(android.R.drawable.ic_media_play, service.appString(R.string.action_connect), connectIntent)
            .build()
    }

    private fun minimal(): Notification =
        base(service, CHANNEL_MINIMAL_ID)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .build()
}
