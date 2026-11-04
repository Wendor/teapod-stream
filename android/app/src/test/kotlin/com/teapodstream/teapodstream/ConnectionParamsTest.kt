package com.teapodstream.teapodstream

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Test

class ConnectionParamsTest {
    private fun tempDir(): File = Files.createTempDirectory("cp").toFile()

    @Test
    fun legacyMetaWithoutEngineLoadsAsGo() {
        val dir = tempDir()
        File(dir, "last_connection_meta.json").writeText(
            """{"socksPort":10808,"excludedPackages":[],"includedPackages":[],"vpnMode":"allExcept"}"""
        )
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
}
