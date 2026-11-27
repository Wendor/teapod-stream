package com.teapodstream.teapodstream

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor
import java.util.concurrent.Executors

/** A method-channel method: answers [MethodChannel.Result] once, now or later. */
internal typealias ChannelMethod = (MethodCall, MethodChannel.Result) -> Unit

/**
 * Runs a method's blocking work off the main thread and answers on [main] (the channel's thread). A throw is answered
 * as an `ERROR`, so the Dart call never hangs.
 */
internal class ChannelWork(private val main: Executor) {

    fun <T> answer(result: MethodChannel.Result, pool: Executor = io, work: () -> T) {
        pool.execute {
            val outcome = runCatching(work)
            main.execute {
                outcome.fold(result::success) { result.error("ERROR", it.message ?: it.javaClass.simpleName, null) }
            }
        }
    }

    companion object {
        /** File, package-manager and core work: short, reused threads. */
        val io: Executor = Executors.newCachedThreadPool()

        // Pinging all configs and urltest over candidates send bursts of calls: without a limit —
        // a `ping` process / temporary core instance per config at once.
        val ping: Executor = Executors.newFixedThreadPool(8)
        val measure: Executor = Executors.newFixedThreadPool(4)

        /** Flutter's quick-connect saves and clears, one at a time in call order. */
        val quickConnect: Executor = Executors.newSingleThreadExecutor()
    }
}

/** The arguments of `connect` and `saveQuickConnect`; null without the core config. */
internal data class ConnectArgs(
    val config: String,
    val params: ConnectionParams,
    val socksUser: String,
    val socksPassword: String,
    val configName: String?,
    val attempt: Long,
) {
    override fun toString() = "ConnectArgs(engine=${params.engine.id}, attempt=$attempt)"

    companion object {
        fun from(args: Map<*, *>): ConnectArgs? {
            val config = args["xrayConfig"] as? String ?: return null
            return ConnectArgs(
                config,
                ConnectionParams.fromArgs(args),
                socksUser = args["socksUser"] as? String ?: "",
                socksPassword = args["socksPassword"] as? String ?: "",
                configName = args["configName"] as? String,
                attempt = (args["attempt"] as? Number)?.toLong() ?: 0,
            )
        }
    }
}
