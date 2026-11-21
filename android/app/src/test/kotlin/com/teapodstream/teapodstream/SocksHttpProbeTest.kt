package com.teapodstream.teapodstream

import java.io.DataInputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

class SocksHttpProbeTest {
    private lateinit var server: ServerSocket
    private val target = SocksHttpProbe.Target("example.test", 80, "/generate_204", false)

    @Before
    fun start() {
        server = ServerSocket(0, 50, InetAddress.getLoopbackAddress())
    }

    @After
    fun stop() {
        server.close()
    }

    /** One SOCKS5 session: [script] reads the client's bytes and writes the replies; returns what it recorded. */
    private fun <T> serve(script: (DataInputStream, OutputStream) -> T): CompletableFuture<T> =
        CompletableFuture.supplyAsync {
            server.accept().use { s ->
                s.soTimeout = 5000
                script(DataInputStream(s.getInputStream()), s.getOutputStream())
            }
        }

    private fun DataInputStream.bytes(n: Int) = ByteArray(n).also { readFully(it) }

    /** Reads the CONNECT request for [target] and answers with [reply] (in pieces if [split]). */
    private fun connect(inp: DataInputStream, out: OutputStream, reply: ByteArray, split: Boolean = false): ByteArray {
        val head = inp.bytes(5)
        val rest = inp.bytes(head[4].toInt() + 2)
        if (split) reply.forEach { out.write(byteArrayOf(it)); out.flush(); Thread.sleep(2) } else out.write(reply)
        return head + rest
    }

    private fun httpReply(inp: DataInputStream, out: OutputStream, status: String = "HTTP/1.1 204 No Content") {
        val req = StringBuilder()
        while (!req.endsWith("\r\n\r\n")) req.append(inp.read().toChar())
        out.write("$status\r\nContent-Length: 0\r\n\r\n".toByteArray())
    }

    private val ipv4Ok = byteArrayOf(5, 0, 0, 1, 0, 0, 0, 0, 0, 0)

    private fun probe(user: String = "", password: String = "", timeoutMs: Int = 3000) =
        SocksHttpProbe.check(server.localPort, user, password, target, timeoutMs)

    private fun expectFailure(stage: String, block: () -> Unit): SocksHttpProbe.Failure {
        try {
            block()
        } catch (e: SocksHttpProbe.Failure) {
            assertEquals(stage, e.stage)
            return e
        }
        fail("expected a failure at $stage")
        throw AssertionError()
    }

    @Test
    fun `no-auth session with a 2xx status passes`() {
        val seen = serve { inp, out ->
            val greeting = inp.bytes(3)
            out.write(byteArrayOf(5, 0))
            val req = connect(inp, out, ipv4Ok)
            httpReply(inp, out)
            greeting to req
        }
        probe()
        val (greeting, req) = seen.get(5, TimeUnit.SECONDS)
        assertArrayEquals(byteArrayOf(5, 1, 0), greeting)
        assertArrayEquals(byteArrayOf(5, 1, 0, 3, 12) + "example.test".toByteArray() + byteArrayOf(0, 80), req)
    }

    @Test
    fun `user and password are sent when the server asks for them`() {
        val seen = serve { inp, out ->
            val greeting = inp.bytes(4)
            out.write(byteArrayOf(5, 2))
            val auth = inp.bytes(2 + 4 + 1 + 6)
            out.write(byteArrayOf(1, 0))
            connect(inp, out, ipv4Ok)
            httpReply(inp, out)
            greeting to auth
        }
        probe("user", "secret")
        val (greeting, auth) = seen.get(5, TimeUnit.SECONDS)
        assertArrayEquals(byteArrayOf(5, 2, 0, 2), greeting)
        assertArrayEquals(byteArrayOf(1, 4) + "user".toByteArray() + byteArrayOf(6) + "secret".toByteArray(), auth)
    }

    @Test
    fun `a refused password fails at auth`() {
        serve { inp, out ->
            inp.bytes(4)
            out.write(byteArrayOf(5, 2))
            inp.bytes(2 + 1 + 1 + 1)
            out.write(byteArrayOf(1, 1))
        }
        expectFailure("socks_auth") { probe("u", "p") }
    }

    @Test
    fun `a password demanded without credentials fails at once`() {
        serve { inp, out ->
            inp.bytes(3)
            out.write(byteArrayOf(5, 2))
            // A real server now waits for the auth request: the probe must not wait for its read timeout.
            Thread.sleep(3000)
        }
        val started = System.nanoTime()
        expectFailure("socks_auth") { probe(timeoutMs = 2000) }
        assertTrue(TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started) < 1000)
    }

    @Test
    fun `a refused CONNECT fails at connect with the reply code`() {
        serve { inp, out ->
            inp.bytes(3)
            out.write(byteArrayOf(5, 0))
            connect(inp, out, byteArrayOf(5, 5, 0, 1, 0, 0, 0, 0, 0, 0))
        }
        val e = expectFailure("socks_connect") { probe() }
        assertTrue(e.message!!.contains("5"))
    }

    @Test
    fun `every BND address type is skipped, also when the reply comes in pieces`() {
        val replies = listOf(
            ipv4Ok,
            byteArrayOf(5, 0, 0, 4) + ByteArray(16) + byteArrayOf(0, 0),
            byteArrayOf(5, 0, 0, 3, 4) + "host".toByteArray() + byteArrayOf(0, 80),
        )
        for (reply in replies) {
            val done = serve { inp, out ->
                inp.bytes(3)
                out.write(byteArrayOf(5, 0))
                connect(inp, out, reply, split = true)
                httpReply(inp, out)
            }
            probe()
            done.get(5, TimeUnit.SECONDS)
        }
    }

    @Test
    fun `a non-2xx status fails at the response`() {
        serve { inp, out ->
            inp.bytes(3)
            out.write(byteArrayOf(5, 0))
            connect(inp, out, ipv4Ok)
            httpReply(inp, out, "HTTP/1.1 503 Service Unavailable")
        }
        expectFailure("http_response") { probe() }
    }

    @Test
    fun `EOF in the middle of the CONNECT reply fails at connect`() {
        serve { inp, out ->
            inp.bytes(3)
            out.write(byteArrayOf(5, 0))
            connect(inp, out, byteArrayOf(5, 0, 0, 1, 0, 0))
        }
        expectFailure("socks_connect") { probe() }
    }

    @Test
    fun `nothing listening fails at the TCP connect`() {
        val port = server.localPort
        server.close()
        try {
            SocksHttpProbe.check(port, "", "", target, 1000)
            fail("expected a failure")
        } catch (e: SocksHttpProbe.Failure) {
            assertEquals("tcp_connect", e.stage)
        }
    }

    @Test
    fun `probe URLs parse with scheme defaults and fall back on garbage`() {
        assertEquals(
            SocksHttpProbe.Target("cp.cloudflare.com", 80, "/generate_204", false),
            SocksHttpProbe.parseUrl("http://cp.cloudflare.com/generate_204"),
        )
        assertEquals(SocksHttpProbe.Target("a.test", 443, "/", true), SocksHttpProbe.parseUrl("https://a.test"))
        assertEquals(SocksHttpProbe.Target("a.test", 8080, "/x", false), SocksHttpProbe.parseUrl("http://a.test:8080/x"))
        assertEquals(
            SocksHttpProbe.Target(SocksHttpProbe.DEFAULT_HOST, 80, "/generate_204", false),
            SocksHttpProbe.parseUrl("::not a url"),
        )
    }
}
