package com.teapodstream.teapodstream

import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.atomic.AtomicLong

/**
 * The session commands of [XrayVpnService] — connect, disconnect, quick start — run one at a time, in the order the
 * service received them, on one thread and under [lock] (which a deferred reconnect's stop also takes). Threads
 * waiting for a lock don't enter in arrival order; a queue does, so a disconnect that waited behind a long start
 * can't stop the session of a connect received after it.
 *
 * A connect or a quick start is skipped when a connect or a disconnect was received after it: the session it would
 * start is replaced right away. Disconnects always run.
 *
 * [submit] must be called on one thread (the main thread, `onStartCommand`): the numbers follow the queue order.
 */
internal class SessionCommands(
    val lock: Any = Any(),
    private val executor: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "session-commands").apply { isDaemon = true }
    },
) {
    enum class Kind { CONNECT, DISCONNECT, QUICK }

    class Command(val id: Long, val done: Future<*>)

    private val issued = AtomicLong(0)
    @Volatile private var lastConnect = 0L
    @Volatile private var lastDisconnect = 0L

    /** Queues [block]; [skipped] runs instead (also in order, under [lock]) when a connect turns out superseded. */
    fun submit(kind: Kind, skipped: () -> Unit = {}, block: () -> Unit): Command {
        val id = issued.incrementAndGet()
        when (kind) {
            Kind.CONNECT -> lastConnect = id
            Kind.DISCONNECT -> lastDisconnect = id
            Kind.QUICK -> {}
        }
        val done = executor.submit {
            synchronized(lock) {
                val replaced = when (kind) {
                    Kind.CONNECT -> lastConnect != id || lastDisconnect > id
                    Kind.QUICK -> lastConnect > id || lastDisconnect > id
                    Kind.DISCONNECT -> false
                }
                if (replaced) skipped() else block()
            }
        }
        return Command(id, done)
    }

    /** Whether no command was received after [id]. */
    fun isLatest(id: Long): Boolean = issued.get() == id

    /** Whether a connect was received after [id] — its session owns the state from then on. */
    fun connectAfter(id: Long): Boolean = lastConnect > id
}
