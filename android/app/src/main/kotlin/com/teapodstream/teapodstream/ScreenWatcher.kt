package com.teapodstream.teapodstream

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.PowerManager

/// Screen and Doze state for the service's threads: the heartbeat and the stats poll slow down
/// with the screen off; only the heartbeat skips its iterations in deep Doze. [onScreenOn] runs on the main thread when the screen
/// turns on, [onWake] on screen on and on leaving Doze.
internal class ScreenWatcher(
    private val context: Context,
    private val log: (String, String) -> Unit,
    private val onScreenOn: () -> Unit,
    private val onWake: () -> Unit,
) {
    @Volatile var screenOn = true
        private set
    @Volatile var deviceIdle = false
        private set
    private var receiver: BroadcastReceiver? = null

    fun register() {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        screenOn = pm.isInteractive
        deviceIdle = idle(pm)
        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    Intent.ACTION_SCREEN_OFF -> {
                        screenOn = false
                        log("info", "Screen off")
                    }
                    Intent.ACTION_SCREEN_ON -> {
                        screenOn = true
                        log("info", "Screen on")
                        onScreenOn()
                        onWake()
                    }
                    PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED -> {
                        val idle = idle(context.getSystemService(Context.POWER_SERVICE) as PowerManager)
                        deviceIdle = idle
                        log("info", "Doze mode: ${if (idle) "entered" else "exited"}")
                        // Leaving Doze = a maintenance window or wake-up: if TUN
                        // was silent for long, the tunnel might have gone stale — probe as on SCREEN_ON.
                        if (!idle) onWake()
                    }
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
        }
        context.registerReceiver(receiver, filter)
    }

    fun unregister() {
        try { receiver?.let(context::unregisterReceiver) } catch (_: Exception) {}
        receiver = null
    }

    private fun idle(pm: PowerManager) = pm.isDeviceIdleMode
}
