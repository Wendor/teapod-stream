package com.teapodstream.teapodstream

import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SessionCommandsTest {
    private val commands = SessionCommands()
    private val ran = Collections.synchronizedList(mutableListOf<String>())

    /** Starts [name] on its own thread, as the service does; it waits for the lock like the real commands. */
    private fun command(name: String, id: Long, done: CountDownLatch) = Thread {
        commands.runIfLatest(id, superseded = { ran += "skip $name" }) { ran += name }
        done.countDown()
    }.apply { start() }

    /** Holds the lock (a long start) until [release]; returns once it holds it. */
    private fun holdLock(release: CountDownLatch) {
        val held = CountDownLatch(1)
        Thread { synchronized(commands.lock) { held.countDown(); release.await() } }.start()
        held.await()
    }

    private fun waitForBlocked(vararg threads: Thread) {
        val deadline = System.currentTimeMillis() + 2000
        while (threads.any { it.state != Thread.State.BLOCKED } && System.currentTimeMillis() < deadline) Thread.sleep(5)
    }

    @Test
    fun `a disconnect that waited behind a long start doesn't stop the newer connect`() {
        val release = CountDownLatch(1)
        holdLock(release)
        val done = CountDownLatch(2)
        val disconnect = command("disconnect", commands.issue(), done)
        val connect = command("connect", commands.issue(), done)
        waitForBlocked(disconnect, connect)
        release.countDown()
        assertTrue(done.await(2, TimeUnit.SECONDS))
        // Whichever thread got the lock first, only the newest command touched the session.
        assertEquals(setOf("connect", "skip disconnect"), ran.toSet())
    }

    @Test
    fun `of two queued connects only the newer one starts`() {
        val release = CountDownLatch(1)
        holdLock(release)
        val done = CountDownLatch(2)
        val older = command("connect 1", commands.issue(), done)
        val newer = command("connect 2", commands.issue(), done)
        waitForBlocked(older, newer)
        release.countDown()
        assertTrue(done.await(2, TimeUnit.SECONDS))
        assertEquals(setOf("connect 2", "skip connect 1"), ran.toSet())
    }

    @Test
    fun `a command alone runs, and stays latest until another one arrives`() {
        val id = commands.issue()
        assertTrue(commands.isLatest(id))
        assertTrue(commands.runIfLatest(id) { ran += "run" })
        commands.issue()
        assertFalse(commands.isLatest(id))
        assertFalse(commands.runIfLatest(id) { ran += "late" })
        assertEquals(listOf("run"), ran)
    }

    @Test
    fun `a quick start yields to a later command but doesn't cancel an earlier one`() {
        val connect = commands.issue()
        val quick = commands.current()
        assertTrue(commands.isLatest(connect)) // the quick start took no new number
        assertTrue(commands.runIfLatest(quick) { ran += "quick" })
        val disconnect = commands.issue()
        assertFalse(commands.runIfLatest(quick) { ran += "late quick" })
        assertTrue(commands.isLatest(disconnect))
        assertEquals(listOf("quick"), ran)
    }
}
