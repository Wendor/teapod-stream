package com.teapodstream.teapodstream

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class QuickConnectStoreTest {
    private val dir: File = Files.createTempDirectory("qc").toFile()
    private val store = QuickConnectStore(dir)
    private val params = ConnectionParams(
        socksPort = 2080, excludedPackages = listOf("a.b"), includedPackages = emptyList(),
        vpnMode = "allExcept", ssPrefix = null, proxyOnly = false, showNotification = true,
        killSwitch = true, allowIcmp = false, blockQuic = false, engine = "box",
    )
    private val fromConfig = { config: String, engine: String -> "cfg-user($config,$engine)" to "cfg-pass" }

    @Test
    fun savedConnectionRoundTripsWithoutTempFiles() {
        store.save("{config}", params, "u", "p")
        assertEquals("{config}", store.config())
        assertEquals(params, store.params())
        assertEquals("u" to "p", store.credentials())
        assertTrue(dir.listFiles()!!.none { it.name.endsWith(".tmp") })
    }

    @Test
    fun quickStartPrefersTheStoredLogin() {
        store.save("{config}", params, "u", "p")
        assertEquals(StartRequest("{config}", params, "u", "p", reconnect = true), store.quickStart(fromConfig))
    }

    @Test
    fun withoutAStoredLoginTheConfigsOneIsUsed() {
        store.save("{config}", params, "u", "p")
        store.clearCredentials()
        val request = store.quickStart(fromConfig)!!
        assertEquals("cfg-user({config},box)" to "cfg-pass", request.socksUser to request.socksPassword)
    }

    @Test
    fun aBrokenLoginFileFallsBackToTheConfig() {
        store.save("{config}", params, "u", "p")
        File(dir, QuickConnectStore.CREDENTIALS).writeText("{not json")
        assertNull(store.credentials())
        assertEquals("cfg-pass", store.quickStart(fromConfig)!!.socksPassword)
    }

    @Test
    fun aLoginWithMissingFieldsFallsBackToTheConfig() {
        store.save("{config}", params, "u", "p")
        for (json in listOf("{}", "{\"user\":\"u\"}", "{\"user\":\"u\",\"pass\":1}")) {
            File(dir, QuickConnectStore.CREDENTIALS).writeText(json)
            assertNull(json, store.credentials())
        }
        File(dir, QuickConnectStore.CREDENTIALS).writeText("{\"user\":\"\",\"pass\":\"\"}")
        assertEquals("empty strings are kept", "" to "", store.credentials())
    }

    @Test
    fun noQuickStartWithoutConfigOrParams() {
        assertNull(store.quickStart(fromConfig))
        store.saveParams(params)
        assertNull("no config", store.quickStart(fromConfig))
        store.clear()
        store.saveConfig("{config}")
        assertNull("no params", store.quickStart(fromConfig))
    }

    @Test
    fun clearRemovesTheConnectionButKeepsTheOffFlag() {
        store.save("{config}", params, "u", "p")
        store.setUserOff(true)
        store.clear()
        assertNull(store.config())
        assertNull(store.params())
        assertNull(store.credentials())
        assertTrue(store.userOff())
        store.setUserOff(false)
        assertFalse(store.userOff())
    }

    @Test
    fun aSecondSaveReplacesTheFirst() {
        store.save("{one}", params, "u1", "p1")
        store.save("{two}", params.copy(engine = "rust"), "u2", "p2")
        assertEquals("{two}", store.config())
        assertEquals("rust", store.params()!!.engine)
        assertEquals("u2" to "p2", store.credentials())
    }
}
