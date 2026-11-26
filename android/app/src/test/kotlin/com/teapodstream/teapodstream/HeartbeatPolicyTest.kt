package com.teapodstream.teapodstream

import com.teapodstream.teapodstream.HeartbeatPolicy.Action
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HeartbeatPolicyTest {
    private val t0 = 1_000_000L

    private fun policy(threshold: Int = 3, switchConfig: Boolean = false, isReconnect: Boolean = false) =
        HeartbeatPolicy(threshold, switchConfig, isReconnect).also { it.onIteration(t0) }

    private fun HeartbeatPolicy.fail(now: Long = t0, internet: Boolean = true, rxFresh: Boolean = false) =
        onFailure("boom", internet, rxFresh, now)

    @Test
    fun failuresRetryUntilThresholdThenReconnect() {
        val p = policy()
        assertEquals(Action.Retry, p.fail())
        assertEquals(Action.None, p.afterRetries(false, false, t0))
        assertEquals(Action.Retry, p.fail())
        val last = p.fail()
        assertTrue(last is Action.Reconnect)
        assertEquals("Heartbeat failed (failures: 3)", (last as Action.Reconnect).reason)
    }

    @Test
    fun recoveredRetryResetsFailures() {
        val p = policy()
        p.fail(); p.fail()
        assertEquals(Action.None, p.afterRetries(true, false, t0))
        assertEquals(0, p.failures())
        assertEquals(Action.Retry, p.fail())
    }

    @Test
    fun successResetsFailures() {
        val p = policy()
        p.fail(); p.fail()
        p.onSuccess()
        assertEquals(Action.Retry, p.fail())
        assertEquals(1, p.failures())
    }

    @Test
    fun freshTunTrafficKeepsSession() {
        val p = policy(threshold = 1)
        assertTrue(p.fail(rxFresh = true) is Action.Warn)
        assertEquals(0, p.failures())
    }

    @Test
    fun noInternetIsNotCountedAndLongAbsenceReconnectsAtOnce() {
        val p = policy()
        repeat(3) { assertTrue(p.fail(internet = false) is Action.Note) }
        assertEquals(0, p.failures())
        val r = p.fail()
        assertTrue(r is Action.Reconnect)
        assertEquals("Tunnel stale after 45s network absence", (r as Action.Reconnect).reason)
    }

    @Test
    fun shortAbsenceCountsNormally() {
        val p = policy()
        repeat(2) { p.fail(internet = false) }
        assertEquals(Action.Retry, p.fail())
    }

    @Test
    fun warmupIgnoresFailuresUntilDeadline() {
        val p = policy(threshold = 1, isReconnect = true)
        assertEquals(HeartbeatPolicy.INTERVAL_MS, p.interval(screenOn = false))
        assertTrue(p.fail(now = t0 + HeartbeatPolicy.WARMUP_TIMEOUT_MS - 1) is Action.Note)
        val r = p.fail(now = t0 + HeartbeatPolicy.WARMUP_TIMEOUT_MS)
        assertTrue(r is Action.Reconnect)
    }

    @Test
    fun warmupDeadlineStartsAtFirstIteration() {
        val p = HeartbeatPolicy(1, false, isReconnect = true)
        p.onIteration(t0)
        p.onIteration(t0 + 20_000) // later iterations don't move it
        assertTrue(p.fail(now = t0 + HeartbeatPolicy.WARMUP_TIMEOUT_MS) is Action.Reconnect)
    }

    @Test
    fun warmupEndsOnFirstSuccess() {
        val p = policy(threshold = 1, isReconnect = true)
        p.onSuccess()
        assertEquals(HeartbeatPolicy.INTERVAL_SCREEN_OFF_MS, p.interval(screenOn = false))
        assertTrue(p.fail() is Action.Reconnect)
    }

    @Test
    fun screenOnKeepsFastInterval() {
        assertEquals(HeartbeatPolicy.INTERVAL_MS, policy().interval(screenOn = true))
        assertEquals(HeartbeatPolicy.INTERVAL_SCREEN_OFF_MS, policy().interval(screenOn = false))
    }

    @Test
    fun switchConfigAsksFlutterThenFallsBackAfterCooldown() {
        val p = policy(threshold = 1, switchConfig = true)
        val first = p.fail(now = t0)
        assertEquals(Action.SwitchConfig(1, "Heartbeat failed (failures: 1) → picking another config"), first)
        assertEquals(0, p.failures())
        // Exhausted again within the cooldown: Flutter still has time, nothing is done.
        assertTrue(p.fail(now = t0 + 10_000) is Action.Note)
        // Flutter didn't switch within the cooldown — a plain reconnect...
        assertTrue(p.fail(now = t0 + HeartbeatPolicy.SWITCH_COOLDOWN_MS) is Action.Reconnect)
        // ...and the next exhaustion asks Flutter again.
        assertTrue(p.fail(now = t0 + HeartbeatPolicy.SWITCH_COOLDOWN_MS + 10_000) is Action.SwitchConfig)
    }

    @Test
    fun deadOrLeakingTunReconnects() {
        val p = policy()
        val fresh = { true }
        assertTrue(p.onTun(running = false, activeConns = 0, rxFresh = fresh, now = t0) is Action.Reconnect)
        assertTrue(p.onTun(running = true, activeConns = HeartbeatPolicy.TUN_CONN_LEAK_THRESHOLD + 1, rxFresh = fresh, now = t0) is Action.Reconnect)
        assertEquals(Action.None, p.onTun(running = true, activeConns = HeartbeatPolicy.TUN_CONN_LEAK_THRESHOLD, rxFresh = fresh, now = t0))
    }

    @Test
    fun pileUpWithoutAnswersIsExhaustionSoSwitchConfigApplies() {
        val conns = HeartbeatPolicy.TUN_CONN_LEAK_THRESHOLD + 1
        val switching = policy(switchConfig = true)
        assertTrue(switching.onTun(running = true, activeConns = conns, rxFresh = { false }, now = t0) is Action.SwitchConfig)
        // The pile-up check runs every interval: within the cooldown it waits for the switch, no reconnect.
        val next = switching.onTun(running = true, activeConns = conns, rxFresh = { false }, now = t0 + HeartbeatPolicy.INTERVAL_MS)
        assertTrue(next is Action.Note)
        // The reconnect mode reconnects, as before.
        assertTrue(policy().onTun(running = true, activeConns = conns, rxFresh = { false }, now = t0) is Action.Reconnect)
    }

    @Test
    fun tunStallIsExhaustionAndIdleWarnsOncePerMinute() {
        val p = policy()
        val stale = { false }
        assertEquals(Action.None, p.onTunIdle(59_000, { error("not counted") }, stale, t0))
        assertTrue(p.onTunIdle(60_000, { 5 }, stale, t0) is Action.Warn)
        assertEquals(Action.None, p.onTunIdle(70_000, { 5 }, stale, t0 + 10_000))
        assertTrue(p.onTunIdle(90_000, { 5 }, stale, t0 + 60_000) is Action.Warn)
        assertEquals(Action.None, p.onTunIdle(200_000, { 1 }, stale, t0))
        val r = p.onTunIdle(HeartbeatPolicy.TUN_STALL_TIMEOUT_MS, { 2 }, stale, t0)
        assertEquals(Action.Reconnect("TUN stall: no data for 120s (conns=2) (failures: 3)"), r)
    }

    @Test
    fun idleCheckCountsConnectionsOnce() {
        var calls = 0L
        val r = policy().onTunIdle(HeartbeatPolicy.TUN_STALL_TIMEOUT_MS, { calls++; 5L - calls * 3 }, { false }, t0)
        assertEquals(1L, calls)
        assertEquals(Action.Reconnect("TUN stall: no data for 120s (conns=2) (failures: 3)"), r)
    }

    @Test
    fun stallWithDataArrivedMeanwhileKeepsSession() {
        val p = policy(switchConfig = true)
        assertTrue(p.onTunIdle(HeartbeatPolicy.TUN_STALL_TIMEOUT_MS, { 5 }, { true }, t0) is Action.Warn)
    }
}
