package com.teapodstream.teapodstream

import com.teapodstream.teapodstream.core.CoreKind
import java.util.Locale
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

class VpnServiceUtilsTest {
    private val savedLocale = Locale.getDefault()

    @Before
    fun fixLocale() = Locale.setDefault(Locale.ROOT)

    @After
    fun restoreLocale() = Locale.setDefault(savedLocale)

    @Test
    fun formatSpeedPicksUnit() {
        assertEquals("0 B/s", formatSpeed(0))
        assertEquals("999 B/s", formatSpeed(999))
        assertEquals("1 KB/s", formatSpeed(1_000))
        assertEquals("500 KB/s", formatSpeed(499_600))
        assertEquals("1.0 MB/s", formatSpeed(1_000_000))
        assertEquals("12.3 MB/s", formatSpeed(12_345_678))
    }

    @Test
    fun subnetMaskToPrefixCountsBits() {
        assertEquals(0, subnetMaskToPrefix("0.0.0.0"))
        assertEquals(8, subnetMaskToPrefix("255.0.0.0"))
        assertEquals(24, subnetMaskToPrefix("255.255.255.0"))
        assertEquals(30, subnetMaskToPrefix("255.255.255.252"))
        assertEquals(32, subnetMaskToPrefix("255.255.255.255"))
    }

    @Test
    fun coreKindFromIdDefaultsToGo() {
        assertEquals(CoreKind.GO, CoreKind.fromId("go"))
        assertEquals(CoreKind.RUST, CoreKind.fromId("rust"))
        assertEquals(CoreKind.GO, CoreKind.fromId(null))
        assertEquals(CoreKind.GO, CoreKind.fromId("zig"))
    }
}
