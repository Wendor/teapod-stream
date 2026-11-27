package com.teapodstream.teapodstream

import com.teapodstream.teapodstream.core.VpnMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

class TunSpecTest {
    private fun spec(
        ipv6: Boolean = false,
        vpnMode: VpnMode = VpnMode.ALL_EXCEPT,
        included: List<String> = listOf("in.app"),
        excluded: List<String> = listOf("out.app"),
        seed: Int = 1,
    ) = TunSpec.of(
        mtu = 1400, dnsServer = "1.1.1.1", ipv6 = ipv6, vpnMode = vpnMode, included = included, excluded = excluded,
        ownPackage = "own.app", nowMs = 1_234_567, random = Random(seed),
    )

    @Test
    fun ipv4OnlyByDefault() {
        val s = spec()
        assertEquals(1, s.addresses.size)
        assertEquals(32, s.addresses[0].prefix)
        assertEquals(listOf(IpPrefix("0.0.0.0", 0)), s.routes)
        assertEquals("Teapod-4567", s.session)
        assertEquals(1400, s.mtu)
        assertEquals("1.1.1.1", s.dnsServer)
    }

    @Test
    fun addressesStayInTheirRanges() {
        repeat(500) { seed ->
            val s = spec(ipv6 = true, seed = seed)
            val octets = s.addresses[0].address.split('.')
            assertEquals("10", octets[0])
            assertTrue(octets.drop(1).all { it.toInt() in 2..250 })
            val v6 = s.addresses[1]
            assertEquals(64, v6.prefix)
            val groups = v6.address.removePrefix("fd00:").removeSuffix("::1").split(':')
            assertEquals(3, groups.size)
            assertTrue(groups.all { it.toInt(16) in 1..65535 })
        }
    }

    @Test
    fun ipv6AddsAnAddressAndADefaultRoute() {
        val s = spec(ipv6 = true)
        assertTrue(s.addresses[1].address.startsWith("fd00:"))
        assertEquals(listOf(IpPrefix("0.0.0.0", 0), IpPrefix("::", 0)), s.routes)
    }

    @Test
    fun eachTunGetsItsOwnAddress() {
        assertTrue(spec(seed = 1).addresses != spec(seed = 2).addresses)
    }

    @Test
    fun onlySelectedAllowsTheIncludedApps() {
        val s = spec(vpnMode = VpnMode.ONLY_SELECTED)
        assertTrue(s.onlySelected)
        assertEquals(listOf("in.app"), s.allowed)
        assertEquals(emptyList<String>(), s.disallowed)
    }

    @Test
    fun otherModesDisallowTheExcludedAppsAndTheAppItself() {
        for (mode in VpnMode.entries - VpnMode.ONLY_SELECTED) {
            val s = spec(vpnMode = mode)
            assertEquals(false, s.onlySelected)
            assertEquals(emptyList<String>(), s.allowed)
            assertEquals(listOf("out.app", "own.app"), s.disallowed)
        }
    }

    @Test
    fun onlySelectedWithNoAppsListsNone() {
        val s = spec(vpnMode = VpnMode.ONLY_SELECTED, included = emptyList())
        assertTrue(s.onlySelected)
        assertEquals(emptyList<String>(), s.allowed)
        assertEquals(emptyList<String>(), s.disallowed)
    }
}
