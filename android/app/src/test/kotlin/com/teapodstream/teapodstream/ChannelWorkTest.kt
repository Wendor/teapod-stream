package com.teapodstream.teapodstream

import com.teapodstream.teapodstream.core.CoreKind
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.Executor

class ChannelWorkTest {
    private class Recorded : MethodChannel.Result {
        val answers = mutableListOf<String>()
        override fun success(result: Any?) { answers += "success:$result" }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            answers += "error:$errorCode:$errorMessage"
        }
        override fun notImplemented() { answers += "notImplemented" }
    }

    /** Queues instead of running, so the test sees which thread step ran where. */
    private class Queue : Executor {
        val tasks = ArrayDeque<Runnable>()
        override fun execute(command: Runnable) { tasks += command }
        fun runAll() { while (tasks.isNotEmpty()) tasks.removeFirst().run() }
    }

    private val main = Queue()
    private val pool = Queue()
    private val work = ChannelWork(main)

    @Test
    fun theWorkRunsOnThePoolAndTheAnswerOnMain() {
        val result = Recorded()
        work.answer(result, pool) { 42 }
        assertTrue("nothing runs on the caller's thread", main.tasks.isEmpty() && result.answers.isEmpty())
        pool.runAll()
        assertTrue("not answered from the pool", result.answers.isEmpty())
        main.runAll()
        assertEquals(listOf("success:42"), result.answers)
    }

    @Test
    fun aThrowIsAnsweredAsAnErrorOnce() {
        val result = Recorded()
        work.answer(result, pool) { throw java.io.IOException("disk full") }
        pool.runAll()
        main.runAll()
        assertEquals(listOf("error:ERROR:disk full"), result.answers)
    }

    @Test
    fun connectArgsNeedTheConfigAndDefaultTheRest() {
        assertNull(ConnectArgs.from(mapOf("socksUser" to "u")))
        val args = ConnectArgs.from(mapOf("xrayConfig" to "{}", "engine" to "rust", "attempt" to 7))!!
        assertEquals("{}", args.config)
        assertEquals(CoreKind.RUST, args.params.engine)
        assertEquals("" to "", args.socksUser to args.socksPassword)
        assertNull(args.configName)
        assertEquals(7L, args.attempt)
        assertEquals(0L, ConnectArgs.from(mapOf("xrayConfig" to "{}"))!!.attempt)
        assertEquals(1L shl 40, ConnectArgs.from(mapOf("xrayConfig" to "{}", "attempt" to (1L shl 40)))!!.attempt)
    }

    @Test
    fun connectArgsKeepTheLoginOutOfToString() {
        val args = ConnectArgs.from(mapOf("xrayConfig" to "{secret}", "socksPassword" to "pw"))!!
        assertTrue(args.toString(), "pw" !in args.toString() && "secret" !in args.toString())
    }
}
