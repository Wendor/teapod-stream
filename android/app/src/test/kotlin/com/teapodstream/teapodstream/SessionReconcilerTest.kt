package com.teapodstream.teapodstream

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class SessionReconcilerTest {
    private companion object {
        val PARAMS = ConnectionParams.fromArgs(emptyMap<String, Any>())
    }

    private fun request(config: String, attempt: Long = 0) =
        StartRequest(config, PARAMS, "u", "p", attempt, reconnect = attempt == 0L)

    private fun on(id: Long, config: String = "c$id") = Desired.On(request(config), id)

    // --- the decision ---

    @Test
    fun `next action table`() {
        val off = Desired.Off(0)
        val cases = listOf(
            Triple(off, Actual(), Action.Settled),
            Triple(off, Actual(running = 1), Action.Stop(forNext = false)),
            Triple(off, Actual(sinkHeld = true), Action.CloseSink),
            Triple(off, Actual(running = 1, sinkHeld = true), Action.Stop(forNext = false)),
            Triple(on(1), Actual(), Action.Start(on(1))),
            Triple(on(1), Actual(sinkHeld = true), Action.Start(on(1))),
            Triple(on(1), Actual(running = 1), Action.Settled),
            Triple(on(2), Actual(running = 1), Action.Stop(forNext = true)),
            Triple(on(1), Actual(failed = 1), Action.Settled),
            Triple(on(2), Actual(failed = 1), Action.Start(on(2))),
        )
        for ((desired, actual, expected) in cases) assertEquals("$desired / $actual", expected, nextAction(desired, actual))
    }

    // --- the worker ---

    /** Records what the reconciler did; a start of a config in [hold] waits for its latch, one in [fail] fails. */
    private class Driver : SessionDriver {
        val events: MutableList<String> = Collections.synchronizedList(mutableListOf())
        val hold = mutableMapOf<String, CountDownLatch>()
        val started = mutableMapOf<String, CountDownLatch>()
        val fail = mutableSetOf<String>()
        @Volatile var running: String? = null
        @Volatile var sink = false
        var runs = 0

        override fun running() = running != null
        override fun sinkHeld() = sink
        override fun own(desired: Desired) {
            events += "own ${desired.tag}"
        }
        override fun stop(forNext: Boolean) {
            events += "stop ${running}${if (forNext) " for next" else ""}"
            sink = forNext
            running = null
        }
        override fun closeSink() {
            events += "close sink"
            sink = false
        }
        override fun start(on: Desired.On): Boolean {
            val config = on.request.config
            started[config]?.countDown()
            hold[config]?.await(5, TimeUnit.SECONDS)
            if (config in fail) {
                events += "start $config failed"
                return false
            }
            events += "start $config"
            running = config
            sink = false
            return true
        }
        override fun settled(desired: Desired) {
            events += "settled ${if (desired is Desired.On) desired.request.config else "off"}"
        }
        override fun afterRun() {
            runs++
        }
    }

    private val driver = Driver()
    private val executor = Executors.newSingleThreadExecutor()
    private val reconciler = SessionReconciler(driver, executor)

    @After
    fun tearDown() {
        executor.shutdownNow()
    }

    private fun idle() {
        // Runs are queued on the executor: a no-op task after them marks the end.
        executor.submit {}.get(5, TimeUnit.SECONDS)
        assertFalse(reconciler.busy())
    }

    /** Connects [config] and waits until its start began (it waits for [release]). */
    private fun longStart(config: String, release: CountDownLatch) {
        val began = CountDownLatch(1)
        driver.hold[config] = release
        driver.started[config] = began
        reconciler.set(Desired.On(request(config, attempt = 1), reconciler.newId()))
        assertTrue(began.await(5, TimeUnit.SECONDS))
    }

    @Test
    fun `a connect starts and settles`() {
        reconciler.set(Desired.On(request("a", attempt = 3), reconciler.newId()))
        idle()
        assertEquals(listOf("own 3", "start a", "settled a"), driver.events)
        assertEquals(3, reconciler.lastAttempt)
    }

    @Test
    fun `disconnect then connect behind a long start stop first and the new session stays`() {
        val release = CountDownLatch(1)
        longStart("a", release)
        reconciler.set(Desired.Off(1))
        reconciler.set(Desired.On(request("b", attempt = 2), reconciler.newId()))
        release.countDown()
        idle()
        assertEquals(listOf("own 1", "start a", "own 2", "stop a for next", "own 2", "start b", "settled b"), driver.events)
        assertEquals("b", driver.running)
    }

    @Test
    fun `of connects received during a start only the newest starts`() {
        val release = CountDownLatch(1)
        longStart("a", release)
        reconciler.set(Desired.On(request("b", attempt = 2), reconciler.newId()))
        reconciler.set(Desired.On(request("c", attempt = 3), reconciler.newId()))
        release.countDown()
        idle()
        assertFalse("b never starts", driver.events.any { it == "start b" })
        assertEquals("c", driver.running)
    }

    @Test
    fun `a connect followed by a disconnect doesn't start`() {
        val release = CountDownLatch(1)
        longStart("a", release)
        reconciler.set(Desired.On(request("b", attempt = 2), reconciler.newId()))
        reconciler.set(Desired.Off(2))
        release.countDown()
        idle()
        assertFalse(driver.events.any { it == "start b" })
        assertEquals(listOf("own 1", "start a", "own 2", "stop a", "settled off"), driver.events)
    }

    @Test
    fun `a quick start after a disconnect runs after the stop`() {
        reconciler.set(Desired.On(request("a", attempt = 1), reconciler.newId()))
        reconciler.set(Desired.Off(1))
        reconciler.set(on(reconciler.newId(), "q"))
        idle()
        assertEquals("q", driver.running)
        assertFalse("a stop never follows the quick start", driver.events.last().startsWith("stop"))
    }

    @Test
    fun `a disconnect from the kill switch's block closes the sink and reports off`() {
        driver.sink = true
        reconciler.set(Desired.Off(4))
        idle()
        assertEquals(listOf("close sink", "settled off"), driver.events)
    }

    @Test
    fun `a failed start isn't retried by itself, a retry is a new desired state`() {
        driver.fail += "a"
        val first = on(reconciler.newId(), "a")
        reconciler.set(first)
        idle()
        assertEquals(listOf("own 0", "start a failed", "settled a"), driver.events)
        driver.fail.clear()
        val retry = on(reconciler.newId(), "a")
        assertTrue(reconciler.replace(first, retry))
        idle()
        assertEquals("a", driver.running)
    }

    @Test
    fun `a reconnect or retry of a replaced session doesn't apply`() {
        val old = on(reconciler.newId(), "a")
        reconciler.set(old)
        reconciler.set(Desired.Off(0))
        idle()
        assertFalse(reconciler.replace(old, on(reconciler.newId(), "a")))
        idle()
        assertEquals(null, driver.running)
    }

    @Test
    fun `a session that ended by itself isn't started again until replaced`() {
        val first = on(reconciler.newId(), "a")
        reconciler.set(first)
        idle()
        driver.running = null // dropped (the kill switch keeps its sink)
        driver.sink = true
        reconciler.set(first) // any run: the same desired state
        idle()
        assertEquals(1, driver.events.count { it == "start a" })
    }

    @Test
    fun `busy from a change until its run has finished`() {
        val release = CountDownLatch(1)
        longStart("a", release)
        assertTrue(reconciler.busy())
        release.countDown()
        idle()
        assertEquals("every run reports its end", 1, driver.runs)
    }
}
