package com.teapodstream.teapodstream

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import com.teapodstream.teapodstream.core.CoreKind
import com.teapodstream.teapodstream.core.VpnCores
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * The VPN half of `com.teapodstream/vpn` (Dart: `XrayEngine`): connect and disconnect with the VPN permission,
 * the quick-connect data, state, stats, ping and measurements, logs.
 */
internal class VpnChannelHandler(
    private val activity: Activity,
    private val work: ChannelWork,
    private val battery: BatteryOptimization,
) {
    private val pendingVpnStart = PendingVpnStart()
    private val quickConnect = QuickConnectRequests(
        QuickConnectStore(activity.filesDir),
        XrayVpnService.sessionStarts::get,
    ) { VpnTileService.configNameChanged(activity.applicationContext) }
    private val filesDir: File get() = activity.filesDir

    val methods: Map<String, ChannelMethod> = mapOf(
        "connect" to ::connect,
        "disconnect" to { _, result ->
            // A connect still waiting for the permission dialog must not start after this.
            pendingVpnStart.cancel(PendingVpnStart.CANCELLED)
            startService(Intent(activity, XrayVpnService::class.java).setAction(XrayVpnService.ACTION_DISCONNECT))
            result.success(null)
        },
        "saveQuickConnect" to ::saveQuickConnect,
        "clearQuickConnect" to { _, result ->
            val seen = XrayVpnService.sessionStarts.get()
            if (sessionRunning()) result.success(false)
            else work.answer(result, ChannelWork.quickConnect) { quickConnect.clear(seen) }
        },
        // The same map as the `state` event: Flutter parses both with one parser
        "getState" to { _, result -> result.success(XrayVpnService.snapshot.toMap()) },
        // With `epoch`, also the chart history after `since` in `history`: the home tab's poll is one call a second.
        "getStats" to { call, result ->
            val stats: MutableMap<String, Any> = SessionStats.get().toMutableMap()
            call.argument<Int>("epoch")?.let { stats["history"] = history(it, call) }
            result.success(stats)
        },
        "getStatsHistory" to { call, result -> result.success(history(call.argument<Int>("epoch") ?: -1, call)) },
        "getTunnelDiag" to { _, result -> result.success(VpnCores.get(XrayVpnService.snapshot.core).diagnostics()) },
        "ping" to { call, result ->
            val address = call.argument<String>("address") ?: ""
            val port = call.argument<Int>("port") ?: 443
            work.answer(result, ChannelWork.ping) { icmpPing(address) ?: tcpPing(address, port) }
        },
        // A real latency measurement through a candidate: brings up a temporary core instance with its config.
        // Unlike a TCP ping it sees that the server is alive at the protocol level, not just listening on the port.
        "measureOutbound" to { call, result ->
            val config = call.argument<String>("config") ?: ""
            val url = call.argument<String>("url") ?: ""
            val engine = call.argument<String>("engine")
            work.answer(result, ChannelWork.measure) {
                val latency = try {
                    VpnCores.get(CoreKind.fromId(engine)).measureOutbound(activity.applicationContext, config, url)
                } catch (_: Exception) {
                    -1L
                }
                if (latency >= 0) latency.toInt() else null
            }
        },
        "getLogFilePath" to { _, result ->
            result.success("${filesDir.absolutePath}/${ServiceLog.FILE_NAME}")
        },
        "setLogsEnabled" to { call, result ->
            val enabled = call.argument<Boolean>("enabled") ?: true
            activity.getSharedPreferences(XrayVpnService.PREFS_NAME, Activity.MODE_PRIVATE)
                .edit().putBoolean(ServiceLog.PREF_ENABLED, enabled).apply()
            ServiceLog.enabled = enabled
            result.success(null)
        },
        "getLogs" to { _, result ->
            work.answer(result) {
                synchronized(ServiceLog.LOCK) {
                    ServiceLog.flush(filesDir)
                    listOf(ServiceLog.PREV_FILE_NAME, ServiceLog.FILE_NAME)
                        .map { File(filesDir, it) }
                        .filter { it.exists() }
                        .flatMap { it.readLines() }
                        .filter { it.isNotBlank() }
                        .takeLast(2000)
                }
            }
        },
        "clearLogs" to { _, result ->
            work.answer(result) {
                try {
                    synchronized(ServiceLog.LOCK) {
                        ServiceLog.flush(filesDir)
                        File(filesDir, ServiceLog.FILE_NAME).writeText("")
                        File(filesDir, ServiceLog.PREV_FILE_NAME).delete()
                    }
                } catch (_: Exception) {
                }
                null
            }
        },
    )

    /** The VPN-permission dialog answered ([Activity.onActivityResult] for [VPN_PERMISSION_REQUEST]). */
    fun onPermissionResult(granted: Boolean) = pendingVpnStart.complete(granted)

    private fun connect(call: MethodCall, result: MethodChannel.Result) {
        val args = ConnectArgs.from(call.arguments as? Map<*, *> ?: emptyMap<String, Any>()) ?: run {
            result.error("INVALID_ARGS", "xrayConfig required", null)
            return
        }
        val start = {
            battery.promptOnce()
            startService(
                Intent(activity, XrayVpnService::class.java).setAction(XrayVpnService.ACTION_CONNECT)
                    .putExtra(XrayVpnService.EXTRA_XRAY_CONFIG, args.config)
                    .putExtra(XrayVpnService.EXTRA_SOCKS_USER, args.socksUser)
                    .putExtra(XrayVpnService.EXTRA_SOCKS_PASSWORD, args.socksPassword)
                    .putExtra(XrayVpnService.EXTRA_PARAMS, args.params.toJson().toString())
                    .putExtra(XrayVpnService.EXTRA_CONFIG_NAME, args.configName)
                    .putExtra(XrayVpnService.EXTRA_ATTEMPT, args.attempt)
            )
            result.success(null)
        }
        // Proxy-only: no TUN, no VPN permission needed.
        val permission = if (args.params.proxyOnly) null else VpnService.prepare(activity)
        if (permission == null) {
            pendingVpnStart.cancel(PendingVpnStart.SUPERSEDED)
            start()
            return
        }
        // A connect arriving while the dialog is open replaces the waiting one.
        val reject = { code: String ->
            val message = if (code == PendingVpnStart.DENIED) "User denied VPN permission" else "VPN start $code"
            result.error(code, message, null)
        }
        if (pendingVpnStart.offer(start, reject)) {
            try {
                @Suppress("DEPRECATION")
                activity.startActivityForResult(permission, VPN_PERMISSION_REQUEST)
            } catch (e: Exception) {
                android.util.Log.w("TeapodVPN", "VPN permission dialog failed: ${e.message}")
                pendingVpnStart.dialogFailed()
            }
        }
    }

    // Re-saves the quick-reconnect data (tile, autostart) without connecting: on a core change while disconnected.
    // During a session — a no-op.
    private fun saveQuickConnect(call: MethodCall, result: MethodChannel.Result) {
        val seen = XrayVpnService.sessionStarts.get()
        if (sessionRunning()) {
            result.success(false)
            return
        }
        val args = ConnectArgs.from(call.arguments as? Map<*, *> ?: emptyMap<String, Any>()) ?: run {
            result.error("INVALID_ARGS", "xrayConfig required", null)
            return
        }
        work.answer(result, ChannelWork.quickConnect) { quickConnect.save(args, seen) }
    }

    /** The chart points after the call's `since` of [epoch] ([SessionStats.history]). */
    private fun history(epoch: Int, call: MethodCall) =
        SessionStats.history(epoch, (call.argument<Number>("since") ?: 0).toLong())

    private fun sessionRunning() = !XrayVpnService.snapshot.state.isOff

    private fun startService(intent: Intent) {
        activity.startForegroundService(intent)
    }

    private fun icmpPing(address: String): Int? {
        if (!isPingableAddress(address)) return null
        return try {
            val proc = Runtime.getRuntime().exec(arrayOf("ping", "-c", "1", "-w", "3", address))
            val exited = proc.waitFor(5, java.util.concurrent.TimeUnit.SECONDS)
            if (!exited || proc.exitValue() != 0) {
                proc.destroy()
                return null
            }
            val output = proc.inputStream.bufferedReader().readText()
            Regex("time=(\\d+\\.?\\d*)").find(output)?.groupValues?.get(1)?.toFloatOrNull()?.toInt()
        } catch (_: Exception) {
            null
        }
    }

    private fun tcpPing(address: String, port: Int): Int? = try {
        val start = System.currentTimeMillis()
        java.net.Socket().use { it.connect(java.net.InetSocketAddress(address, port), 5000) }
        (System.currentTimeMillis() - start).toInt()
    } catch (_: Exception) {
        null
    }

    companion object {
        const val VPN_PERMISSION_REQUEST = 1001
    }
}

/**
 * Flutter's quick-connect save and clear, checked while no session ran. [seen] is [sessionStarts] at that check: a
 * session started since then owns the stored data, so the write is dropped (false). The check and the write are one
 * step under the store's lock, which the session's own save also takes; the tile is told after the lock is released.
 */
internal class QuickConnectRequests(
    private val store: QuickConnectStore,
    private val sessionStarts: () -> Long,
    private val tileNameChanged: () -> Unit,
) {
    fun save(args: ConnectArgs, seen: Long): Boolean {
        var admitted = false
        try {
            return store.locked {
                if (sessionStarts() != seen) return@locked false
                admitted = true
                store.save(args.config, args.params, tileName = args.configName ?: "")
                true
            }
        } finally {
            // Also after a failed save: it may have removed the old name.
            if (admitted) tileNameChanged()
        }
    }

    fun clear(seen: Long): Boolean = store.locked {
        if (sessionStarts() != seen) return@locked false
        store.clear()
        true
    }.also { if (it) tileNameChanged() }
}
