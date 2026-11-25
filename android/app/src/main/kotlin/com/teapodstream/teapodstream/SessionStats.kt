package com.teapodstream.teapodstream

/// Traffic of the running session: totals and speeds sampled by the service's stats thread, and the
/// speed chart history. Read by Flutter (`getStats`, `getStatsHistory`, the stats event stream).
object SessionStats {
    const val INTERVAL_MS = 1_000L
    // Nobody looks at speeds while the screen is off — poll 10x slower so the CPU isn't woken
    // every second all night. Totals stay exact (cumulative counters), speeds average over the
    // longer interval.
    const val INTERVAL_SCREEN_OFF_MS = 10_000L
    private const val MAX_HISTORY = 300

    @Volatile private var upload = 0L
    @Volatile private var download = 0L
    @Volatile var uploadSpeed = 0L
        private set
    @Volatile var downloadSpeed = 0L
        private set
    private var lastTime = 0L
    private val history = SpeedHistory(MAX_HISTORY)

    fun get(): Map<String, Long> = mapOf(
        "upload" to upload,
        "download" to download,
        "uploadSpeed" to uploadSpeed,
        "downloadSpeed" to downloadSpeed,
    )

    /** Chart history after point [since] of epoch [epoch] (see [SpeedHistory.since]). */
    fun history(epoch: Int, since: Long): Map<String, Any> = history.since(epoch, since)

    /** A new session: zero totals and speeds, a new chart epoch. */
    fun reset(now: Long) {
        upload = 0
        download = 0
        uploadSpeed = 0
        downloadSpeed = 0
        lastTime = now
        history.reset()
    }

    /** The core's cumulative counters [tx] / [rx] at [now]; [chart] — add the speeds to the chart. */
    fun sample(tx: Long, rx: Long, now: Long, chart: Boolean) {
        val elapsed = (now - lastTime) / 1000.0
        if (elapsed > 0) {
            uploadSpeed = ((tx - upload) / elapsed).toLong().coerceAtLeast(0)
            downloadSpeed = ((rx - download) / elapsed).toLong().coerceAtLeast(0)
        }
        upload = tx
        download = rx
        lastTime = now
        if (chart) history.add(uploadSpeed, downloadSpeed)
    }
}
