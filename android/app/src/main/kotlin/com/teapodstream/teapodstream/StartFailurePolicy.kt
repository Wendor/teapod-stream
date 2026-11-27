package com.teapodstream.teapodstream

/**
 * What a session stop and a failed start leave: the TUN kept as the kill switch's sink or closed, a retry, the state
 * reported. Pure, so every combination is tested on the JVM; [XrayVpnService] applies the result.
 */
object StartFailurePolicy {
    /** What is wanted when the start fails. */
    enum class Wanted {
        /** Still this start. */
        SAME,

        /** Another start replaced it. */
        OTHER_START,

        /** An off replaced it. */
        OFF,
    }

    /** The TUN stays open as a sink ([keepTun]) and the stop reports [state]. */
    data class Stop(val keepTun: Boolean, val state: SessionState)

    /**
     * A stop of the session. [mayKeepSink] — the stop allows a sink at all (false: a user's off, a broken manual
     * connect); [reconnecting] — another start follows; [tunHeld] — a TUN is open as the stop begins; [resultState]
     * — reported when nothing else applies.
     */
    fun stop(
        killSwitch: Boolean,
        proxyOnly: Boolean,
        mayKeepSink: Boolean,
        reconnecting: Boolean,
        tunHeld: Boolean,
        resultState: SessionState,
    ): Stop {
        // A reconnect keeps the TUN for the next start to reuse (no establish(), no system "VPN active" notification)
        // and as a sink meanwhile; the kill switch keeps it after any stop that allows it.
        val keepTun = (killSwitch || reconnecting) && mayKeepSink && !proxyOnly && tunHeld
        val state = when {
            reconnecting -> SessionState.RECONNECTING
            keepTun -> SessionState.BLOCKED
            else -> resultState
        }
        return Stop(keepTun, state)
    }

    /**
     * The decision on a failed start. [restorePrevious] — the previous TUN becomes the session's again (else it is
     * closed); [adoptWanted] — the stop's states belong to what is wanted now (the start was replaced); [retry] — the
     * same start runs again after a delay; [mayKeepSink], [reconnecting], [resultState], [reportError] — the stop's
     * arguments; [outcome] — what that stop leaves.
     */
    data class Failure(
        val restorePrevious: Boolean,
        val adoptWanted: Boolean,
        val retry: Boolean,
        val mayKeepSink: Boolean,
        val reconnecting: Boolean,
        val resultState: SessionState,
        val reportError: Boolean,
        val outcome: Stop,
    )

    /**
     * A start failed. [reconnect] — a native restart of a session, not the user's connect; [hadPreviousTun] — a TUN
     * was open when the start began (a sink left by a drop or a reconnect); [newTunHeld] — the session holds a TUN at
     * the failure (established, or the previous one reused); [previousTunOpen] — the previous TUN is still open and
     * not reused. [nextAttempt] counts a retry and returns its number; it is called only when a retry is possible.
     */
    fun startFailure(
        killSwitch: Boolean,
        reconnect: Boolean,
        proxyOnly: Boolean,
        hadPreviousTun: Boolean,
        newTunHeld: Boolean,
        previousTunOpen: Boolean,
        wanted: Wanted,
        maxAttempts: Int,
        nextAttempt: () -> Int,
    ): Failure {
        val next = wanted == Wanted.OTHER_START
        // Without a new TUN the previous one stays: as the kill switch's sink, for the next reconnect to reuse, or for
        // the start that replaced this one.
        val restorePrevious = !newTunHeld && previousTunOpen && (killSwitch || reconnect || next) && !proxyOnly
        val tunHeld = newTunHeld || restorePrevious
        if (wanted != Wanted.SAME) {
            // Replaced: no error for it. A new start keeps the sink for itself; an off stops as a user's off does.
            val outcome = stop(killSwitch, proxyOnly, mayKeepSink = next, reconnecting = next, tunHeld = tunHeld,
                resultState = SessionState.DISCONNECTED)
            return Failure(restorePrevious, adoptWanted = true, retry = false, mayKeepSink = next, reconnecting = next,
                resultState = SessionState.DISCONNECTED, reportError = false, outcome = outcome)
        }
        val retry = reconnect && nextAttempt() <= maxAttempts
        // The kill switch keeps the sink after a final failure, so traffic stays blocked instead of leaking past the
        // VPN — on a manual connect only if traffic was already blocked: a broken config must not lock the network.
        val keepSinkOnFailure = killSwitch && (reconnect || hadPreviousTun)
        val mayKeepSink = retry || keepSinkOnFailure
        val outcome = stop(killSwitch, proxyOnly, mayKeepSink, reconnecting = retry, tunHeld = tunHeld,
            resultState = SessionState.ERROR)
        return Failure(restorePrevious, adoptWanted = false, retry = retry, mayKeepSink = mayKeepSink,
            reconnecting = retry, resultState = SessionState.ERROR, reportError = !retry, outcome = outcome)
    }
}
