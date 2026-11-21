package com.teapodstream.teapodstream

import java.io.InputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URI

/**
 * Heartbeat probe: a plain-HTTP GET through the core's local SOCKS5 inbound; a 2xx status means the tunnel works.
 * It can't speak TLS — an https URL is measured inside the core by the caller.
 */
internal object SocksHttpProbe {
    const val DEFAULT_HOST = "cp.cloudflare.com"

    data class Target(val host: String, val port: Int, val path: String, val https: Boolean)

    /** A failed probe; [stage] names the step that failed (for the log). */
    class Failure(val stage: String, message: String, cause: Throwable? = null) : Exception(message, cause)

    fun parseUrl(raw: String): Target = try {
        val u = URI(raw)
        val https = u.scheme.equals("https", ignoreCase = true)
        Target(
            host = u.host ?: DEFAULT_HOST,
            port = if (u.port > 0) u.port else if (https) 443 else 80,
            path = if (u.path.isNullOrEmpty()) "/" else u.path,
            https = https,
        )
    } catch (_: Exception) {
        Target(DEFAULT_HOST, 80, "/generate_204", false)
    }

    /** Throws [Failure] unless [target] answers 2xx through the SOCKS5 inbound on 127.0.0.1:[socksPort]. */
    fun check(socksPort: Int, user: String, password: String, target: Target, timeoutMs: Int = 10_000) {
        var stage = "init"
        try {
            Socket().use { socket ->
                socket.soTimeout = timeoutMs
                stage = "tcp_connect"
                socket.connect(InetSocketAddress("127.0.0.1", socksPort), timeoutMs)
                val out = socket.getOutputStream()
                val inp = socket.getInputStream()

                stage = "socks_greeting"
                // Offer user/password only when we have credentials to send.
                out.write(if (user.isEmpty()) byteArrayOf(5, 1, 0) else byteArrayOf(5, 2, 0, 2))
                val resp = ByteArray(2)
                readFully(inp, resp)
                if (resp[0] != 5.toByte()) throw Exception("SOCKS ver mismatch")
                when (resp[1].toInt()) {
                    0 -> {}
                    2 -> {
                        stage = "socks_auth"
                        if (user.isEmpty()) throw Exception("server requires a password, none configured")
                        val u = user.toByteArray()
                        val p = password.toByteArray()
                        out.write(byteArrayOf(1, u.size.toByte()) + u + byteArrayOf(p.size.toByte()) + p)
                        readFully(inp, resp)
                        if (resp[1] != 0.toByte()) throw Exception("SOCKS auth failed")
                    }
                    else -> throw Exception("SOCKS auth not supported")
                }

                stage = "socks_connect"
                val host = target.host.toByteArray()
                out.write(
                    byteArrayOf(5, 1, 0, 3, host.size.toByte()) + host +
                        byteArrayOf((target.port shr 8).toByte(), target.port.toByte())
                )
                val reply = ByteArray(4)
                readFully(inp, reply)
                val rep = reply[1].toInt() and 0xFF
                if (reply[0].toInt() != 5 || rep != 0) throw Exception("SOCKS connect failed: $rep")
                // BND.ADDR + BND.PORT
                val bndLen = when (reply[3].toInt()) {
                    1 -> 6
                    4 -> 18
                    3 -> inp.read().also { if (it < 0) throw Exception("EOF while reading SOCKS response") } + 2
                    else -> 0
                }
                readFully(inp, ByteArray(bndLen))

                stage = "http_request"
                out.write("GET ${target.path} HTTP/1.1\r\nHost: ${target.host}\r\nConnection: close\r\n\r\n".toByteArray())
                out.flush()

                stage = "http_response"
                val line = inp.bufferedReader().readLine()
                val code = line?.split(" ")?.getOrNull(1)?.toIntOrNull()
                if (code == null || code !in 200..299) throw Exception("Invalid HTTP response: $line")
            }
        } catch (e: Failure) {
            throw e
        } catch (e: Exception) {
            throw Failure(stage, e.message ?: e.javaClass.simpleName, e)
        }
    }

    // InputStream.read may return fewer bytes than requested — a split SOCKS reply is not a failure.
    private fun readFully(inp: InputStream, buf: ByteArray) {
        var off = 0
        while (off < buf.size) {
            val n = inp.read(buf, off, buf.size - off)
            if (n < 0) throw Exception("EOF while reading SOCKS response")
            off += n
        }
    }
}
