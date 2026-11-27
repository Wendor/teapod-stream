package com.teapodstream.teapodstream

import com.teapodstream.teapodstream.StartFailurePolicy.Stop
import com.teapodstream.teapodstream.StartFailurePolicy.Wanted
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StartFailurePolicyTest {
    private fun fail(
        killSwitch: Boolean = false,
        reconnect: Boolean = false,
        proxyOnly: Boolean = false,
        hadPreviousTun: Boolean = false,
        newTunHeld: Boolean = false,
        previousTunOpen: Boolean = hadPreviousTun,
        wanted: Wanted = Wanted.SAME,
        attempt: Int = 1,
    ) = StartFailurePolicy.startFailure(
        killSwitch, reconnect, proxyOnly, hadPreviousTun, newTunHeld, previousTunOpen, wanted,
        maxAttempts = 3, nextAttempt = { attempt },
    )

    @Test
    fun manualConnectWithoutKillSwitchStopsWithAnError() {
        val f = fail(hadPreviousTun = true)
        assertFalse(f.restorePrevious)
        assertFalse(f.retry)
        assertTrue(f.reportError)
        assertEquals(Stop(keepTun = false, state = SessionState.ERROR), f.outcome)
    }

    @Test
    fun manualConnectWithKillSwitchKeepsTheSinkOnlyIfTrafficWasBlocked() {
        // A broken config must not lock the network.
        assertEquals(Stop(false, SessionState.ERROR), fail(killSwitch = true).outcome)
        val blocked = fail(killSwitch = true, hadPreviousTun = true)
        assertTrue(blocked.restorePrevious)
        assertEquals(Stop(true, SessionState.BLOCKED), blocked.outcome)
        assertTrue(blocked.reportError)
    }

    @Test
    fun reconnectRetriesWithTheSinkUntilAttemptsRunOut() {
        val f = fail(reconnect = true, hadPreviousTun = true, attempt = 3)
        assertTrue(f.retry)
        assertTrue(f.restorePrevious)
        assertFalse(f.reportError)
        assertEquals(Stop(true, SessionState.RECONNECTING), f.outcome)

        val last = fail(reconnect = true, hadPreviousTun = true, attempt = 4)
        assertFalse(last.retry)
        assertEquals(Stop(false, SessionState.ERROR), last.outcome)
        val blocked = fail(killSwitch = true, reconnect = true, hadPreviousTun = true, attempt = 4)
        assertEquals(Stop(true, SessionState.BLOCKED), blocked.outcome)
    }

    @Test
    fun attemptsAreCountedOnlyForARetry() {
        var counted = 0
        val count = { ++counted }
        fun run(reconnect: Boolean, wanted: Wanted) =
            StartFailurePolicy.startFailure(false, reconnect, false, false, false, false, wanted, 3, count)
        for (wanted in Wanted.entries) run(reconnect = false, wanted)
        run(reconnect = true, Wanted.OFF)
        run(reconnect = true, Wanted.OTHER_START)
        assertEquals(0, counted)
        run(reconnect = true, Wanted.SAME)
        assertEquals(1, counted)
    }

    @Test
    fun replacedByAnotherStartKeepsTheSinkForIt() {
        val f = fail(hadPreviousTun = true, wanted = Wanted.OTHER_START)
        assertTrue(f.adoptWanted)
        assertTrue(f.restorePrevious)
        assertFalse(f.reportError)
        assertEquals(Stop(true, SessionState.RECONNECTING), f.outcome)
    }

    @Test
    fun replacedByAnOffStopsAsTheUsersOff() {
        val f = fail(killSwitch = true, reconnect = true, hadPreviousTun = true, wanted = Wanted.OFF)
        assertTrue(f.adoptWanted)
        assertFalse(f.retry)
        assertFalse(f.reportError)
        assertEquals(Stop(false, SessionState.DISCONNECTED), f.outcome)
    }

    @Test
    fun proxyOnlyNeverKeepsATun() {
        val f = fail(killSwitch = true, reconnect = true, proxyOnly = true, hadPreviousTun = true, attempt = 4)
        assertFalse(f.restorePrevious)
        assertEquals(Stop(false, SessionState.ERROR), f.outcome)
    }

    @Test
    fun anEstablishedTunReplacesThePreviousOne() {
        val f = fail(killSwitch = true, hadPreviousTun = true, newTunHeld = true, previousTunOpen = false)
        assertFalse(f.restorePrevious)
        assertEquals(Stop(true, SessionState.BLOCKED), f.outcome)
    }

    /** Every combination agrees with the decisions as they were spread over `startVpn` and `stopVpn`. */
    @Test
    fun matchesThePreviousInlineDecisions() {
        val bools = listOf(false, true)
        for (ks in bools) for (rc in bools) for (po in bools) for (had in bools) for (held in bools)
            for (open in bools) for (wanted in Wanted.entries) for (attempt in 1..5) {
                val f = fail(ks, rc, po, had, held, open, wanted, attempt)
                val e = Previous.failure(ks, rc, po, had, held, open, wanted, attempt)
                val where = "ks=$ks rc=$rc po=$po had=$had held=$held open=$open $wanted attempt=$attempt"
                assertEquals(where, e, Expected(f.restorePrevious, f.adoptWanted, f.retry, f.reportError, f.outcome))
            }
    }

    private data class Expected(
        val restorePrevious: Boolean,
        val adoptWanted: Boolean,
        val retry: Boolean,
        val reportError: Boolean,
        val outcome: Stop,
    )

    /** The conditions copied from `startVpn`'s catch block and `stopVpn` before they moved to the policy. */
    private object Previous {
        fun failure(
            killSwitch: Boolean, isReconnect: Boolean, proxyOnly: Boolean, hadPreviousTun: Boolean,
            newTunHeld: Boolean, previousTunOpen: Boolean, wanted: Wanted, attempt: Int,
        ): Expected {
            val keepSinkOnFailure = killSwitch && (isReconnect || hadPreviousTun)
            val replaced = wanted != Wanted.SAME
            val next = wanted == Wanted.OTHER_START
            val restore = !newTunHeld && previousTunOpen && (killSwitch || isReconnect || next) && !proxyOnly
            val tunHeld = newTunHeld || restore
            if (replaced) {
                val stop = stop(killSwitch, proxyOnly, explicit = !next, reconnecting = next, tunHeld,
                    SessionState.DISCONNECTED)
                return Expected(restore, true, false, false, stop)
            }
            val willRetry = isReconnect && attempt <= 3
            return Expected(restore, false, willRetry, !willRetry,
                stop(killSwitch, proxyOnly, explicit = !willRetry && !keepSinkOnFailure, reconnecting = willRetry,
                    tunHeld, SessionState.ERROR))
        }

        fun stop(
            killSwitchEnabled: Boolean, proxyOnlyMode: Boolean, explicit: Boolean, reconnecting: Boolean,
            tunHeld: Boolean, resultState: SessionState,
        ): Stop {
            val keptTunAsSink = (killSwitchEnabled || reconnecting) && !explicit && !proxyOnlyMode && tunHeld
            val finalState = when {
                reconnecting -> SessionState.RECONNECTING
                keptTunAsSink -> SessionState.BLOCKED
                else -> resultState
            }
            return Stop(keptTunAsSink, finalState)
        }
    }
}
