package com.teapodstream.teapodstream

/// Decisions of the heartbeat loop. The loop thread probes the tunnel and applies the returned
/// [Action]; all counters, the warmup and the switchConfig cooldown live here. Time comes in as
/// an argument (`SystemClock.elapsedRealtime`: a wall-clock step can't stretch or cut the warm-up and the switch
/// cooldown), so the policy is tested on the JVM. One instance per heartbeat thread; methods
/// are synchronized because a wake probe on another thread may report a success.
class HeartbeatPolicy(
    private val threshold: Int,
    private val switchConfig: Boolean,
    isReconnect: Boolean,
) {
    sealed interface Action {
        /// Carry on to the next interval.
        data object None : Action
        /// Carry on; log at debug level.
        data class Note(val message: String) : Action
        /// Carry on; log a warning.
        data class Warn(val message: String) : Action
        /// Probe again right away (up to [IMMEDIATE_RETRIES] times, [RETRY_DELAY_MS] apart),
        /// then report with [afterRetries].
        data object Retry : Action
        /// Reconnect the session; the loop ends.
        data class Reconnect(val reason: String) : Action
        /// Ask Flutter to pick another config (tunnel_dead event); the loop carries on.
        data class SwitchConfig(val failures: Int, val reason: String) : Action
    }

    // After a reconnect, failures don't count until the first probe succeeds (warmup), up to
    // WARMUP_TIMEOUT_MS from the first probe — not from the thread start, which may be long
    // before the core is ready after a slow reconnect.
    private var warmupDone = !isReconnect
    private var warmupDeadline = 0L
    private var failures = 0
    // Consecutive failures without direct internet. When internet returns after a long absence
    // the tunnel session is stale regardless of protocol: the first failure reconnects.
    private var noInternetStreak = 0
    private var lastSwitchAt = 0L
    private var lastStallWarnAt = 0L

    var successes = 0
        private set

    /// The sleep before the next probe. Warmup keeps the fast cadence: after a reconnect the
    /// first success must be seen promptly whatever the screen state.
    @Synchronized fun interval(screenOn: Boolean): Long =
        if (screenOn || !warmupDone) INTERVAL_MS else INTERVAL_SCREEN_OFF_MS

    /// A probe iteration starts (not skipped by Doze).
    @Synchronized fun onIteration(now: Long) {
        if (!warmupDone && warmupDeadline == 0L) warmupDeadline = now + WARMUP_TIMEOUT_MS
    }

    /// TUN mode only: tun2socks state before probing. The SOCKS probe bypasses the TUN, so it
    /// passes even when tun2socks crashed or leaks connections (stale TIME_WAIT / CLOSE_WAIT
    /// entries in gVisor); a reconnect resets both. Too many connections while apps get no
    /// payload ([rxFresh] false) is a dead upstream piling up attempts, not a leak: it is
    /// exhaustion, so `switchConfig` applies (a plain reconnect every interval would restart
    /// the warm-up and keep the failures from ever counting).
    @Synchronized fun onTun(running: Boolean, activeConns: Long, rxFresh: () -> Boolean, now: Long): Action = when {
        !running -> Action.Reconnect("tun2socks not running")
        activeConns > TUN_CONN_LEAK_THRESHOLD && !rxFresh() ->
            exhausted(threshold, "No answers with activeConns=$activeConns", rxFresh = false, now = now)
        activeConns > TUN_CONN_LEAK_THRESHOLD -> Action.Reconnect("gVisor connection leak detected (activeConns=$activeConns)")
        else -> Action.None
    }

    /// The probe passed (or was skipped because the TUN received data recently).
    @Synchronized fun onSuccess() {
        warmupDone = true
        failures = 0
        noInternetStreak = 0
        successes++
    }

    /// A probe on another thread passed: the tunnel is alive, the failure count starts over.
    @Synchronized fun resetFailures() {
        failures = 0
    }

    /// TUN mode, after a success: the SOCKS probe passes even when proxy goroutines are alive
    /// but no data reaches the TUN (half-open connections held by keepalives).
    /// [idleMs] — time since tun2socks last wrote to the TUN; [activeConns] is counted once, only
    /// when the idle time calls for it; [rxFresh] is re-checked before acting on a stall, since data
    /// may reach the TUN after [idleMs] was read.
    @Synchronized fun onTunIdle(idleMs: Long, activeConns: () -> Long, rxFresh: () -> Boolean, now: Long): Action {
        val idleSec = idleMs / 1000
        if (idleSec < 60) return Action.None
        val conns = activeConns()
        return when {
            conns < 2 -> Action.None
            idleMs >= TUN_STALL_TIMEOUT_MS ->
                exhausted(threshold, "TUN stall: no data for ${idleSec}s (conns=$conns)", rxFresh(), now)
            now - lastStallWarnAt >= 60_000 -> {
                lastStallWarnAt = now
                Action.Warn("TUN rx idle for ${idleSec}s (conns=$conns)")
            }
            else -> Action.None
        }
    }

    /// The probe failed. [directInternet] — the physical network reaches the internet;
    /// [rxFresh] — the TUN received data within the last interval.
    @Synchronized fun onFailure(error: String?, directInternet: Boolean, rxFresh: Boolean, now: Long): Action {
        // No physical network: not the core's fault; a network change reconnects once the
        // new network is ready.
        if (!directInternet) {
            noInternetStreak++
            return Action.Note("Heartbeat skipped: no direct internet (streak=$noInternetStreak)")
        }
        if (noInternetStreak >= 3) {
            val absenceSec = noInternetStreak * (INTERVAL_MS / 1000)
            noInternetStreak = 0
            return Action.Reconnect("Tunnel stale after ${absenceSec}s network absence")
        }
        noInternetStreak = 0
        if (!warmupDone) {
            // A config switch asked for meanwhile (the pile-up check) has its cooldown: the warm-up limit doesn't cut it.
            if (warmupDeadline == 0L || now < warmupDeadline || switchPending(now)) {
                return Action.Note("Heartbeat warmup probe failed: $error")
            }
            return Action.Reconnect("Heartbeat warmup timed out (${WARMUP_TIMEOUT_MS / 1000} s)")
        }
        failures++
        if (failures >= threshold) return exhausted(failures, "Heartbeat failed", rxFresh, now)
        return Action.Retry
    }

    /// After [Action.Retry]: [recovered] — one of the immediate retries passed.
    @Synchronized fun afterRetries(recovered: Boolean, rxFresh: Boolean, now: Long): Action {
        if (recovered) {
            warmupDone = true
            failures = 0
        }
        return if (failures >= threshold) exhausted(failures, "Heartbeat retries exhausted", rxFresh, now)
        else Action.None
    }

    /// How many failures were counted so far (for the log).
    @Synchronized fun failures(): Int = failures

    private fun exhausted(count: Int, reason: String, rxFresh: Boolean, now: Long): Action {
        // The probe rides through the routing balancer and can land on a dead detour while
        // real traffic flows: if the TUN saw data within the last interval, keep the session.
        if (rxFresh) {
            failures = 0
            lastSwitchAt = 0L // data flows: an earlier switch request is settled
            return Action.Warn("Heartbeat failing but TUN traffic is alive, skipping reconnect")
        }
        if (switchConfig) {
            if (lastSwitchAt == 0L) {
                lastSwitchAt = now
                failures = 0
                return Action.SwitchConfig(count, "$reason (failures: $count) → picking another config")
            }
            // Flutter has the cooldown to switch: a check exhausted again meanwhile (the pile-up one runs every
            // interval) waits instead of reconnecting under it.
            if (switchPending(now)) {
                return Action.Note("$reason (failures: $count), waiting for the config switch")
            }
            // No switch within the cooldown (app killed / no live candidate): a plain reconnect of the current
            // server; the next exhaustion asks Flutter again.
            lastSwitchAt = 0L
            failures = 0
            return Action.Reconnect("$reason (failures: $count), no switch within the switchConfig cooldown")
        }
        return Action.Reconnect("$reason (failures: $count)")
    }

    private fun switchPending(now: Long) = lastSwitchAt != 0L && now - lastSwitchAt < SWITCH_COOLDOWN_MS

    companion object {
        const val INTERVAL_MS = 15_000L
        // Screen off: nobody is watching, the radio should be allowed to idle between
        // probes. Dead-tunnel detection grows to ~3 min while asleep — acceptable,
        // checkTunStallOnWake() probes immediately on SCREEN_ON.
        const val INTERVAL_SCREEN_OFF_MS = 60_000L
        // After a reconnect the core establishes its outbound connection lazily: failures
        // don't count until the first probe succeeds, but no longer than this.
        const val WARMUP_TIMEOUT_MS = 30_000L
        // How long to wait for Flutter's reaction to tunnel_dead before reconnecting ourselves.
        const val SWITCH_COOLDOWN_MS = 45_000L
        // More active proxy goroutines than this — the gVisor TCP state machine is leaking.
        const val TUN_CONN_LEAK_THRESHOLD = 200L
        // No data reached the TUN for this long while ≥2 connections are active — tun2socks
        // goroutines are stuck (held alive by keepalives); the SOCKS probe won't catch it.
        const val TUN_STALL_TIMEOUT_MS = 120_000L
        const val IMMEDIATE_RETRIES = 2
        const val RETRY_DELAY_MS = 3_000L
    }
}
