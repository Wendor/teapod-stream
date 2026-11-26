package com.teapodstream.teapodstream

import com.teapodstream.teapodstream.core.CoreKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SessionSnapshotTest {
    private val connected = SessionSnapshot.connected(7, 2080, "su", "sp", 1_700_000_000_000)

    @Test
    fun wireNamesAreWhatFlutterParses() {
        assertEquals(
            listOf("disconnected", "connecting", "reconnecting", "connected", "disconnecting", "error", "blocked"),
            SessionState.entries.map { it.wire },
        )
    }

    @Test
    fun connectedMapCarriesTheSocksLoginAndNoError() {
        assertEquals(
            mapOf(
                "type" to "state", "value" to "connected", "attempt" to 7L,
                "socksPort" to 2080, "socksUser" to "su", "socksPassword" to "sp", "connectedAtMs" to 1_700_000_000_000,
            ),
            connected.toMap(),
        )
    }

    @Test
    fun otherStatesCarryTheErrorKeyAndNoSocksLogin() {
        val m = SessionSnapshot(SessionState.ERROR, attempt = 3, error = "boom").toMap()
        assertEquals(mapOf("type" to "state", "value" to "error", "attempt" to 3L, "error" to "boom"), m)
        val d = SessionSnapshot().toMap()
        assertTrue(d.containsKey("error"))
        assertNull(d["error"])
        assertFalse(d.containsKey("socksPort"))
    }

    @Test
    fun untaggedSessionHasNoAttemptField() {
        assertFalse(SessionSnapshot(SessionState.RECONNECTING).toMap().containsKey("attempt"))
        assertFalse(SessionSnapshot.connected(0, 1, "", "", 1).toMap().containsKey("attempt"))
    }

    @Test
    fun movingAwayFromConnectedDropsTheLoginAndKeepsTheAttempt() {
        val r = connected.moved(SessionState.RECONNECTING)
        assertEquals(SessionSnapshot(SessionState.RECONNECTING, attempt = 7), r)
        assertEquals(9L, connected.moved(SessionState.DISCONNECTING, attempt = 9).attempt)
    }

    @Test
    fun errorStaysOnlyInStatesThatCarryOne() {
        val failed = SessionSnapshot().moved(SessionState.ERROR, error = "boom")
        assertEquals("boom", failed.error)
        // blocked after an error keeps the reason, a new one replaces it
        assertEquals("boom", failed.moved(SessionState.BLOCKED).error)
        assertEquals("new", failed.moved(SessionState.BLOCKED, error = "new").error)
        // any other state clears it
        assertNull(failed.moved(SessionState.RECONNECTING).error)
        assertNull(failed.moved(SessionState.RECONNECTING).moved(SessionState.ERROR).error)
        assertNull(SessionSnapshot().moved(SessionState.DISCONNECTED, error = "ignored").error)
    }

    @Test
    fun itestMarkerHasTheSocksLoginOnlyWhenConnected() {
        assertEquals(
            mapOf("ev" to "state", "value" to "connected", "t" to 5L,
                "socksPort" to 2080, "socksUser" to "su", "socksPassword" to "sp"),
            connected.itestMarker(5),
        )
        assertEquals(
            mapOf("ev" to "state", "value" to "blocked", "t" to 5L),
            SessionSnapshot(SessionState.BLOCKED, error = "x").itestMarker(5),
        )
    }

    @Test
    fun theServiceStopsOnlyWhenOffWithNothingHeld() {
        assertTrue(serviceIdle(SessionState.DISCONNECTED, tunHeld = false, queueBusy = false))
        assertTrue("a failed start without a sink", serviceIdle(SessionState.ERROR, tunHeld = false, queueBusy = false))
        assertFalse("the kill switch's sink", serviceIdle(SessionState.BLOCKED, tunHeld = true, queueBusy = false))
        assertFalse("a TUN still held", serviceIdle(SessionState.DISCONNECTED, tunHeld = true, queueBusy = false))
        assertFalse("a command waiting or running in the queue", serviceIdle(SessionState.DISCONNECTED, tunHeld = false, queueBusy = true))
        for (state in listOf(SessionState.CONNECTING, SessionState.RECONNECTING, SessionState.CONNECTED, SessionState.DISCONNECTING)) {
            assertFalse(state.wire, serviceIdle(state, tunHeld = false, queueBusy = false))
        }
    }

    @Test
    fun `the session's core stays through its states and its stop`() {
        val rust = SessionSnapshot.connected(7, 2080, "su", "sp", 1, core = CoreKind.RUST)
        assertEquals(CoreKind.RUST, rust.moved(SessionState.RECONNECTING).core)
        assertEquals(CoreKind.RUST, rust.moved(SessionState.DISCONNECTING).moved(SessionState.DISCONNECTED).core)
        assertEquals(CoreKind.BOX, rust.moved(SessionState.CONNECTING, core = CoreKind.BOX).core)
    }
}
