package com.teapodstream.teapodstream

import com.teapodstream.teapodstream.core.CoreKind
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ItestMarkerTest {
    @Test
    fun markerIsPrefixedSingleLineJson() {
        val m = ItestBridge.marker(mapOf("ev" to "state", "value" to "connected", "t" to 5L))
        assertTrue(m.startsWith("TEAPOD_ITEST {"))
        assertFalse(m.contains('\n'))
        val o = JSONObject(m.removePrefix("TEAPOD_ITEST "))
        assertEquals("connected", o.getString("value"))
        assertEquals(5L, o.getLong("t"))
    }

    @Test
    fun markerEscapesNewlinesInValues() {
        val m = ItestBridge.marker(mapOf("error" to "line1\nline2"))
        assertFalse(m.contains('\n'))
        assertEquals("line1\nline2", JSONObject(m.removePrefix("TEAPOD_ITEST ")).getString("error"))
    }

    @Test
    fun connectedMarkerNamesTheRunningCore() {
        val m = SessionSnapshot.connected(1, 1080, "u", "p", 5L, CoreKind.RUST).itestMarker(6L)
        assertEquals("rust", m["core"])
        val off = SessionSnapshot.connected(1, 1080, "u", "p", 5L).copy(state = SessionState.DISCONNECTED)
        assertFalse(off.itestMarker(6L).containsKey("core"))
    }
}
