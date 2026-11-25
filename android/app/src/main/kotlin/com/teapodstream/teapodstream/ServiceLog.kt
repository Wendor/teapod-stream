package com.teapodstream.teapodstream

import java.io.File

/// The service's log: `vpn_log.txt` in filesDir (the previous session's in `vpn_log.prev.txt`),
/// logcat and the Flutter log events. Lines are buffered and flushed in batches: a FileWriter
/// open per line wakes flash storage on every heartbeat/xray-access event; warning/error flush
/// immediately so crash diagnostics never sit in the buffer.
object ServiceLog {
    const val FILE_NAME = "vpn_log.txt"
    const val PREV_FILE_NAME = "vpn_log.prev.txt"
    /** Guards the log files and the buffer; readers flush under it first ([flush]). */
    val LOCK = Any()
    /** The user toggle in [XrayVpnService.PREFS_NAME]. */
    const val PREF_ENABLED = "logs_enabled"

    // User toggle: when off, only warning/error are logged (file + UI) so a broken
    // session still leaves diagnostics. Persisted by VpnChannelHandler.
    @Volatile var enabled = true

    private val buffer = StringBuilder()
    private var lastFlushMs = 0L
    private const val FLUSH_INTERVAL_MS = 5_000L
    private const val FLUSH_SIZE_CHARS = 8 * 1024

    @JvmStatic fun flush(filesDir: File) {
        synchronized(LOCK) { flushLocked(filesDir) }
    }

    private fun flushLocked(filesDir: File) {
        if (buffer.isEmpty()) return
        try {
            java.io.FileWriter(File(filesDir, FILE_NAME), true).use { it.write(buffer.toString()) }
        } catch (_: Exception) {}
        buffer.setLength(0)
        lastFlushMs = System.currentTimeMillis()
    }

    fun write(filesDir: File, level: String, message: String) {
        if (!enabled && level != "warning" && level != "error") return
        android.util.Log.i("TeapodVPN", "[$level] $message")
        append(filesDir, level, message)
        if (level != "debug" || BuildConfig.DEBUG) {
            VpnEventStreamHandler.sendLogEvent(level, message)
        }
    }

    private fun append(filesDir: File, level: String, message: String) {
        try {
            val line = "${System.currentTimeMillis()}|$level|${message.replace("\n", " ")}\n"
            synchronized(LOCK) {
                buffer.append(line)
                if (level == "warning" || level == "error"
                    || buffer.length >= FLUSH_SIZE_CHARS
                    || System.currentTimeMillis() - lastFlushMs >= FLUSH_INTERVAL_MS
                ) {
                    flushLocked(filesDir)
                }
            }
        } catch (_: Exception) {}
    }

    /// A new session's log. Rotate instead of wiping: the previous session's log survives one
    /// connect, so a hang that forced the user to reconnect can still be diagnosed afterwards.
    fun rotate(filesDir: File) {
        try {
            synchronized(LOCK) {
                flushLocked(filesDir)
                val current = File(filesDir, FILE_NAME)
                val prev = File(filesDir, PREV_FILE_NAME)
                prev.delete()
                if (current.exists() && current.length() > 0) {
                    current.renameTo(prev)
                }
                current.writeText("")
            }
        } catch (_: Exception) {}
    }
}
