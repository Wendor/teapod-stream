package com.teapodstream.teapodstream

import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/** What the session should be. Commands only replace it; [SessionReconciler] brings the running session to it. */
internal sealed interface Desired {
    /** No session; [attempt] — the Flutter connect the stop answers. */
    data class Off(val attempt: Long) : Desired

    /**
     * A session of [request]. [id] tells two of them apart: a retry or a reconnect of the same config is a new one.
     * [waitForNetwork] — a network-change reconnect: the start waits for direct internet first.
     */
    data class On(val request: StartRequest, val id: Long, val waitForNetwork: Boolean = false) : Desired

    /** The Flutter connect the session's states are tagged with (0 — a native start). */
    val tag: Long get() = when (this) {
        is Off -> attempt
        is On -> request.attempt
    }
}

/**
 * The session as the worker sees it: [running] — the [Desired.On.id] it started and that still runs; [failed] — the
 * one whose start failed or whose session ended by itself (not started again until replaced); [sinkHeld] — a TUN
 * sink without a session (the kill switch's block).
 */
internal data class Actual(val running: Long? = null, val failed: Long? = null, val sinkHeld: Boolean = false)

internal sealed interface Action {
    /** The session is where it should be. */
    data object Settled : Action

    /** Stop the running session; [forNext] — a new one follows, the TUN stays a sink until its establish(). */
    data class Stop(val forNext: Boolean) : Action

    /** Close the kill switch's sink. */
    data object CloseSink : Action

    data class Start(val on: Desired.On) : Action
}

/** The one decision: what brings [actual] closer to [desired]. */
internal fun nextAction(desired: Desired, actual: Actual): Action = when (desired) {
    is Desired.Off -> when {
        actual.running != null -> Action.Stop(forNext = false)
        actual.sinkHeld -> Action.CloseSink
        else -> Action.Settled
    }
    is Desired.On -> when {
        actual.running == desired.id -> Action.Settled
        actual.running != null -> Action.Stop(forNext = true)
        actual.failed == desired.id -> Action.Settled
        else -> Action.Start(desired)
    }
}

/** What [SessionReconciler] drives: the service's session. Called only on the reconciler's thread. */
internal interface SessionDriver {
    fun running(): Boolean
    fun sinkHeld(): Boolean

    /** [desired] owns the session's states from here on (their attempt tag). */
    fun own(desired: Desired)
    fun stop(forNext: Boolean)
    fun closeSink()

    /** Starts [on]'s session; false — it failed (the driver decides about a retry: [SessionReconciler.replace]). */
    fun start(on: Desired.On): Boolean

    /** [desired] is reached (also the [Desired.Off] a stop or a never-started connect ends in). */
    fun settled(desired: Desired)

    /** After every run, once it is no longer [SessionReconciler.busy] for it. */
    fun afterRun()
}

/**
 * Keeps the one [Desired] state and brings the session to it on one thread. [set] and [replace] only swap the state
 * and ask for a run; a run loops [nextAction] until settled, so a command that was replaced before its turn never acts:
 * only the latest state exists. A long start isn't interrupted; the loop then stops it and starts what is wanted now.
 */
internal class SessionReconciler(
    private val driver: SessionDriver,
    private val executor: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "session").apply { isDaemon = true }
    },
) {
    private val ids = AtomicLong(0)
    private val lock = Any()
    @Volatile var desired: Desired = Desired.Off(0)
        private set
    /** The Flutter connect a disconnect answers: the last one received. */
    @Volatile var lastAttempt = 0L
        private set
    private var pending = 0
    // The worker's own view, on its thread only.
    private var started: Long? = null
    private var failed: Long? = null
    private var reported: Desired? = null

    fun newId(): Long = ids.incrementAndGet()

    fun set(next: Desired) {
        synchronized(lock) {
            desired = next
            if (next is Desired.On && next.request.attempt > 0) lastAttempt = next.request.attempt
            pending++
        }
        executor.execute(::run)
    }

    /** Sets [next] only while [expected] is still the desired state (a reconnect or a retry of that session). */
    fun replace(expected: Desired, next: Desired): Boolean {
        synchronized(lock) { if (desired !== expected) return false }
        set(next)
        return true
    }

    /** A change was asked for and its run hasn't finished: the service is still busy. */
    fun busy(): Boolean = synchronized(lock) { pending > 0 }

    private fun actual(): Actual {
        val alive = started?.takeIf { driver.running() }
        if (started != null && alive == null) failed = started // ended by itself: not started again
        started = alive
        return Actual(running = alive, failed = failed, sinkHeld = driver.sinkHeld())
    }

    private fun run() {
        try {
            while (true) {
                val wanted = desired
                when (val action = nextAction(wanted, actual())) {
                    Action.Settled -> {
                        // Once per desired state: later runs that find it reached have nothing to report.
                        if (reported !== wanted) driver.settled(wanted)
                        reported = wanted
                        // Replaced meanwhile: the next queued run brings the session to it.
                        if (desired === wanted) break else continue
                    }
                    is Action.Stop -> {
                        driver.own(wanted)
                        driver.stop(action.forNext)
                        started = null
                    }
                    Action.CloseSink -> driver.closeSink()
                    is Action.Start -> {
                        driver.own(wanted)
                        failed = null
                        if (driver.start(action.on)) started = action.on.id else failed = action.on.id
                    }
                }
            }
        } finally {
            synchronized(lock) { pending-- }
            driver.afterRun()
        }
    }
}
