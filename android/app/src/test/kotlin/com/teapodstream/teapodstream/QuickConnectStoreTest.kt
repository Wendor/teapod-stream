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
    fun tileNameIsSavedRemovedByABlankOneAndCleared() {
        store.saveTileName("Oslo")
        assertEquals("Oslo", store.tileName())
        store.saveTileName(" ")
        assertNull(store.tileName())
        store.saveTileName("Oslo")
        store.clear()
        assertNull(store.tileName())
    }

    @Test
    fun aLoginThatCantBeRemovedFailsTheClear() {
        store.save("{config}", params, "u", "p")
        dir.setWritable(false)
        try {
            assertTrue(runCatching { store.clearCredentials() }.isFailure)
        } finally {
            dir.setWritable(true)
        }
        store.clearCredentials()
        assertNull(store.credentials())
    }

    @Test
    fun aLoginThatCantBeRemovedKeepsTheOldConfig() {
        store.save("{old}", params, "old-u", "old-p")
        // A non-empty directory under the login's name: it can't be removed, so the config isn't replaced.
        store.clearCredentials()
        File(dir, QuickConnectStore.CREDENTIALS).mkdir()
        File(dir, "${QuickConnectStore.CREDENTIALS}/x").writeText("")
        assertTrue(runCatching { store.save("{new}", params.copy(engine = "go"), "u", "p") }.isFailure)
        assertEquals("{old}", store.config())
        assertEquals("the params stay with the config", params, store.params())
    }

    @Test
    fun concurrentReplacementsNeverPairOneConfigWithAnothersParamsOrLogin() {
        val writers = (1..2).map { w ->
            Thread {
                // A store of its own per writer, as the activity and the service have.
                val own = QuickConnectStore(dir)
                repeat(300) { i -> own.save("c-$w-$i", params.copy(socksPort = w * 1000 + i), "u-$w-$i", "p") }
            }
        }
        val mismatches = mutableListOf<String>()
        val failures = java.util.Collections.synchronizedList(mutableListOf<Throwable>())
        val reader = Thread {
            val own = QuickConnectStore(dir)
            repeat(600) {
                val r = own.quickStart { config, _ -> "from-$config" to "p" } ?: return@repeat
                val (w, i) = r.config.removePrefix("c-").split("-").map(String::toInt)
                if (r.socksUser != "u-$w-$i" && r.socksUser != "from-${r.config}") mismatches += "${r.config}/${r.socksUser}"
                if (r.params.socksPort != w * 1000 + i) mismatches += "${r.config}/port ${r.params.socksPort}"
            }
        }
        (writers + reader).forEach { t -> t.setUncaughtExceptionHandler { _, e -> failures += e }; t.start() }
        (writers + reader).forEach { it.join() }
        assertTrue(failures.toString(), failures.isEmpty())
        assertTrue(mismatches.take(3).toString(), mismatches.isEmpty())
    }

    @Test
    fun aFailedWriteLeavesNoTempFile() {
        // A non-empty directory under the target name: the rename fails.
        File(dir, QuickConnectStore.PARAMS).mkdir()
        File(dir, "${QuickConnectStore.PARAMS}/x").writeText("")
        assertTrue(runCatching { store.save("{config}", params, "u", "p") }.isFailure)
        assertTrue(dir.listFiles()!!.none { it.name.endsWith(".tmp") })
    }

    @Test
    fun paramsThatCantBeWrittenLeaveNothingToQuickStart() {
        store.save("{old}", params, "old-u", "old-p")
        File(dir, QuickConnectStore.PARAMS).delete()
        File(dir, QuickConnectStore.PARAMS).mkdir()
        File(dir, "${QuickConnectStore.PARAMS}/x").writeText("")
        assertTrue(runCatching { store.save("{new}", params.copy(engine = "go"), "u", "p") }.isFailure)
        assertNull("the old config doesn't stay with other params", store.config())
        assertNull(store.quickStart(fromConfig))
    }

    @Test
    fun quickStartPrefersTheStoredLogin() {
        store.save("{config}", params, "u", "p")
        assertEquals(StartRequest("{config}", params, "u", "p", attempt = 0, reconnect = true), store.quickStart(fromConfig))
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
        store.save("{config}", params, "u", "p")
        File(dir, QuickConnectStore.PARAMS).delete()
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
