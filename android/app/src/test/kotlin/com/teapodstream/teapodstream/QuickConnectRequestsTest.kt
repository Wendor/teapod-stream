package com.teapodstream.teapodstream

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

class QuickConnectRequestsTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private val starts = AtomicLong()
    private val tileNames = mutableListOf<String?>()
    private val store by lazy { QuickConnectStore(tmp.root) }
    // The tile is told after each committed change; it reads the name from the store.
    private val requests by lazy { QuickConnectRequests(store, starts::get) { tileNames += store.tileName() } }

    private fun args(config: String) = ConnectArgs.from(mapOf("xrayConfig" to config, "configName" to "n-$config"))!!

    /**
     * Runs [calls] the way the channel does: [ChannelWork.answer] on [ChannelWork.quickConnect]. The first call waits
     * until every call is queued, so a pool that runs them side by side would let a later one pass it.
     */
    private fun inOrder(vararg calls: () -> Boolean) {
        val queued = CountDownLatch(1)
        val answered = CountDownLatch(calls.size)
        val errors = java.util.Collections.synchronizedList(mutableListOf<String>())
        val work = ChannelWork { it.run() }
        calls.forEachIndexed { i, call ->
            work.answer(Answered(answered, errors), ChannelWork.quickConnect) {
                if (i == 0) queued.await(5, TimeUnit.SECONDS)
                call()
            }
        }
        queued.countDown()
        assertTrue(answered.await(5, TimeUnit.SECONDS))
        assertTrue(errors.toString(), errors.isEmpty())
    }

    /** Counts every answer down; errors are checked on the test's thread. */
    private class Answered(private val latch: CountDownLatch, private val errors: MutableList<String>) :
        MethodChannel.Result {
        override fun success(result: Any?) = latch.countDown()
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            errors += "$errorCode: $errorMessage"
            latch.countDown()
        }
        override fun notImplemented() {
            errors += "notImplemented"
            latch.countDown()
        }
    }

    @Test
    fun theLaterOfTwoSavesStays() {
        inOrder({ requests.save(args("{a}"), 0) }, { requests.save(args("{b}"), 0) })
        assertEquals("{b}", store.config())
        assertEquals(listOf<String?>("n-{a}", "n-{b}"), tileNames)
    }

    @Test
    fun aSaveThenAClearLeavesNothing() {
        inOrder({ requests.save(args("{a}"), 0) }, { requests.clear(0) })
        assertNull(store.config())
        assertNull(store.params())
        assertEquals(listOf<String?>("n-{a}", null), tileNames)
    }

    @Test
    fun aFailedSaveStillTellsTheTile() {
        java.io.File(tmp.root, QuickConnectStore.PARAMS).mkdir()
        java.io.File(tmp.root, "${QuickConnectStore.PARAMS}/x").writeText("")
        assertTrue(runCatching { requests.save(args("{a}"), 0) }.isFailure)
        assertEquals(listOf<String?>(null), tileNames)
    }

    @Test
    fun aSessionStartedSinceTheCheckKeepsItsData() {
        store.save("{session}", args("{session}").params)
        val seen = starts.get()
        starts.incrementAndGet() // a session started (and may have stopped) after the check
        assertFalse(requests.save(args("{old}"), seen))
        assertFalse(requests.clear(seen))
        assertEquals("{session}", store.config())
        assertTrue(tileNames.isEmpty())
    }
}
