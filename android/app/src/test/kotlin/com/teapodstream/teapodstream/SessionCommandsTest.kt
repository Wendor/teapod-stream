package com.teapodstream.teapodstream

import com.teapodstream.teapodstream.SessionCommands.Kind
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

    private fun submit(kind: Kind, name: String) =
        commands.submit(kind, skipped = { ran += "skip $name" }) { ran += name }

    /** A long start occupying the queue until [release]; returns once it runs. */
    private fun longStart(release: CountDownLatch) {
        val running = CountDownLatch(1)
        commands.submit(Kind.CONNECT) {
            running.countDown()
            release.await()
        }
        assertTrue(running.await(2, TimeUnit.SECONDS))
    }

    private fun finish(last: SessionCommands.Command) = last.done.get(2, TimeUnit.SECONDS)

    @Test
    fun `disconnect then connect behind a long start stop first and the new session stays`() {
        val release = CountDownLatch(1)
        longStart(release)
        submit(Kind.DISCONNECT, "disconnect")
        val last = submit(Kind.CONNECT, "connect")
        release.countDown()
        finish(last)
        assertEquals(listOf("disconnect", "connect"), ran)
    }

    @Test
    fun `of queued connects only the newest starts`() {
        val release = CountDownLatch(1)
        longStart(release)
        submit(Kind.CONNECT, "connect 1")
        val last = submit(Kind.CONNECT, "connect 2")
        release.countDown()
        finish(last)
        assertEquals(listOf("skip connect 1", "connect 2"), ran)
    }

    @Test
    fun `a connect followed by a disconnect doesn't start`() {
        val release = CountDownLatch(1)
        longStart(release)
        submit(Kind.CONNECT, "connect")
        val last = submit(Kind.DISCONNECT, "disconnect")
        release.countDown()
        finish(last)
        assertEquals(listOf("skip connect", "disconnect"), ran)
    }

    @Test
    fun `a quick start after a disconnect runs after the stop`() {
        val release = CountDownLatch(1)
        longStart(release)
        submit(Kind.DISCONNECT, "disconnect")
        val last = submit(Kind.QUICK, "quick")
        release.countDown()
        finish(last)
        assertEquals(listOf("disconnect", "quick"), ran)
    }

    @Test
    fun `commands run under the session lock`() {
        val held = CountDownLatch(1)
        val release = CountDownLatch(1)
        Thread { synchronized(commands.lock) { held.countDown(); release.await() } }.start()
        assertTrue(held.await(2, TimeUnit.SECONDS))
        val c = submit(Kind.QUICK, "quick")
        Thread.sleep(100)
        assertTrue(ran.isEmpty()) // waits for the lock a deferred reconnect holds
        release.countDown()
        finish(c)
        assertEquals(listOf("quick"), ran)
    }

    @Test
    fun `isLatest tracks the last command received`() {
        val a = submit(Kind.DISCONNECT, "a")
        assertTrue(commands.isLatest(a.id))
        val b = submit(Kind.QUICK, "b")
        assertFalse(commands.isLatest(a.id))
        finish(b)
    }

    @Test
    fun `a quick start followed by a connect or a disconnect doesn't start`() {
        val release = CountDownLatch(1)
        longStart(release)
        submit(Kind.QUICK, "quick 1")
        submit(Kind.CONNECT, "connect")
        submit(Kind.QUICK, "quick 2")
        val last = submit(Kind.DISCONNECT, "disconnect")
        release.countDown()
        finish(last)
        assertEquals(listOf("skip quick 1", "skip connect", "skip quick 2", "disconnect"), ran)
    }
}
