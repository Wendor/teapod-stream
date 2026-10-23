package com.teapodstream.teapodstream

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The Rust owner check must decide exactly as the Go service's buildTunValidator:
 *
 *     if (allowedUids.isEmpty()) -> always true
 *     lookup threw               -> true
 *     uid < 0                    -> vpnMode != "onlySelected" && !blockUnowned
 *     onlySelected               -> uid in allowedUids
 *     allExcept                  -> uid !in allowedUids
 *
 * with blockUnowned = excludedPackages.isNotEmpty() && !allowTethering.
 */
class TunOwnerPolicyTest {
    private val own = 10_100
    private val browser = 10_200
    private val excluded = 10_300
    private val other = 10_400
    private val unowned = -1

    /** The Go validator, transcribed literally from the Go service. */
    private fun go(vpnMode: String, allowedUids: Set<Int>, blockUnowned: Boolean, uid: Int?): Boolean {
        if (allowedUids.isEmpty()) return true
        if (uid == null) return true
        if (uid < 0) return vpnMode != "onlySelected" && !blockUnowned
        return if (vpnMode == "onlySelected") uid in allowedUids else uid !in allowedUids
    }

    @Test
    fun matchesGoForEveryModeTetheringAndOwner() {
        val uids = listOf(null, unowned, own, browser, excluded, other)
        for (vpnMode in listOf("allExcept", "onlySelected")) {
            for (exclusions in listOf(emptyList(), listOf("org.example.excluded"))) {
                for (tethering in listOf(false, true)) {
                    for (listed in listOf(emptySet(), setOf(own), setOf(own, excluded), setOf(browser))) {
                        val policy = TunOwnerPolicy.of(vpnMode, listed, exclusions, tethering)
                        val blockUnowned = exclusions.isNotEmpty() && !tethering
                        assertEquals(blockUnowned, policy.blockUnowned)
                        for (uid in uids) {
                            assertEquals(
                                "mode=$vpnMode exclusions=$exclusions tethering=$tethering listed=$listed uid=$uid",
                                go(vpnMode, listed, blockUnowned, uid),
                                policy.admit(uid),
                            )
                        }
                    }
                }
            }
        }
    }

    @Test
    fun onlySelectedDropsUnownedAndUnlistedFlows() {
        val policy = TunOwnerPolicy.of("onlySelected", setOf(browser), emptyList(), allowTethering = true)
        assertTrue(policy.needsAdmission)
        assertTrue(policy.admitFlow { browser })
        // Tethering, an unselected app bound to tun0, or an OEM's INVALID_UID for a
        // selected app's bound socket: all dropped, as in Go.
        assertFalse(policy.admitFlow { unowned })
        assertFalse(policy.admitFlow { other })
        assertEquals(2, policy.denied)
    }

    @Test
    fun allExceptBlocksUnownedOnlyWithExclusionsAndTetheringOff() {
        val strict = TunOwnerPolicy.of("allExcept", setOf(own, excluded), listOf("x"), allowTethering = false)
        assertTrue(strict.needsAdmission)
        assertFalse(strict.admit(unowned))
        assertTrue(strict.admit(browser))
        assertFalse(strict.admit(excluded))

        val tethering = TunOwnerPolicy.of("allExcept", setOf(own, excluded), listOf("x"), allowTethering = true)
        assertTrue(tethering.admit(unowned))
        // Android never reports an excluded UID to this VPN (INVALID_UID instead), so
        // nothing reachable is refused and the core keeps running without the hook.
        assertFalse(tethering.needsAdmission)

        val noExclusions = TunOwnerPolicy.of("allExcept", setOf(own), emptyList(), allowTethering = false)
        assertTrue(noExclusions.admit(unowned))
        assertFalse(noExclusions.needsAdmission)
    }

    @Test
    fun failedLookupAllowsTheFlowLikeGo() {
        val policy = TunOwnerPolicy.of("onlySelected", setOf(browser), emptyList(), allowTethering = false)
        assertTrue(policy.admitFlow { throw SecurityException("not the active VPN") })
        assertTrue(policy.admitFlow { throw IllegalArgumentException("bad tuple") })
        assertEquals(0, policy.denied)
    }

    @Test
    fun emptyUidListIsGoAllowAll() {
        val policy = TunOwnerPolicy.of("onlySelected", emptySet(), emptyList(), allowTethering = false)
        assertTrue(policy.admit(unowned))
        assertTrue(policy.admit(other))
        assertFalse(policy.needsAdmission)
    }

    @Test
    fun heartbeatProbesFollowGo() {
        for (probe in listOf("socks", "xrayDelay", "passive")) {
            assertEquals(probe to null, heartbeatProbeOf(probe))
        }
        assertEquals("socks" to null, heartbeatProbeOf(null))
        assertEquals("socks" to null, heartbeatProbeOf(""))
        val (probe, unknown) = heartbeatProbeOf("icmp")
        assertEquals("socks", probe)
        assertEquals("icmp", unknown)
        assertNull(heartbeatProbeOf("xrayDelay").second)
    }
}
