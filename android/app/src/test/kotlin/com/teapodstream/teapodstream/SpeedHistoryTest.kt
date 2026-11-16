package com.teapodstream.teapodstream

import org.junit.Assert.assertEquals
import org.junit.Test

class SpeedHistoryTest {
    @Suppress("UNCHECKED_CAST")
    private fun Map<String, Any>.downloads() =
        (this["history"] as List<Map<String, Long>>).map { it.getValue("downloadSpeed") }

    @Test
    fun firstRequestGetsWholeBuffer() {
        val h = SpeedHistory(3).apply { reset(); add(0, 1); add(0, 2) }
        val r = h.since(-1, 0)
        assertEquals(true, r["full"])
        assertEquals(listOf(1L, 2L), r.downloads())
        assertEquals(2L, r["seq"])
    }

    @Test
    fun deltaReturnsOnlyNewPointsAfterSince() {
        val h = SpeedHistory(5).apply { reset(); add(0, 1); add(0, 2) }
        val epoch = h.since(-1, 0)["epoch"] as Int
        h.add(0, 3); h.add(0, 4)
        val r = h.since(epoch, 2)
        assertEquals(false, r["full"])
        assertEquals(2L, r["from"])
        assertEquals(listOf(3L, 4L), r.downloads())
        assertEquals(emptyList<Long>(), h.since(epoch, 4).downloads())
    }

    /** Lagged behind by more than the buffer (background, hidden tab) — the whole buffer, no gaps. */
    @Test
    fun gapLargerThanBufferReturnsFullBuffer() {
        val h = SpeedHistory(3).apply { reset(); add(0, 1) }
        val epoch = h.since(-1, 0)["epoch"] as Int
        (2L..6L).forEach { h.add(0, it) }
        val r = h.since(epoch, 1)
        assertEquals(true, r["full"])
        assertEquals(listOf(4L, 5L, 6L), r.downloads())
        assertEquals(3L, r["from"])
    }

    /** A new session is a new epoch: an old client gets the whole (new) buffer. */
    @Test
    fun resetStartsNewEpoch() {
        val h = SpeedHistory(3).apply { reset(); add(0, 1) }
        val epoch = h.since(-1, 0)["epoch"] as Int
        h.reset(); h.add(0, 9)
        val r = h.since(epoch, 1)
        assertEquals(true, r["full"])
        assertEquals(listOf(9L), r.downloads())
    }
}
