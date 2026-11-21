package com.teapodstream.teapodstream

import java.util.concurrent.atomic.AtomicLong

/**
 * Orders the session commands of [XrayVpnService] (`ACTION_CONNECT`, `ACTION_DISCONNECT`). Each takes a number when
 * the service receives it ([issue], main thread) and runs its work later on its own thread under [lock]; the JVM
 * doesn't let waiting threads in in arrival order, so a command that a newer one superseded while it waited must not
 * touch the session at all. [runIfLatest] checks that under the lock.
 */
internal class SessionCommands(val lock: Any = Any()) {
    private val issued = AtomicLong(0)

    /** A number for a command received now; newer commands get larger numbers. */
    fun issue(): Long = issued.incrementAndGet()

    /** Whether no command was received after [command]. */
    fun isLatest(command: Long): Boolean = issued.get() == command

    /**
     * Runs [block] under [lock] if [command] is still the latest when it gets the lock; otherwise runs [superseded]
     * (also under the lock) and returns false.
     */
    fun runIfLatest(command: Long, superseded: () -> Unit = {}, block: () -> Unit): Boolean = synchronized(lock) {
        if (!isLatest(command)) {
            superseded()
            return@synchronized false
        }
        block()
        true
    }
}
