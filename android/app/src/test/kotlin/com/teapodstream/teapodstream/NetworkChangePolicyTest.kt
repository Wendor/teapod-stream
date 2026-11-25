package com.teapodstream.teapodstream

import com.teapodstream.teapodstream.NetworkChangePolicy.Companion.DEBOUNCE_MS
import com.teapodstream.teapodstream.NetworkChangePolicy.Companion.SETTLING_MS
import com.teapodstream.teapodstream.NetworkChangePolicy.Plan
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NetworkChangePolicyTest {
    private val connectedAt = 1_000_000L
    private val late = connectedAt + 60_000

    @Test
    fun switchAfterSettlingChecksTheNetwork() {
        val p = NetworkChangePolicy()
        val plan = p.schedule(switched = true, connectedAt = connectedAt, now = late)
        assertEquals(Plan(check = true, delayMs = DEBOUNCE_MS, settling = false), plan)
        assertTrue(p.onFire(plan, { "lte" }, "wifi"))
        assertFalse(p.onFire(plan, { "wifi" }, "wifi"))
        assertFalse(p.onFire(plan, { null }, "wifi"))
    }

    @Test
    fun validationLossAfterSettlingReconnects() {
        val p = NetworkChangePolicy()
        val plan = p.schedule(switched = false, connectedAt = connectedAt, now = late)
        assertFalse(plan.check)
        assertTrue(p.onFire(plan, { error("not asked") }, "wifi"))
    }

    @Test
    fun validationLossForcesReconnectOfALaterSwitchPlan() {
        val p = NetworkChangePolicy()
        p.schedule(switched = false, connectedAt = connectedAt, now = late)
        val plan = p.schedule(switched = true, connectedAt = connectedAt, now = late + 100)
        assertFalse(plan.check)
        assertTrue(p.onFire(plan, { "wifi" }, "wifi"))
        // Consumed: the next switch checks again.
        val next = p.schedule(switched = true, connectedAt = connectedAt, now = late + 200)
        assertTrue(next.check)
    }

    @Test
    fun eventsRightAfterConnectWaitForTheWindowAndCheck() {
        val p = NetworkChangePolicy()
        val plan = p.schedule(switched = false, connectedAt = connectedAt, now = connectedAt + 1_000)
        assertEquals(Plan(check = true, delayMs = SETTLING_MS - 1_000 + DEBOUNCE_MS, settling = true), plan)
        assertFalse(p.onFire(plan, { "wifi" }, "wifi"))
    }

    @Test
    fun unknownConnectTimeIsNotSettling() {
        val plan = NetworkChangePolicy().schedule(switched = true, connectedAt = 0, now = late)
        assertFalse(plan.settling)
        assertEquals(DEBOUNCE_MS, plan.delayMs)
    }

    @Test
    fun resetDropsPendingForce() {
        val p = NetworkChangePolicy()
        p.schedule(switched = false, connectedAt = connectedAt, now = late)
        p.reset()
        assertTrue(p.schedule(switched = true, connectedAt = connectedAt, now = late).check)
    }
}
