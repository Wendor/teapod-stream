package com.teapodstream.teapodstream

import org.junit.Assert.assertEquals
import org.junit.Test

class SessionStatsTest {
    @Test
    fun speedsFromTheBaselineOfTheSession() {
        val g = SessionStats.reset(0)
        SessionStats.sample(g, 1_000, 2_000, 1_000, chart = false)
        SessionStats.sample(g, 1_500, 4_000, 2_000, chart = false)
        assertEquals(mapOf("upload" to 1_500L, "download" to 4_000L, "uploadSpeed" to 500L, "downloadSpeed" to 2_000L),
            SessionStats.get())
    }

    @Test
    fun aStoppedSessionsWorkerDoesNotTouchTheNextSession() {
        val old = SessionStats.reset(0)
        val next = SessionStats.reset(10_000)
        SessionStats.sample(old, 900_000, 900_000, 10_500, chart = true)
        SessionStats.sample(next, 1_000, 1_000, 11_000, chart = true)
        assertEquals(mapOf("upload" to 1_000L, "download" to 1_000L, "uploadSpeed" to 1_000L, "downloadSpeed" to 1_000L),
            SessionStats.get())
        @Suppress("UNCHECKED_CAST")
        assertEquals(1, (SessionStats.history(-1, 0)["history"] as List<Any>).size)
    }
}
