package com.teapodstream.teapodstream

/// Decisions on physical network events. The service schedules the returned [Plan] on its
/// handler and, when it fires, asks [onFire] whether to reconnect. Time comes in as an argument,
/// so the policy is tested on the JVM. Used from the network callback and handler threads.
class NetworkChangePolicy {
    /// [check] — when the plan fires, compare the physical network with the one the session
    /// connected on (back on it — the core's sockets are alive, no reconnect needed);
    /// otherwise reconnect. [settling] — inside the window right after connecting.
    data class Plan(val check: Boolean, val delayMs: Long, val settling: Boolean)

    // A loss of VALIDATED outside the settling window: a reconnect is mandatory, even if a
    // network change follows and the network turns out to be the same.
    @Volatile private var force = false

    /// A network event while connected. [switched] — the physical network changed (otherwise
    /// the current one lost VALIDATED); [connectedAt] — when the session connected (0 — unknown).
    fun schedule(switched: Boolean, connectedAt: Long, now: Long): Plan {
        // On mobile data Android fires onAvailable/onCapabilitiesChanged right after the VPN
        // connects. In the window we don't reconnect right away: when it ends the networks are
        // compared, so a real change isn't lost.
        val sinceConnect = now - connectedAt
        val settling = connectedAt > 0 && sinceConnect < SETTLING_MS
        if (!switched && !settling) force = true
        val delay = if (settling) SETTLING_MS - sinceConnect + DEBOUNCE_MS else DEBOUNCE_MS
        return Plan(check = (switched || settling) && !force, delayMs = delay, settling = settling)
    }

    /// The scheduled [plan] fires: true — reconnect. [current] — the physical network now
    /// (null — none yet), [connected] — the one the session connected on.
    fun <N : Any> onFire(plan: Plan, current: () -> N?, connected: N?): Boolean {
        val forced = force
        force = false
        if (!plan.check || forced) return true
        val now = current() ?: return false
        return now != connected
    }

    /// The session stopped: a pending forced reconnect no longer applies.
    fun reset() {
        force = false
    }

    companion object {
        const val SETTLING_MS = 5_000L
        const val DEBOUNCE_MS = 2_000L
    }
}
