package com.teapodstream.teapodstream

import com.teapodstream.teapodstream.core.VpnMode
import com.teapodstream.teapodstream.core.CoreKind
import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class QuickConnectStoreTest {
    private val dir: File = Files.createTempDirectory("qc").toFile()
    private val store = QuickConnectStore(dir, TestStoreCipher)
    private val params = ConnectionParams(
        socksPort = 2080, excludedPackages = listOf("a.b"), includedPackages = emptyList(),
        vpnMode = VpnMode.ALL_EXCEPT, ssPrefix = null, proxyOnly = false, showNotification = true,
        killSwitch = true, allowIcmp = false, blockQuic = false, engine = CoreKind.BOX,
    )
    private val fromConfig = { config: String, engine: CoreKind -> "cfg-user($config,${engine.id})" to "cfg-pass" }

    @Test
    fun savedConnectionRoundTripsWithoutTempFiles() {
        store.save("{config}", params)
        assertEquals("{config}", store.config())
        assertEquals(params, store.params())
        assertTrue(dir.listFiles()!!.none { it.name.endsWith(".tmp") })
    }

    @Test
    fun storedFilesHoldNoPlainText() {
        store.save("""{"outbounds":[{"password":"server-secret"}]}""", params, tileName = "Oslo")
        for (name in listOf(QuickConnectStore.CONFIG, QuickConnectStore.PARAMS, QuickConnectStore.TILE_NAME)) {
            val text = String(File(dir, name).readBytes(), Charsets.ISO_8859_1)
            assertFalse(name, text.contains("server-secret") || text.contains("Oslo") || text.contains("socksPort"))
        }
    }

    @Test
    fun aPlainFileOfAnOlderVersionIsReadAndStoredEncrypted() {
        File(dir, QuickConnectStore.CONFIG).writeText("{plain}")
        File(dir, QuickConnectStore.PARAMS).writeText(params.toJson().toString())
        assertEquals("{plain}", store.config())
        assertEquals(params, store.params())
        assertFalse(String(File(dir, QuickConnectStore.CONFIG).readBytes(), Charsets.ISO_8859_1).contains("{plain}"))
        assertEquals("{plain}", QuickConnectStore(dir, TestStoreCipher).config())
    }

    @Test
    fun aFileThatDoesNotDecryptReadsAsNothingSavedAndIsRemoved() {
        store.save("{config}", params)
        TestStoreCipher.rotate() // the key is gone
        try {
            assertNull(store.quickStart(fromConfig))
            assertNull(store.config())
            assertFalse(File(dir, QuickConnectStore.CONFIG).exists())
            assertFalse(File(dir, QuickConnectStore.PARAMS).exists())
            // The next save works with the new key.
            store.save("{new}", params)
            assertEquals("{new}", store.config())
        } finally {
            TestStoreCipher.rotate()
        }
    }

    @Test
    fun aFileSwappedForAnotherOneDoesNotDecrypt() {
        store.save("{config}", params)
        File(dir, QuickConnectStore.PARAMS).copyTo(File(dir, QuickConnectStore.CONFIG), overwrite = true)
        assertNull(store.config())
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
    fun theTileNameIsReplacedWithTheSessionOrKept() {
        store.save("{a}", params, tileName = "Oslo")
        assertEquals("Oslo", store.tileName())
        store.save("{b}", params)
        assertEquals("a reconnect keeps the name", "Oslo", store.tileName())
        store.save("{c}", params, tileName = "")
        assertNull(store.tileName())
    }

    @Test
    fun aLegacyNameIsTakenOnlyByAStoredConfigWithoutAName() {
        store.adoptLegacyTileName("Old")
        assertNull("no config to name", store.tileName())
        store.save("{a}", params, tileName = "")
        store.adoptLegacyTileName(" ")
        assertNull("blank", store.tileName())
        store.adoptLegacyTileName("Old")
        assertEquals("Old", store.tileName())
        store.adoptLegacyTileName("Older")
        assertEquals("the store's own name stays", "Old", store.tileName())
    }

    @Test
    fun aLegacyNameThatCantBeWrittenIsDropped() {
        store.save("{a}", params, tileName = "")
        File(dir, QuickConnectStore.TILE_NAME).mkdir()
        File(dir, "${QuickConnectStore.TILE_NAME}/x").writeText("")
        store.adoptLegacyTileName("Old") // doesn't throw
        assertEquals("{a}", store.config())
    }

    @Test
    fun anInterruptedSaveLeavesNoOldName() {
        store.save("{a}", params, tileName = "Berlin")
        File(dir, QuickConnectStore.PARAMS).delete()
        File(dir, QuickConnectStore.PARAMS).mkdir()
        File(dir, "${QuickConnectStore.PARAMS}/x").writeText("")
        assertTrue(runCatching { store.save("{b}", params, tileName = "Oslo") }.isFailure)
        assertNull(store.tileName())
    }

    @Test
    fun concurrentReplacementsNeverPairOneConfigWithAnothersParams() {
        val go = java.util.concurrent.CountDownLatch(1)
        val writing = java.util.concurrent.atomic.AtomicInteger(2)
        val seen = java.util.concurrent.CountDownLatch(1)
        val writers = (1..2).map { w ->
            Thread {
                // A store of its own per writer, as the activity and the service have.
                val own = QuickConnectStore(dir, TestStoreCipher)
                go.await()
                try {
                    repeat(500) { i ->
                        // The last replacement waits for the reader's first session, so a read always overlaps one.
                        if (i == 499) check(seen.await(10, java.util.concurrent.TimeUnit.SECONDS)) { "no session read" }
                        own.save("c-$w-$i", params.copy(socksPort = w * 1000 + i))
                    }
                } finally {
                    writing.decrementAndGet()
                }
            }
        }
        val mismatches = mutableListOf<String>()
        var checked = 0
        val failures = java.util.Collections.synchronizedList(mutableListOf<Throwable>())
        val reader = Thread {
            val own = QuickConnectStore(dir, TestStoreCipher)
            go.await()
            // Reads for as long as the writers write, so every read overlaps a replacement.
            while (writing.get() > 0) {
                val r = own.quickStart { config, _ -> "from-$config" to "p" } ?: continue
                checked++
                seen.countDown()
                val (w, i) = r.config.removePrefix("c-").split("-").map(String::toInt)
                if (r.socksUser != "from-${r.config}") mismatches += "${r.config}/${r.socksUser}"
                if (r.params.socksPort != w * 1000 + i) mismatches += "${r.config}/port ${r.params.socksPort}"
            }
        }
        (writers + reader).forEach { t -> t.setUncaughtExceptionHandler { _, e -> failures += e }; t.start() }
        go.countDown()
        (writers + reader).forEach { it.join() }
        assertTrue(failures.toString(), failures.isEmpty())
        assertTrue("the reader saw saved sessions", checked > 0)
        assertTrue(mismatches.take(3).toString(), mismatches.isEmpty())
    }

    @Test
    fun aFailedWriteLeavesNoTempFile() {
        // A non-empty directory under the target name: the rename fails.
        File(dir, QuickConnectStore.PARAMS).mkdir()
        File(dir, "${QuickConnectStore.PARAMS}/x").writeText("")
        assertTrue(runCatching { store.save("{config}", params) }.isFailure)
        assertTrue(dir.listFiles()!!.none { it.name.endsWith(".tmp") })
    }

    @Test
    fun paramsThatCantBeWrittenLeaveNothingToQuickStart() {
        store.save("{old}", params)
        File(dir, QuickConnectStore.PARAMS).delete()
        File(dir, QuickConnectStore.PARAMS).mkdir()
        File(dir, "${QuickConnectStore.PARAMS}/x").writeText("")
        assertTrue(runCatching { store.save("{new}", params.copy(engine = CoreKind.GO)) }.isFailure)
        assertNull("the old config doesn't stay with other params", store.config())
        assertNull(store.quickStart(fromConfig))
    }

    @Test
    fun quickStartTakesTheLoginFromTheConfig() {
        store.save("{config}", params)
        assertEquals(
            StartRequest("{config}", params, "cfg-user({config},box)", "cfg-pass", attempt = 0, reconnect = true),
            store.quickStart(fromConfig),
        )
        // The tile's name comes with the config it names, so the session's save writes it back unchanged.
        store.save("{config}", params, tileName = "Oslo")
        assertEquals("Oslo", store.quickStart(fromConfig)!!.configName)
    }

    @Test
    fun theLoginFileOfOlderVersionsIsRemovedAndNotRead() {
        File(dir, QuickConnectStore.LEGACY_CREDENTIALS).writeText("{\"user\":\"old\",\"pass\":\"old\"}")
        store.save("{config}", params)
        assertFalse(File(dir, QuickConnectStore.LEGACY_CREDENTIALS).exists())
        File(dir, QuickConnectStore.LEGACY_CREDENTIALS).writeText("{\"user\":\"old\",\"pass\":\"old\"}")
        assertEquals("cfg-pass", store.quickStart(fromConfig)!!.socksPassword)
        store.clear()
        assertFalse(File(dir, QuickConnectStore.LEGACY_CREDENTIALS).exists())
    }

    @Test
    fun noQuickStartWithoutConfigOrParams() {
        assertNull(store.quickStart(fromConfig))
        store.saveParams(params)
        assertNull("no config", store.quickStart(fromConfig))
        store.clear()
        store.save("{config}", params)
        File(dir, QuickConnectStore.PARAMS).delete()
        assertNull("no params", store.quickStart(fromConfig))
    }

    @Test
    fun clearRemovesTheConnectionButKeepsTheOffFlag() {
        store.save("{config}", params)
        store.setUserOff(true)
        store.clear()
        assertNull(store.config())
        assertNull(store.params())
        assertTrue(store.userOff())
        store.setUserOff(false)
        assertFalse(store.userOff())
    }

    @Test
    fun aSecondSaveReplacesTheFirst() {
        store.save("{one}", params)
        store.save("{two}", params.copy(engine = CoreKind.RUST))
        assertEquals("{two}", store.config())
        assertEquals(CoreKind.RUST, store.params()!!.engine)
    }
}
