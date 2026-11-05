package com.teapodstream.teapodstream

import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class PrefixTcpProxyTest {
    private lateinit var target: ServerSocket
    private val proxies = mutableListOf<PrefixTcpProxy>()

    @Before
    fun startTarget() {
        target = ServerSocket(0, 50, InetAddress.getLoopbackAddress())
    }

    @After
    fun stopAll() {
        proxies.forEach { it.stop() }
        target.close()
    }

    private fun proxy(prefix: ByteArray, allowed: ((Socket) -> Boolean)? = null) =
        PrefixTcpProxy("127.0.0.1", target.localPort, prefix, allowed).also {
            proxies += it
            it.start()
        }

    /** Целевой сервер: (первое чтение, остаток потока); отвечает [reply]. */
    private fun acceptOnce(reply: ByteArray): CompletableFuture<Pair<ByteArray, ByteArray>> =
        CompletableFuture.supplyAsync {
            target.accept().use { s ->
                s.soTimeout = 5000
                val buf = ByteArray(65536)
                val n = s.inputStream.read(buf)
                s.outputStream.write(reply)
                s.outputStream.flush()
                s.shutdownOutput()
                buf.copyOf(n) to s.inputStream.readBytes()
            }
        }

    @Test
    fun prefixAndFirstChunkArriveTogetherAndTrafficFlowsBothWays() {
        val received = acceptOnce("pong".toByteArray())
        val p = proxy(byteArrayOf(0x16, 0x03, 0x01))
        Socket(InetAddress.getLoopbackAddress(), p.localPort).use { c ->
            c.soTimeout = 5000
            c.outputStream.write("hello".toByteArray())
            c.outputStream.flush()
            assertEquals("pong", String(c.inputStream.readBytes()))
            c.outputStream.write("more".toByteArray())
            c.shutdownOutput()
        }
        val (first, rest) = received.get(5, TimeUnit.SECONDS)
        // Префикс уходит одной записью с первыми данными клиента (обход DPI).
        assertArrayEquals(byteArrayOf(0x16, 0x03, 0x01) + "hello".toByteArray(), first)
        assertArrayEquals("more".toByteArray(), rest)
    }

    @Test
    fun listensOnLoopbackOnly() {
        val p = proxy(byteArrayOf(1))
        assertTrue(p.localPort > 0)
        val server = PrefixTcpProxy::class.java.getDeclaredField("serverSocket")
            .apply { isAccessible = true }.get(p) as ServerSocket
        assertTrue(server.inetAddress.isLoopbackAddress)
    }

    @Test
    fun rejectedClientIsClosedWithoutReachingTarget() {
        val p = proxy(byteArrayOf(1)) { false }
        Socket(InetAddress.getLoopbackAddress(), p.localPort).use { c ->
            c.soTimeout = 5000
            c.outputStream.write("x".toByteArray())
            assertEquals(-1, c.inputStream.read())
        }
        target.soTimeout = 300
        val reached = runCatching { target.accept().close() }.isSuccess
        assertEquals(false, reached)
    }

    @Test
    fun clientClosingWithoutDataNeverDialsTarget() {
        val p = proxy(byteArrayOf(1))
        Socket(InetAddress.getLoopbackAddress(), p.localPort).close()
        target.soTimeout = 300
        assertEquals(false, runCatching { target.accept().close() }.isSuccess)
    }

    @Test
    fun stopClosesTheListener() {
        val p = proxy(byteArrayOf(1))
        val port = p.localPort
        p.stop()
        assertTrue(runCatching { Socket(InetAddress.getLoopbackAddress(), port).close() }.isFailure)
    }
}
