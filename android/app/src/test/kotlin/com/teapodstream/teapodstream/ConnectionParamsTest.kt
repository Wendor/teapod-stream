package com.teapodstream.teapodstream

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class ConnectionParamsTest {
    private fun tempDir(): File = Files.createTempDirectory("cp").toFile()

    private fun meta(dir: File, json: String) = File(dir, "last_connection_meta.json").writeText(json)

    private val minimal = """{"socksPort":10808,"excludedPackages":[],"includedPackages":[],"vpnMode":"allExcept"}"""

    @Test
    fun legacyMetaWithoutEngineLoadsAsGo() {
        val dir = tempDir()
        meta(dir, minimal)
        assertEquals("go", QuickConnectStore(dir).params()!!.engine)
    }

    @Test
    fun engineSurvivesSaveLoad() {
        val dir = tempDir()
        QuickConnectStore(dir).saveParams(ConnectionParams(
            socksPort = 1, excludedPackages = emptyList(), includedPackages = emptyList(),
            vpnMode = "allExcept", ssPrefix = null, proxyOnly = false, showNotification = true,
            killSwitch = false, allowIcmp = false, blockQuic = false, engine = "rust",
        ))
        assertEquals("rust", QuickConnectStore(dir).params()!!.engine)
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
        QuickConnectStore(dir).saveParams(params)
        assertEquals(params, QuickConnectStore(dir).params())
    }

    @Test
    fun missingOptionalFieldsGetDefaults() {
        val dir = tempDir()
        meta(dir, minimal)
        val p = QuickConnectStore(dir).params()!!
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
        val low = QuickConnectStore(dir).params()!!
        assertEquals(576, low.mtu)
        assertEquals(10, low.heartbeatThreshold)

        meta(dir, """{"socksPort":1,"excludedPackages":[],"includedPackages":[],"mtu":65000,"heartbeatThreshold":0}""")
        val high = QuickConnectStore(dir).params()!!
        assertEquals(9000, high.mtu)
        assertEquals(1, high.heartbeatThreshold)
    }

    @Test
    fun emptyStringsFallBackToDefaults() {
        val dir = tempDir()
        meta(dir, """{"socksPort":1,"excludedPackages":[],"includedPackages":[],"ssPrefix":"","heartbeatUrl":"","engine":""}""")
        val p = QuickConnectStore(dir).params()!!
        assertNull(p.ssPrefix)
        assertEquals("http://cp.cloudflare.com/generate_204", p.heartbeatUrl)
        assertEquals("go", p.engine)
    }

    @Test
    fun missingOrCorruptFileGivesNull() {
        val dir = tempDir()
        assertNull(QuickConnectStore(dir).params())
        meta(dir, "{not json")
        assertNull(QuickConnectStore(dir).params())
        meta(dir, """{"excludedPackages":[],"includedPackages":[]}""")
        assertNull(QuickConnectStore(dir).params())
    }

    @Test
    fun saveFailureThrowsForTheCallerToLog() {
        val missing = File(tempDir(), "no/such/dir")
        val params = ConnectionParams(
            socksPort = 1, excludedPackages = emptyList(), includedPackages = emptyList(),
            vpnMode = "allExcept", ssPrefix = null, proxyOnly = false, showNotification = true,
            killSwitch = false, allowIcmp = false, blockQuic = false,
        )
        assertThrows(java.io.IOException::class.java) { QuickConnectStore(missing).saveParams(params) }
    }

    private val full = ConnectionParams(
        socksPort = 4321, excludedPackages = listOf("a.b"), includedPackages = listOf("c.d"),
        vpnMode = "onlySelected", ssPrefix = "1603", proxyOnly = true, showNotification = false,
        killSwitch = true, allowIcmp = true, blockQuic = true, ipv6Enabled = true, mtu = 1400,
        heartbeatProbe = "xrayDelay", heartbeatAction = "switchConfig", heartbeatThreshold = 5,
        heartbeatUrl = "http://probe/204", allowTethering = true, engine = "box",
    )

    /** The arguments `XrayEngine` sends for [full], with the secrets the params must leave out. */
    private val fullArgs = mapOf(
        "xrayConfig" to "{}", "socksUser" to "u", "socksPassword" to "secret", "configName" to "n",
        "socksPort" to 4321, "excludedPackages" to listOf("a.b"), "includedPackages" to listOf("c.d"),
        "vpnMode" to "onlySelected", "ssPrefix" to "1603", "proxyOnly" to true, "showNotification" to false,
        "killSwitch" to true, "allowIcmp" to true, "blockQuic" to true, "ipv6Enabled" to true, "mtu" to 1400,
        "heartbeatProbe" to "xrayDelay", "heartbeatAction" to "switchConfig", "heartbeatThreshold" to 5,
        "heartbeatUrl" to "http://probe/204", "allowTethering" to true, "engine" to "box",
    )

    @Test
    fun flutterArgumentsMapEveryFieldAndLeaveSecretsOut() {
        val p = ConnectionParams.fromArgs(fullArgs)
        assertEquals(full, p)
        val json = p.toJson().toString()
        for (secret in listOf("xrayConfig", "socksUser", "socksPassword", "secret")) {
            assertEquals(false, json.contains(secret))
        }
    }

    @Test
    fun intentJsonRoundTripKeepsEveryField() {
        assertEquals(full, ConnectionParams.fromJson(org.json.JSONObject(full.toJson().toString())))
    }

    @Test
    fun missingArgumentsGetTheSameDefaultsAsTheFile() {
        val dir = tempDir()
        meta(dir, minimal)
        assertEquals(QuickConnectStore(dir).params(), ConnectionParams.fromArgs(emptyMap<String, Any?>()))
        val nulls = mapOf("ssPrefix" to null, "heartbeatUrl" to "", "engine" to null)
        assertEquals(QuickConnectStore(dir).params(), ConnectionParams.fromArgs(nulls))
    }

    @Test
    fun flutterArgumentsAreClampedLikeTheFile() {
        val low = ConnectionParams.fromArgs(mapOf("mtu" to 100, "heartbeatThreshold" to 50))
        assertEquals(576, low.mtu)
        assertEquals(10, low.heartbeatThreshold)
        val high = ConnectionParams.fromArgs(mapOf("mtu" to 65000, "heartbeatThreshold" to 0))
        assertEquals(9000, high.mtu)
        assertEquals(1, high.heartbeatThreshold)
    }
}
