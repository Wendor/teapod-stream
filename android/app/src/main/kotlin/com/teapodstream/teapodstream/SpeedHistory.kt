package com.teapodstream.teapodstream

/**
 * Speeds for the chart — the last [capacity] points, numbered: the client
 * fetches only new ones. The number grows monotonically, the epoch changes on every
 * [reset] (a new session). No Android types — covered by JVM tests.
 */
internal class SpeedHistory(private val capacity: Int) {
    private val points = ArrayDeque<Pair<Long, Long>>(capacity)
    private var seq = 0L
    private var epoch = 0

    @Synchronized
    fun add(upload: Long, download: Long) {
        if (points.size >= capacity) points.removeFirst()
        points.addLast(upload to download)
        seq++
    }

    @Synchronized
    fun reset() {
        points.clear()
        epoch++
    }

    /**
     * Points after [since] of the same [clientEpoch]. If the client lagged behind by more than
     * the buffer, missed a new session or came for the first time (epoch < 0) — the whole buffer
     * with `full = true`. `from` — the number of the point before the first one returned: the client applies
     * the response only if it continues its history.
     */
    @Synchronized
    fun since(clientEpoch: Int, since: Long): Map<String, Any> {
        val first = seq - points.size
        val full = clientEpoch != epoch || since < first || since > seq
        val from = if (full) first else since
        return mapOf(
            "epoch" to epoch,
            "seq" to seq,
            "from" to from,
            "full" to full,
            "history" to points.drop((from - first).toInt()).map { (up, down) ->
                mapOf("uploadSpeed" to up, "downloadSpeed" to down)
            },
        )
    }
}
