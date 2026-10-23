package org.xrayrust.mobile

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.SocketTimeoutException
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * TUN flow admission (ABI 1.11) with synthetic app packets through the core's packet
 * I/O: no VpnService, TUN fd or owner lookup. Pins what the Rust service's owner check
 * (TunOwnerPolicy in the app, Go's rule) relies on: the callback sees the app's
 * original tuple; a denial stops UDP before routing and TCP before its outbound opens;
 * an exception escaping the callback denies, so the service catches lookup errors
 * itself to allow them as Go does; a timeout allows only with failOpen; and an
 * installed policy drops local ICMP, so the service installs one only when it can deny.
 */
@RunWith(AndroidJUnit4::class)
class TunAdmissionTest {
    @Test fun udpFlowsFollowTheDecisionWithTheAppTuple() {
        UdpEcho().use { allowed ->
            UdpEcho().use { denied ->
                val flows = ConcurrentLinkedQueue<XrayTunFlow>()
                val policy = XrayTunFlowAdmission { flow ->
                    flows.add(flow)
                    flow.destination.port == allowed.port
                }
                core(XrayTunAdmissionOptions(policy, timeoutMs = 1_000)).use { core ->
                    core.start()
                    assertNotNull("allowed UDP flow", udpRoundTrip(core, 41_000, allowed.port))
                    val flow = flows.first { it.destination.port == allowed.port }
                    assertEquals(17, flow.protocol)
                    assertEquals(InetSocketAddress(InetAddress.getByAddress(TunPackets.client), 41_000), flow.source)
                    assertEquals(InetSocketAddress(InetAddress.getByAddress(TunPackets.loopback), allowed.port), flow.destination)
                    assertNull("denied UDP flow", udpRoundTrip(core, 41_001, denied.port))
                    assertEquals("a denied datagram reached its target", 0, denied.received.get())
                    core.stop()
                }
            }
        }
    }

    @Test fun tcpDenialResetsBeforeTheOutboundOpens() {
        ServerSocket(0, 8, InetAddress.getByAddress(TunPackets.loopback)).use { allowed ->
            ServerSocket(0, 8, InetAddress.getByAddress(TunPackets.loopback)).use { denied ->
                allowed.soTimeout = 5_000
                denied.soTimeout = 1_500
                val flows = ConcurrentLinkedQueue<XrayTunFlow>()
                val policy = XrayTunFlowAdmission { flow ->
                    flows.add(flow)
                    flow.destination.port == allowed.localPort
                }
                core(XrayTunAdmissionOptions(policy, timeoutMs = 1_000)).use { core ->
                    core.start()
                    assertEquals("allowed TCP handshake", false, tcpHandshake(core, 42_000, allowed.localPort))
                    allowed.accept().close()
                    assertEquals(6, flows.first { it.destination.port == allowed.localPort }.protocol)
                    assertEquals("denied TCP must be reset", true, tcpHandshake(core, 42_001, denied.localPort))
                    try {
                        denied.accept().close()
                        error("a denied TCP flow opened its outbound")
                    } catch (_: SocketTimeoutException) {
                    }
                    core.stop()
                }
            }
        }
    }

    @Test fun exceptionsDenyAndTimeoutsAllowOnlyWithFailOpen() {
        UdpEcho().use { throwing ->
            UdpEcho().use { slow ->
                for (failOpen in listOf(true, false)) {
                    val release = CountDownLatch(1)
                    val policy = XrayTunFlowAdmission { flow ->
                        when (flow.destination.port) {
                            throwing.port -> throw IllegalStateException("owner lookup failed")
                            // Answers "deny" only after the core's timeout decided.
                            slow.port -> { release.await(3, TimeUnit.SECONDS); false }
                            else -> true
                        }
                    }
                    core(XrayTunAdmissionOptions(policy, timeoutMs = 200, failOpen = failOpen)).use { core ->
                        core.start()
                        val base = if (failOpen) 43_000 else 43_100
                        assertNull("exception must deny (failOpen=$failOpen)", udpRoundTrip(core, base, throwing.port))
                        val timedOut = udpRoundTrip(core, base + 1, slow.port)
                        release.countDown()
                        if (failOpen) assertNotNull("timeout with failOpen allows", timedOut)
                        else assertNull("timeout without failOpen denies", timedOut)
                        core.stop()
                    }
                }
                assertEquals("a thrown denial reached its target", 0, throwing.received.get())
            }
        }
    }

    @Test fun localIcmpIsAnsweredOnlyWithoutAPolicy() {
        val request = TunPackets.icmpEcho(TunPackets.client, byteArrayOf(1, 1, 1, 1), 0x5445, 1, ByteArray(32) { it.toByte() })
        XrayCore.create(CONFIG).use { core ->
            core.start()
            core.pushPacket(request)
            assertEquals(0x5445 to 1, TunPackets.await(core, 2_000) { TunPackets.parseEchoReply(it) })
            core.stop()
        }
        UdpEcho().use { echo ->
            core(XrayTunAdmissionOptions({ true }, timeoutMs = 1_000)).use { core ->
                core.start()
                core.pushPacket(request)
                assertNull("ICMP under an admission policy", TunPackets.await(core, 1_500) { TunPackets.parseEchoReply(it) })
                // The same core still carries an admitted flow.
                assertNotNull(udpRoundTrip(core, 44_000, echo.port))
                core.stop()
            }
        }
    }

    private fun core(admission: XrayTunAdmissionOptions) = XrayCore.create(CONFIG, tunAdmission = admission)

    /** The echoed payload, or null when nothing came back after two sends. */
    private fun udpRoundTrip(core: XrayCore, sourcePort: Int, target: Int): ByteArray? {
        val payload = ByteArray(300) { ((it * 11 + sourcePort) and 255).toByte() }
        val packet = TunPackets.udp(TunPackets.client, sourcePort, TunPackets.loopback, target, payload)
        repeat(2) {
            core.pushPacket(packet)
            TunPackets.await(core, 1_500) { p ->
                TunPackets.parseUdp(p)?.takeIf { it.sourcePort == target && it.destinationPort == sourcePort }?.payload
            }?.let { reply ->
                assertArrayEquals(payload, reply)
                return reply
            }
        }
        return null
    }

    /**
     * SYN, then ACK of the core's SYN-ACK. Returns true when the core resets the
     * flow (at either step), false when the handshake completed without a reset.
     */
    private fun tcpHandshake(core: XrayCore, sourcePort: Int, target: Int): Boolean {
        val src = TunPackets.client
        val dst = TunPackets.loopback
        val iss = 1_000L
        core.pushPacket(TunPackets.tcp(src, sourcePort, dst, target, iss, 0, TunPackets.SYN))
        val synAck = requireNotNull(TunPackets.await(core, 3_000) { p ->
            TunPackets.parseTcp(p)?.takeIf { it.sourcePort == target && it.destinationPort == sourcePort }
        }) { "no reply to SYN" }
        if (synAck.flags and TunPackets.RST != 0) return true
        assertEquals(TunPackets.SYN or TunPackets.ACK, synAck.flags and (TunPackets.SYN or TunPackets.ACK))
        assertEquals(iss + 1, synAck.ack)
        core.pushPacket(TunPackets.tcp(src, sourcePort, dst, target, iss + 1, (synAck.seq + 1) and 0xffffffffL, TunPackets.ACK))
        val reset = TunPackets.await(core, 3_000) { p ->
            TunPackets.parseTcp(p)?.takeIf {
                it.sourcePort == target && it.destinationPort == sourcePort && it.flags and TunPackets.RST != 0
            }
        }
        return reset != null
    }

    /** Device-loopback UDP echo that counts what reached it. */
    private class UdpEcho : AutoCloseable {
        private val socket = DatagramSocket(0, InetAddress.getByAddress(TunPackets.loopback))
        val port: Int = socket.localPort
        val received = AtomicInteger()

        init {
            Thread {
                val buffer = ByteArray(2048)
                try {
                    while (true) {
                        val packet = DatagramPacket(buffer, buffer.size)
                        socket.receive(packet)
                        received.incrementAndGet()
                        socket.send(DatagramPacket(packet.data, packet.length, packet.socketAddress))
                    }
                } catch (_: Exception) {
                }
            }.apply { isDaemon = true }.start()
        }

        override fun close() = socket.close()
    }

    private companion object {
        const val CONFIG = """{"inbounds":[{"tag":"tun-in","protocol":"tun"}],
            "outbounds":[{"tag":"direct","protocol":"freedom"}]}"""
    }
}
