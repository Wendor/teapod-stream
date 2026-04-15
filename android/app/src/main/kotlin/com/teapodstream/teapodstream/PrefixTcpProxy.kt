package com.teapodstream.teapodstream

import java.io.IOException
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors

/**
 * Local TCP proxy that prepends [prefix] bytes before forwarding traffic to [targetHost]:[targetPort].
 *
 * Used to support Outline Shadowsocks servers that require a custom prefix
 * (e.g. TLS ClientHello mimicry bytes) at the start of each TCP connection.
 *
 * Flow: Xray → 127.0.0.1:[localPort] → [prefix] + [targetHost]:[targetPort]
 */
class PrefixTcpProxy(
    private val targetHost: String,
    private val targetPort: Int,
    private val prefix: ByteArray,
) {
    private val serverSocket = ServerSocket(0) // random available port
    val localPort: Int = serverSocket.localPort

    @Volatile private var running = true
    private val executor = Executors.newCachedThreadPool()

    fun start() {
        executor.submit {
            while (running) {
                try {
                    val client = serverSocket.accept()
                    executor.submit { handleClient(client) }
                } catch (e: IOException) {
                    if (running) {
                        android.util.Log.w("PrefixTcpProxy", "accept error: ${e.message}")
                    }
                    break
                }
            }
        }
    }

    private fun handleClient(client: Socket) {
        val tag = "PrefixProxy"
        try {
            // Read first chunk from Xray before connecting to the real server.
            // This lets us send prefix + first SS bytes in a single write, which is
            // critical for DPI evasion: the first TCP segment must look like a complete
            // TLS ClientHello (prefix) immediately followed by the actual SS stream data.
            val firstBuf = ByteArray(65536)
            val firstN = client.inputStream.read(firstBuf)
            if (firstN <= 0) return

            android.util.Log.i(tag, "connecting to $targetHost:$targetPort (first chunk: $firstN bytes)")
            val server = Socket(targetHost, targetPort)
            android.util.Log.i(tag, "connected, sending ${prefix.size}+$firstN bytes combined")
            try {
                // Single write: prefix + first SS data → one TCP segment
                val combined = ByteArray(prefix.size + firstN)
                prefix.copyInto(combined)
                firstBuf.copyInto(combined, prefix.size, 0, firstN)
                server.outputStream.write(combined)
                server.outputStream.flush()

                val uploadThread = Thread {
                    try {
                        val n = client.inputStream.copyTo(server.outputStream)
                        android.util.Log.i(tag, "upload done: $n bytes")
                    } catch (e: Exception) {
                        android.util.Log.i(tag, "upload error: ${e.message}")
                    } finally {
                        try { server.shutdownOutput() } catch (_: Exception) {}
                    }
                }
                uploadThread.isDaemon = true
                uploadThread.start()

                try {
                    val n = server.inputStream.copyTo(client.outputStream)
                    android.util.Log.i(tag, "download done: $n bytes")
                } catch (e: Exception) {
                    android.util.Log.i(tag, "download error: ${e.message}")
                } finally {
                    try { client.shutdownOutput() } catch (_: Exception) {}
                }

                uploadThread.join(5000)
            } finally {
                try { server.close() } catch (_: Exception) {}
            }
        } catch (e: Exception) {
            android.util.Log.i("PrefixProxy", "handleClient error: ${e.message}")
        } finally {
            try { client.close() } catch (_: Exception) {}
        }
    }

    fun stop() {
        running = false
        try { serverSocket.close() } catch (_: Exception) {}
        executor.shutdownNow()
    }
}
