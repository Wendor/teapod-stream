package com.teapodstream.teapodstream

import com.teapodstream.teapodstream.core.CoreKind
import java.util.Locale
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
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
    fun coreKindFromIdDefaultsToGo() {
        assertEquals(CoreKind.GO, CoreKind.fromId("go"))
        assertEquals(CoreKind.RUST, CoreKind.fromId("rust"))
        assertEquals(CoreKind.GO, CoreKind.fromId(null))
        assertEquals(CoreKind.GO, CoreKind.fromId("zig"))
    }

    @Test
    fun pingableAddressIsHostnameOrIpLiteral() {
        listOf(
            "example.com", "a-b.example.com.", "_srv.test", "1.2.3.4", "::1", "2001:db8::1", "::ffff:1.2.3.4",
            "fe80::1%wlan0",
        ).forEach { assertTrue(it, isPingableAddress(it)) }
        val label64 = "a".repeat(64)
        listOf(
            "", "-f", "-c 100 x", "--help", "a b", "a;b", "-1.2.3.4", "a.-b", "fe80::1%", "fe80::1%a b", "a\nb",
            "example.com\n", "$label64.com",
        ).forEach { assertFalse(it, isPingableAddress(it)) }
    }
}
