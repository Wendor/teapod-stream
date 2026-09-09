package org.xrayrust.mobile

import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.DataInputStream
import java.io.File
import java.net.ServerSocket
import java.net.Socket
import java.security.KeyStore
import java.security.cert.CertificateFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket
import javax.net.ssl.TrustManagerFactory

@RunWith(AndroidJUnit4::class)
class VlessTransportInteropTest {
    @Test fun productionProfilesExchangeDataWithReferenceXray() {
        val path = InstrumentationRegistry.getArguments().getString("interopConfig")
        assumeTrue("Run scripts/test-rust-transports.py to start the local reference server", path != null)
        val fixture = JSONObject(File(requireNotNull(path)).readText())
        val trust = KeyStore.getInstance(KeyStore.getDefaultType()).apply {
            load(null)
            val cert = CertificateFactory.getInstance("X.509").generateCertificate(
                fixture.getString("certificatePem").byteInputStream())
            setCertificateEntry("local-test", cert)
        }
        val trustManager = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()).apply { init(trust) }
        val ssl = SSLContext.getInstance("TLS").apply { init(null, trustManager.trustManagers, null) }
        val cases = fixture.getJSONArray("cases")
        val failures = mutableListOf<String>()
        for (index in 0 until cases.length()) {
            val entry = cases.getJSONObject(index)
            val name = entry.getString("name")
            val config = JSONObject(entry.getString("config"))
            val inbounds = config.getJSONArray("inbounds")
            val port = ServerSocket(0).use { it.localPort }
            for (i in 0 until inbounds.length()) {
                val inbound = inbounds.getJSONObject(i)
                if (inbound.getString("protocol") == "socks") inbound.put("port", port)
            }
            try {
                XrayCore.create(config.toString()).use { core ->
                    core.start()
                    socks(port, fixture.getInt("echoPort")).use { echo(it) }
                    Log.i("TeapodVlessInterop", "$name: plain echo passed")
                    // Inner TLS exercises Vision's transition as well as its
                    // initial framing. Only the generated test CA is trusted.
                    socks(port, fixture.getInt("tlsEchoPort")).use { tunnel ->
                        (ssl.socketFactory.createSocket(tunnel, "cover.example", fixture.getInt("tlsEchoPort"), true) as SSLSocket).use {
                            it.soTimeout = 15000
                            it.sslParameters = it.sslParameters.apply { endpointIdentificationAlgorithm = "HTTPS" }
                            it.startHandshake()
                            Log.i("TeapodVlessInterop", "$name: inner TLS handshake passed")
                            echo(it)
                        }
                    }
                    core.stop()
                }
                Log.i("TeapodVlessInterop", "$name: plain and inner-TLS payloads verified")
            } catch (error: Throwable) {
                Log.e("TeapodVlessInterop", "$name failed", error)
                failures.add(name + ": " + error.javaClass.simpleName)
            }
        }
        check(failures.isEmpty()) { failures.joinToString("; ") }
    }

    private fun socks(port: Int, target: Int): Socket {
        val client = Socket("127.0.0.1", port)
        try {
            client.soTimeout = 15000
            val out = client.getOutputStream()
            val input = DataInputStream(client.getInputStream())
            out.write(byteArrayOf(5, 1, 0))
            assertEquals(5, input.readUnsignedByte()); assertEquals(0, input.readUnsignedByte())
            out.write(byteArrayOf(5, 1, 0, 1, 127, 0, 0, 1, (target shr 8).toByte(), target.toByte()))
            assertEquals(5, input.readUnsignedByte()); assertEquals(0, input.readUnsignedByte())
            input.readUnsignedByte()
            val bytes = when (input.readUnsignedByte()) { 1 -> 4; 4 -> 16; 3 -> input.readUnsignedByte(); else -> error("Invalid SOCKS address") }
            input.readFully(ByteArray(bytes + 2))
            return client
        } catch (error: Throwable) {
            client.close()
            throw error
        }
    }

    private fun echo(socket: Socket) {
        val input = DataInputStream(socket.getInputStream())
        val out = socket.getOutputStream()
        repeat(4) { round ->
            val payload = ByteArray(32 * 1024) { ((it * 37 + round) and 255).toByte() }
            out.write(payload); out.flush()
            val received = ByteArray(payload.size)
            input.readFully(received)
            assertArrayEquals(payload, received)
        }
    }
}
