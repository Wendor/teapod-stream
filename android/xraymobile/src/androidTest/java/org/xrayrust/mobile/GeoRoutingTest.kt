package org.xrayrust.mobile

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket

@RunWith(AndroidJUnit4::class)
class GeoRoutingTest {
    private fun field(number: Int, bytes: ByteArray): ByteArray =
        byteArrayOf(((number shl 3) or 2).toByte(), bytes.size.toByte()) + bytes
    private fun text(number: Int, value: String) = field(number, value.toByteArray())
    private fun directory(): File = File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir,
        "geo-${System.nanoTime()}").apply {
        mkdirs()
        val domain = byteArrayOf(8, 2) + text(2, "routed.test")
        File(this, "geosite.dat").writeBytes(field(1, text(1, "FIXTURE") + field(2, domain)))
        val cidr = field(1, byteArrayOf(127, 0, 0, 1)) + byteArrayOf(16, 32)
        File(this, "geoip.dat").writeBytes(field(1, text(1, "FIXTURE") + field(2, cidr)))
    }

    private fun config(port: Int, rule: String, strategy: String = "AsIs") = """
      {"inbounds":[{"tag":"test-in","protocol":"socks","listen":"127.0.0.1","port":$port}],
       "outbounds":[{"tag":"proxy","protocol":"freedom"},{"tag":"direct","protocol":"freedom"}],
       "dns":{"hosts":{"routed.test":"127.0.0.1","other.test":"127.0.0.1"}},
       "routing":{"domainStrategy":"$strategy","rules":[$rule]}}
    """.trimIndent()

    private fun route(rule: String, destination: String, expected: String, strategy: String = "AsIs") {
        val dir = directory()
        try {
            ServerSocket(0, 4, InetAddress.getByName("127.0.0.1")).use { upstream ->
                upstream.soTimeout = 10000
                val port = ServerSocket(0).use { it.localPort }
                XrayCore.create(config(port, rule, strategy), geodataDirectory = dir).use { core ->
                    core.start()
                    Socket("127.0.0.1", port).use { client ->
                        client.soTimeout = 10000
                        val out = client.getOutputStream()
                        val input = java.io.DataInputStream(client.getInputStream())
                        out.write(byteArrayOf(5, 1, 0))
                        assertEquals(5, input.readUnsignedByte()); assertEquals(0, input.readUnsignedByte())
                        val address = destination.toByteArray()
                        val target = if (destination == "127.0.0.1") byteArrayOf(1, 127, 0, 0, 1)
                            else byteArrayOf(3, address.size.toByte()) + address
                        out.write(byteArrayOf(5, 1, 0) + target + byteArrayOf((upstream.localPort shr 8).toByte(), upstream.localPort.toByte()))
                        assertEquals(5, input.readUnsignedByte()); assertEquals(0, input.readUnsignedByte())
                        upstream.accept().use {
                            val deadline = System.nanoTime() + 2_000_000_000
                            var connections = core.connectionSnapshot().connections
                            while (connections.isEmpty() && System.nanoTime() < deadline) {
                                Thread.sleep(10)
                                connections = core.connectionSnapshot().connections
                            }
                            assertEquals(expected, connections.single { it.inboundTag == "test-in" }.outboundTag)
                        }
                    }
                    core.stop()
                }
            }
        } finally { dir.deleteRecursively() }
    }

    @Test fun geositeMatchSelectsDirect() = route(
        """{"type":"field","domain":["geosite:fixture"],"outboundTag":"direct"}""", "routed.test", "direct")
    @Test fun geositeNonMatchKeepsProxy() = route(
        """{"type":"field","domain":["geosite:fixture"],"outboundTag":"direct"}""", "other.test", "proxy")
    @Test fun geoipMatchSelectsDirect() = route(
        """{"type":"field","ip":["geoip:fixture"],"outboundTag":"direct"}""", "127.0.0.1", "direct")
    @Test fun geoipResolvesDomainBeforeMatching() = route(
        """{"type":"field","ip":["geoip:fixture"],"outboundTag":"direct"}""", "other.test", "direct", "IPIfNonMatch")

    @Test fun bundledUsGeoipAndCloudflareGeositeLoadTogether() {
        val dir = directory()
        try {
            val assets = InstrumentationRegistry.getInstrumentation().context.assets
            for (name in listOf("geoip.dat", "geosite.dat")) {
                assets.open(name).use { input -> File(dir, name).outputStream().use { input.copyTo(it) } }
            }
            val rules = """{"type":"field","ip":["geoip:us","geoip:ru"],"outboundTag":"direct"},
              {"type":"field","domain":["geosite:cloudflare","geosite:youtube"],"outboundTag":"direct"}"""
            XrayCore.create(config(10809, rules), geodataDirectory = dir).use {
                assertEquals(2, it.routingPolicySnapshot().ruleCount)
            }
        } finally { dir.deleteRecursively() }
    }

    @Test fun missingAndCorruptDatabasesFailConfigurationLoad() {
        val dir = directory()
        val conf = config(10809, """{"type":"field","domain":["geosite:fixture"],"outboundTag":"direct"}""")
        try {
            File(dir, "geosite.dat").delete()
            assertThrows(XrayCoreException::class.java) { XrayCore.create(conf, geodataDirectory = dir).close() }
            File(dir, "geosite.dat").writeText("broken protobuf")
            assertThrows(XrayCoreException::class.java) { XrayCore.create(conf, geodataDirectory = dir).close() }
        } finally { dir.deleteRecursively() }
    }
}
