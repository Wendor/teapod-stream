package com.teapodstream.teapodstream

/**
 * Скорости для графика — последние [capacity] точек, пронумерованные: клиент
 * забирает только новые. Номер растёт монотонно, эпоха меняется на каждом
 * [reset] (новая сессия). Без Android-типов — покрыто JVM-тестами.
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
     * Точки после [since] той же [clientEpoch]. Если клиент отстал больше чем на
     * буфер, опоздал на новую сессию или пришёл впервые (epoch < 0) — весь буфер
     * с `full = true`. `from` — номер точки перед первой отданной: клиент применяет
     * ответ, только если он продолжает его историю.
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
