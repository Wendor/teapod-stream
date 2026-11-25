package com.teapodstream.teapodstream

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

class QuickConnectRequestsTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private val starts = AtomicLong()
    private val tileNames = mutableListOf<String?>()
    private val store by lazy { QuickConnectStore(tmp.root) }
    private val requests by lazy { QuickConnectRequests(store, starts::get) { tileNames += it } }

    private fun args(config: String) = ConnectArgs.from(mapOf("xrayConfig" to config, "configName" to "n-$config"))!!

    /** Runs [calls] the way the channel does: on ChannelWork's single quick-connect thread, in call order. */
    private fun inOrder(vararg calls: () -> Unit) {
        val pool = Executors.newSingleThreadExecutor()
        calls.forEach { pool.execute(it) }
        pool.shutdown()
        assertTrue(pool.awaitTermination(5, TimeUnit.SECONDS))
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
    fun aSessionStartedSinceTheCheckKeepsItsData() {
        store.save("{session}", args("{session}").params, "u", "p")
        val seen = starts.get()
        starts.incrementAndGet() // a session started (and may have stopped) after the check
        assertFalse(requests.save(args("{old}"), seen))
        assertFalse(requests.clear(seen))
        assertEquals("{session}", store.config())
        assertTrue(tileNames.isEmpty())
    }
}
