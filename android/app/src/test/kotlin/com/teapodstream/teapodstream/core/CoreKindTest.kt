package com.teapodstream.teapodstream.core

import org.junit.Assert.assertEquals
import org.junit.Test

class CoreKindTest {
    @Test
    fun `fromId resolves box and falls back to go`() {
        assertEquals(CoreKind.BOX, CoreKind.fromId("box"))
        assertEquals(CoreKind.GO, CoreKind.fromId("unknown"))
        assertEquals(CoreKind.GO, CoreKind.fromId(null))
    }

    @Test
    fun `versionKey per core`() {
        assertEquals("xray-go", CoreKind.GO.versionKey)
        assertEquals("xray-rust", CoreKind.RUST.versionKey)
        assertEquals("sing-box", CoreKind.BOX.versionKey)
    }
}
