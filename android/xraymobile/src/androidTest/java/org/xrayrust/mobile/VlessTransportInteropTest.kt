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
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketTimeoutException
import java.security.KeyStore
import java.security.cert.CertificateFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket
import javax.net.ssl.TrustManagerFactory

/**
 * Production configs (VLESS, Trojan, VMess, Shadowsocks 2022, Hysteria2, with the
 * app's fragmentation, noise, QUIC and UDP settings) from scripts/test-rust-transports.py
 * against the pinned reference Xray. Every case carries plain and inner-TLS payloads
 * through SOCKS and runs both outbound probes. `udpEcho` cases relay SOCKS UDP;
 * `udpBlocked` cases must drop it; `tunUdp` sends UDP packets through the TUN packet
 * path to the host's echo and to port 443, which the server redirects to the echo.
 */
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
                    if (entry.optBoolean("udpEcho")) {
                        socksUdp(port, fixture.getInt("udpEchoPort"), expectReply = true)
                        Log.i("TeapodVlessInterop", "$name: SOCKS UDP echo passed")
                    }
                    if (entry.optBoolean("udpBlocked")) {
                        socksUdp(port, fixture.getInt("udpEchoPort"), expectReply = false)
                        Log.i("TeapodVlessInterop", "$name: SOCKS UDP dropped as configured")
                    }
                    entry.optJSONObject("tunUdp")?.let { expect ->
                        // Fresh source ports: a dropped UDP tuple stays dropped until idle.
                        tunUdp(core, 40_000 + index * 2, fixture.getInt("udpEchoPort"), expect.getBoolean("echo"))
                        tunUdp(core, 40_001 + index * 2, 443, expect.getBoolean("quic"))
                        Log.i("TeapodVlessInterop", "$name: TUN UDP echo=${expect.getBoolean("echo")} " +
                            "udp443=${expect.getBoolean("quic")} as expected")
                    }
                    // XRAYDELAY: the app probes the proxy leaf of the running core.
                    probeUrl(fixture)?.let { url ->
                        val result = core.probeOutboundUrl(url, 10_000, "proxy")
                        check(result.isReachable) { "in-core probe: ${result.failureKind} ${result.httpStatus ?: ""}" }
                        Log.i("TeapodVlessInterop", "$name: in-core probe ${result.delayMs} ms")
                    }
                    core.stop()
                }
                // switchConfig: a temporary core from the production probe variant
                // (ephemeral loopback SOCKS, proxy leaf only) while none other runs.
                val probe = entry.optString("probe")
                val url = probeUrl(fixture)
                if (probe.isNotEmpty() && url != null) {
                    XrayCore.create(probe).use { candidate ->
                        candidate.start()
                        val result = candidate.probeOutboundUrl(url, 5_000, "proxy")
                        candidate.stop()
                        check(result.isReachable) { "candidate probe: ${result.failureKind} ${result.httpStatus ?: ""}" }
                        Log.i("TeapodVlessInterop", "$name: candidate probe ${result.delayMs} ms")
                    }
                }
                Log.i("TeapodVlessInterop", "$name: plain and inner-TLS payloads verified")
            } catch (error: Throwable) {
                Log.e("TeapodVlessInterop", "$name failed", error)
                failures.add(name + ": " + error.javaClass.simpleName + " " + error.message)
            }
        }
        check(failures.isEmpty()) { failures.joinToString("; ") }
    }

    /** The harness's HTTP 204 endpoint, seen from the reference server on the host. */
    private fun probeUrl(fixture: JSONObject): String? =
        fixture.optInt("probePort").takeIf { it > 0 }?.let { "http://127.0.0.1:$it/generate_204" }

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

    /**
     * SOCKS5 UDP ASSOCIATE; 3000 bytes exceed one 1200-byte QUIC datagram. With
     * [expectReply] false nothing may come back; a refused association also counts.
     */
    private fun socksUdp(port: Int, target: Int, expectReply: Boolean) {
        Socket("127.0.0.1", port).use { control ->
            control.soTimeout = 15000
            val out = control.getOutputStream()
            val input = DataInputStream(control.getInputStream())
            out.write(byteArrayOf(5, 1, 0))
            assertEquals(5, input.readUnsignedByte()); assertEquals(0, input.readUnsignedByte())
            out.write(byteArrayOf(5, 3, 0, 1, 0, 0, 0, 0, 0, 0))
            assertEquals(5, input.readUnsignedByte())
            val status = input.readUnsignedByte()
            if (status != 0 && !expectReply) return
            assertEquals(0, status)
            input.readUnsignedByte()
            val host = when (input.readUnsignedByte()) {
                1 -> InetAddress.getByAddress(ByteArray(4).also { input.readFully(it) })
                4 -> InetAddress.getByAddress(ByteArray(16).also { input.readFully(it) })
                3 -> InetAddress.getByName(String(ByteArray(input.readUnsignedByte()).also { input.readFully(it) }))
                else -> error("Invalid SOCKS address")
            }
            val relay = InetSocketAddress(
                if (host.isAnyLocalAddress) InetAddress.getLoopbackAddress() else host,
                input.readUnsignedShort())
            DatagramSocket().use { udp ->
                udp.soTimeout = if (expectReply) 5000 else 2000
                val header = byteArrayOf(0, 0, 0, 1, 127, 0, 0, 1, (target shr 8).toByte(), target.toByte())
                for (size in if (expectReply) intArrayOf(64, 1000, 3000) else intArrayOf(64)) {
                    val payload = ByteArray(size) { ((it * 31 + size) and 255).toByte() }
                    val datagram = header + payload
                    val buffer = ByteArray(65536)
                    var reply: ByteArray? = null
                    // UDP may lose a datagram; the payload itself must come back intact.
                    for (attempt in 0 until 3) {
                        udp.send(DatagramPacket(datagram, datagram.size, relay))
                        val packet = DatagramPacket(buffer, buffer.size)
                        try {
                            udp.receive(packet)
                        } catch (_: SocketTimeoutException) {
                            continue
                        }
                        reply = buffer.copyOf(packet.length)
                        break
                    }
                    if (!expectReply) {
                        check(reply == null) { "SOCKS UDP was relayed although UDP is off" }
                        return
                    }
                    val received = requireNotNull(reply) { "No UDP reply for $size bytes" }
                    check(received.size > 4 && received[2].toInt() == 0) { "Invalid SOCKS UDP reply" }
                    val offset = when (received[3].toInt()) {
                        1 -> 10
                        4 -> 22
                        3 -> 7 + (received[4].toInt() and 255)
                        else -> error("Invalid SOCKS UDP address")
                    }
                    assertArrayEquals(payload, received.copyOfRange(offset, received.size))
                }
            }
        }
    }

    /**
     * One UDP flow from an app address through the TUN packet path to 127.0.0.1:[target]
     * on the server's host. Blocked flows get no reply within two sends.
     */
    private fun tunUdp(core: XrayCore, sourcePort: Int, target: Int, expectReply: Boolean) {
        val payload = ByteArray(200) { ((it * 13 + target) and 255).toByte() }
        val packet = TunPackets.udp(TunPackets.client, sourcePort, TunPackets.loopback, target, payload)
        var reply: ByteArray? = null
        for (attempt in 0 until if (expectReply) 3 else 2) {
            core.pushPacket(packet)
            reply = TunPackets.await(core, 2_000) { p ->
                TunPackets.parseUdp(p)?.takeIf { it.sourcePort == target && it.destinationPort == sourcePort }?.payload
            }
            if (reply != null) break
        }
        if (expectReply) {
            assertArrayEquals("TUN UDP to port $target", payload, requireNotNull(reply) { "No TUN UDP reply from port $target" })
        } else {
            check(reply == null) { "TUN UDP to port $target was not blocked" }
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
