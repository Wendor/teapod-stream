package com.teapodstream.teapodstream

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ConnectionParamsTest {
    private fun tempDir(): File = Files.createTempDirectory("cp").toFile()

    private fun meta(dir: File, json: String) = File(dir, "last_connection_meta.json").writeText(json)

    private val minimal = """{"socksPort":10808,"excludedPackages":[],"includedPackages":[],"vpnMode":"allExcept"}"""

    @Test
    fun legacyMetaWithoutEngineLoadsAsGo() {
        val dir = tempDir()
        meta(dir, minimal)
        assertEquals("go", ConnectionParams.load(dir)!!.engine)
    }

    @Test
    fun engineSurvivesSaveLoad() {
        val dir = tempDir()
        ConnectionParams(
            socksPort = 1, excludedPackages = emptyList(), includedPackages = emptyList(),
            vpnMode = "allExcept", ssPrefix = null, proxyOnly = false, showNotification = true,
            killSwitch = false, allowIcmp = false, blockQuic = false, engine = "rust",
        ).save(dir) { _, _ -> }
        assertEquals("rust", ConnectionParams.load(dir)!!.engine)
    }

    @Test
    fun everyFieldSurvivesSaveLoad() {
        val dir = tempDir()
        val params = ConnectionParams(
            socksPort = 4321,
            excludedPackages = listOf("a.b", "c.d"),
            includedPackages = listOf("e.f"),
            vpnMode = "onlySelected",
            ssPrefix = "1603",
            proxyOnly = true,
            showNotification = false,
            killSwitch = true,
            allowIcmp = true,
            blockQuic = true,
            ipv6Enabled = true,
            mtu = 1400,
            heartbeatProbe = "passive",
            heartbeatAction = "switchConfig",
            heartbeatThreshold = 7,
            heartbeatUrl = "http://probe/204",
            allowTethering = true,
            engine = "rust",
        )
        params.save(dir) { _, _ -> }
        assertEquals(params, ConnectionParams.load(dir))
    }

    @Test
    fun missingOptionalFieldsGetDefaults() {
        val dir = tempDir()
        meta(dir, minimal)
        val p = ConnectionParams.load(dir)!!
        assertNull(p.ssPrefix)
        assertEquals(true, p.showNotification)
        assertEquals(false, p.killSwitch)
        assertEquals(false, p.allowIcmp)
        assertEquals(1500, p.mtu)
        assertEquals("socks", p.heartbeatProbe)
        assertEquals("reconnect", p.heartbeatAction)
        assertEquals(3, p.heartbeatThreshold)
        assertEquals("http://cp.cloudflare.com/generate_204", p.heartbeatUrl)
    }

    @Test
    fun outOfRangeValuesAreClamped() {
        val dir = tempDir()
        meta(dir, """{"socksPort":1,"excludedPackages":[],"includedPackages":[],"mtu":100,"heartbeatThreshold":50}""")
        val low = ConnectionParams.load(dir)!!
        assertEquals(576, low.mtu)
        assertEquals(10, low.heartbeatThreshold)

        meta(dir, """{"socksPort":1,"excludedPackages":[],"includedPackages":[],"mtu":65000,"heartbeatThreshold":0}""")
        val high = ConnectionParams.load(dir)!!
        assertEquals(9000, high.mtu)
        assertEquals(1, high.heartbeatThreshold)
    }

    @Test
    fun emptyStringsFallBackToDefaults() {
        val dir = tempDir()
        meta(dir, """{"socksPort":1,"excludedPackages":[],"includedPackages":[],"ssPrefix":"","heartbeatUrl":"","engine":""}""")
        val p = ConnectionParams.load(dir)!!
        assertNull(p.ssPrefix)
        assertEquals("http://cp.cloudflare.com/generate_204", p.heartbeatUrl)
        assertEquals("go", p.engine)
    }

    @Test
    fun missingOrCorruptFileGivesNull() {
        val dir = tempDir()
        assertNull(ConnectionParams.load(dir))
        meta(dir, "{not json")
        assertNull(ConnectionParams.load(dir))
        meta(dir, """{"excludedPackages":[],"includedPackages":[]}""")
        assertNull(ConnectionParams.load(dir))
    }

    @Test
    fun saveFailureIsLoggedNotThrown() {
        val missing = File(tempDir(), "no/such/dir")
        val logged = mutableListOf<String>()
        ConnectionParams(
            socksPort = 1, excludedPackages = emptyList(), includedPackages = emptyList(),
            vpnMode = "allExcept", ssPrefix = null, proxyOnly = false, showNotification = true,
            killSwitch = false, allowIcmp = false, blockQuic = false,
        ).save(missing) { level, _ -> logged += level }
        assertEquals(listOf("warning"), logged)
    }
}
