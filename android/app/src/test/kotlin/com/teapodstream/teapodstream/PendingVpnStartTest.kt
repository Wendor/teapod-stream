package com.teapodstream.teapodstream

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PendingVpnStartTest {
    private val events = mutableListOf<String>()
    private val pending = PendingVpnStart()

    private fun offer(name: String) = pending.offer({ events += "start $name" }, { events += "reject $name $it" })

    @Test
    fun `granted permission starts the waiting connect`() {
        assertTrue(offer("a"))
        pending.complete(granted = true)
        assertEquals(listOf("start a"), events)
    }

    @Test
    fun `denied permission rejects it`() {
        offer("a")
        pending.complete(granted = false)
        assertEquals(listOf("reject a ${PendingVpnStart.DENIED}"), events)
    }

    @Test
    fun `a newer connect replaces the waiting one without a second dialog`() {
        assertTrue(offer("a"))
        assertFalse(offer("b"))
        assertEquals(listOf("reject a ${PendingVpnStart.SUPERSEDED}"), events)
        pending.complete(granted = true)
        assertEquals(listOf("reject a ${PendingVpnStart.SUPERSEDED}", "start b"), events)
    }

    @Test
    fun `a disconnect cancels the waiting connect, the late grant starts nothing`() {
        offer("a")
        pending.cancel(PendingVpnStart.CANCELLED)
        pending.complete(granted = true)
        assertEquals(listOf("reject a ${PendingVpnStart.CANCELLED}"), events)
        assertTrue(offer("b")) // the next connect shows the dialog again
    }

    @Test
    fun `cancel and complete with nothing waiting do nothing`() {
        pending.cancel(PendingVpnStart.CANCELLED)
        pending.complete(granted = true)
        assertTrue(events.isEmpty())
    }
}
