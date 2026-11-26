package com.teapodstream.teapodstream

import com.teapodstream.teapodstream.core.VpnCore
import java.util.concurrent.atomic.AtomicBoolean

/// The heartbeat thread of a running session and the probe on wake: probes the tunnel and applies
/// [HeartbeatPolicy]'s decisions through [Host]. One thread at a time; [start] replaces it.
internal class Heartbeat(private val host: Host) {
    interface Host {
        val running: Boolean
        /** TUN mode (not proxy-only): tun2socks runs and its metrics are meaningful. */
        val tunMode: Boolean
        val screenOn: Boolean
        val deviceIdle: Boolean
        val core: VpnCore
        val params: ConnectionParams?
        /** When the running session connected (0 — none): a wake probe's reconnect is bound to it. */
        val connectedAt: Long
        /** The physical network reaches the internet (not through the tunnel). */
        fun directInternet(): Boolean
        /** Reconnect the stored session; [session] — only while that session is the connected one. */
        fun reconnect(session: Long?)
        fun log(level: String, message: String)
    }

    private var thread: Thread? = null
    @Volatile private var current: HeartbeatPolicy? = null
    private val wakeProbeRunning = AtomicBoolean(false)

    // How we probe the tunnel: "socks" (HTTP via SOCKS5), "xrayDelay" (measured inside
    // the core) or "passive" (only tun2socks metrics, no active probes).
    private val probeKind get() = host.params?.heartbeatProbe ?: "socks"
    // Behavior on a dead tunnel: "reconnect" — reconnect to the same server,
    // "switchConfig" — leave the decision to Flutter (it picks a live config).
    private val switchConfig get() = host.params?.heartbeatAction == "switchConfig"
    private val threshold get() = host.params?.heartbeatThreshold ?: 3
    private val url get() = host.params?.heartbeatUrl ?: ConnectionParams.DEFAULT_HEARTBEAT_URL

    /// Screen on or Doze exit: a TUN idle for the stall timeout may be a stale tunnel — probe it
    /// (off the main thread) and reconnect only if the probe fails.
    fun probeOnWake() {
        if (!host.tunMode || !host.running) return
        val lastRx = host.core.lastRxActivityMs()
        if (lastRx <= 0) return
        val idleSec = (System.currentTimeMillis() - lastRx) / 1000
        if (idleSec < HeartbeatPolicy.TUN_STALL_TIMEOUT_MS / 1000) return
        // Don't require activeConns >= 2: after Doze, connections drain to 0 naturally
        // but the tunnel session (xray upstream) may be stale for new connections.
        // Idle alone isn't proof of death though — probe the upstream through xray
        // and reconnect only if it actually fails (issue #81: blind reconnects on
        // every wake). onReceive runs on the main thread, so probe off-thread.
        if (probeKind == "passive") return
        if (!wakeProbeRunning.compareAndSet(false, true)) return
        Thread {
            try {
                val session = host.connectedAt // the session probed: a reconnect applies only to it
                val port = XrayVpnService.snapshot.socksPort
                if (session <= 0L || port <= 0) return@Thread
                try {
                    probe(port)
                    host.log("info", "TUN idle ${idleSec}s on wake but tunnel alive, skipping reconnect")
                } catch (e: Exception) {
                    host.log("warning", "TUN stall on wake: no data for ${idleSec}s, probe failed (${e.message}), reconnecting")
                    host.reconnect(session)
                }
            } finally {
                wakeProbeRunning.set(false)
            }
        }.also { it.isDaemon = true; it.start() }
    }

    fun start(isReconnect: Boolean) {
        host.log("info", "startHeartbeat (isReconnect=$isReconnect)")
        thread?.interrupt()
        val policy = HeartbeatPolicy(threshold, switchConfig, isReconnect)
        current = policy
        thread = Thread {
            while (!Thread.currentThread().isInterrupted && host.running) {
                try {
                    Thread.sleep(policy.interval(host.screenOn))
                    if (!host.running) break
                    // Deep Doze: don't wake the radio with probes — counters are untouched,
                    // on leaving idle (maintenance window) the receiver probes.
                    if (host.deviceIdle) continue
                    policy.onIteration(System.currentTimeMillis())
                    val port = XrayVpnService.snapshot.socksPort
                    if (port <= 0) continue
                    // Skip in proxy-only mode: tun2socks is intentionally not started.
                    if (host.tunMode && !apply(policy.onTun(host.core.isTunRunning(), host.core.activeConnections(), { isTunRxFresh() }, System.currentTimeMillis()))) break

                    // Data reached the TUN within the last interval — the tunnel is
                    // demonstrably alive, no need to burn a radio round-trip on an
                    // active probe. Idle tunnels still get the full probe, except in
                    // passive mode: there are no active probes at all, drops are caught by
                    // the TUN stall watchdog and the tun2socks checks above.
                    if (probeKind != "passive" && !isTunRxFresh()) {
                        probe(port)
                    }
                    policy.onSuccess()
                    val successCount = policy.successes
                    if (successCount % 5 == 0) {
                        val activeConns = if (host.tunMode) host.core.activeConnections() else 0L
                        host.log("info", "Heartbeat alive (${successCount} ok, tun=${host.core.isTunRunning()}, conns=$activeConns)")
                    }
                    // Detailed tunnel stats every ~1 minute: log() routes them to
                    // vpn_log.txt + Flutter EventChannel (not only logcat).
                    if (host.tunMode && successCount % 4 == 0) {
                        val stats = host.core.statsLine()
                        if (stats.isNotEmpty()) {
                            val lastRx = host.core.lastRxActivityMs()
                            val lastRxSec = if (lastRx > 0) (System.currentTimeMillis() - lastRx) / 1000 else -1
                            host.log("debug", "tun stats: $stats lastRxSec=$lastRxSec")
                        }
                    }
                    if (host.tunMode) {
                        val lastRx = host.core.lastRxActivityMs()
                        if (lastRx > 0) {
                            val now = System.currentTimeMillis()
                            if (!apply(policy.onTunIdle(now - lastRx, { host.core.activeConnections() }, { isTunRxFresh() }, now))) break
                        }
                    }
                } catch (_: InterruptedException) {
                    break
                } catch (e: Exception) {
                    val action = policy.onFailure(e.message, host.directInternet(), isTunRxFresh(), System.currentTimeMillis())
                    if (action != HeartbeatPolicy.Action.Retry) {
                        if (apply(action)) continue else break
                    }
                    host.log("warning", "Heartbeat failed (${policy.failures()}): ${e.message}")
                    var recovered = false
                    var retries = 0
                    while (retries < HeartbeatPolicy.IMMEDIATE_RETRIES && !Thread.currentThread().isInterrupted) {
                        try {
                            Thread.sleep(HeartbeatPolicy.RETRY_DELAY_MS)
                            probe(XrayVpnService.snapshot.socksPort)
                            recovered = true
                            break
                        } catch (_: InterruptedException) {
                            break
                        } catch (_: Exception) {
                            retries++
                        }
                    }
                    if (!apply(policy.afterRetries(recovered, isTunRxFresh(), System.currentTimeMillis()))) break
                }
            }
        }.also { it.isDaemon = true; it.start() }
    }

    /// Applies a heartbeat decision. Returns false when a reconnect was started and the
    /// heartbeat thread must finish.
    private fun apply(action: HeartbeatPolicy.Action): Boolean {
        when (action) {
            HeartbeatPolicy.Action.None, HeartbeatPolicy.Action.Retry -> {}
            is HeartbeatPolicy.Action.Note -> host.log("debug", action.message)
            is HeartbeatPolicy.Action.Warn -> host.log("warning", action.message)
            is HeartbeatPolicy.Action.SwitchConfig -> {
                host.log("warning", action.reason)
                VpnEventStreamHandler.sendTunnelDeadEvent(action.failures)
            }
            is HeartbeatPolicy.Action.Reconnect -> {
                host.log("warning", "${action.reason} → reconnect")
                host.reconnect(null)
                return false
            }
        }
        return true
    }

    // True when an app got payload from the proxy within the last heartbeat interval —
    // the tunnel is demonstrably passing traffic even if the probe itself fails.
    fun isTunRxFresh(): Boolean {
        if (!host.tunMode) return false
        val lastRx = host.core.lastRxActivityMs()
        return lastRx > 0 && System.currentTimeMillis() - lastRx < HeartbeatPolicy.INTERVAL_MS
    }

    fun stop() {
        if (thread != null) host.log("info", "stopHeartbeat: interrupting heartbeat thread")
        thread?.interrupt()
        thread = null
        current = null
    }

    /// Active probe of the selected type. Throws on failure —
    /// the heartbeat loop counts it as a failure.
    private fun probe(port: Int) {
        when (probeKind) {
            "passive" -> return   // never reached: the loop doesn't call the probe at all
            "xrayDelay" -> {
                val ms = host.core.measureDelay(url)
                if (ms < 0) throw Exception("xray delay probe returned $ms")
                host.log("debug", "Heartbeat OK (xray delay ${ms}ms)")
            }
            else -> checkTunnelConnectivity(port)
        }
    }

    private fun checkTunnelConnectivity(port: Int) {
        val target = SocksHttpProbe.parseUrl(url)
        if (target.https) {
            // The probe itself speaks plain HTTP over SOCKS5 — it can't do TLS.
            // For an https URL it's more honest to measure via the core than to fake success.
            val ms = host.core.measureDelay(url)
            if (ms < 0) throw Exception("xray delay probe returned $ms")
            host.log("debug", "Heartbeat OK (https url, measured in core: ${ms}ms)")
            return
        }
        val creds = XrayVpnService.snapshot
        try {
            SocksHttpProbe.check(port, creds.socksUser, creds.socksPassword, target)
        } catch (e: SocksHttpProbe.Failure) {
            host.log("warning", "Heartbeat check failed at [${e.stage}]: ${e.message}")
            throw e
        }
        current?.resetFailures()
        host.log("debug", "Heartbeat OK")
    }
}
