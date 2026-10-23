package org.xrayrust.mobile

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

/**
 * Local nativeStats change: the counters appended after upstream's 19 reach Kotlin
 * at their header positions, and the TUN payload counters move while a flow is
 * still open — the outbound accounting snapshot adds bytes only when it closes.
 * Packets go through the core's packet I/O, so no VpnService or TUN fd is needed.
 */
@RunWith(AndroidJUnit4::class)
class TunStatsTest {
    private val client = TunPackets.client
    private val loopback = TunPackets.loopback

    @Test
    fun liveTunCountersReachKotlinWhileTheFlowIsOpen() {
        DatagramSocket(0, InetAddress.getByAddress(loopback)).use { echo ->
            Thread {
                val buffer = ByteArray(2048)
                try {
                    while (true) {
                        val packet = DatagramPacket(buffer, buffer.size)
                        echo.receive(packet)
                        echo.send(DatagramPacket(packet.data, packet.length, packet.socketAddress))
                    }
                } catch (_: Exception) {
                }
            }.apply { isDaemon = true }.start()

            XrayCore.create(CONFIG).use { core ->
                core.start()
                val payload = ByteArray(700) { (it * 7).toByte() }
                core.pushPacket(TunPackets.udp(client, 49154, loopback, echo.localPort, payload))
                val echoed = TunPackets.await(core, 5_000) { TunPackets.parseUdp(it)?.payload }
                assertNotNull("no UDP echo through the TUN packet path", echoed)
                assertTrue(payload.contentEquals(echoed))

                val stats = core.stats()
                assertEquals(payload.size.toLong(), stats.udpRemoteWrittenBytes)
                assertEquals(payload.size.toLong(), stats.udpRemoteReadBytes)
                assertTrue(stats.inboundPackets >= 1 && stats.outboundPackets >= 1)
                // Appended fields: constant budget, the open UDP flow, nothing on TCP.
                assertTrue("udpFlowLimit=${stats.udpFlowLimit}", stats.udpFlowLimit > 0)
                assertTrue("activeUdpFlows=${stats.activeUdpFlows}", stats.activeUdpFlows >= 1)
                assertEquals(0L, stats.activeTcpFlows)
                assertEquals(0L, stats.tcpRemoteReadBytes + stats.tcpRemoteWrittenBytes)
                assertEquals(0L, stats.tunFdReadLoopExits + stats.tunFdWriteLoopExits)
                // Why the app reads live TUN counters: the flow is still open.
                val direct = core.outboundAccountingSnapshot().outbounds
                    .firstOrNull { it.outboundTag == "direct" }
                assertEquals(0L, direct?.downlinkBytes ?: 0L)
                core.stop()
            }
        }
    }

    private companion object {
        const val CONFIG = """{"inbounds":[{"tag":"tun-in","protocol":"tun"}],
            "outbounds":[{"tag":"direct","protocol":"freedom"}]}"""
    }
}
