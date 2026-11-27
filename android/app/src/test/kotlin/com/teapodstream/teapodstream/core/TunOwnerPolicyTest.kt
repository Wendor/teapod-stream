package com.teapodstream.teapodstream.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The owner check (Tun2SocksCore.buildTunValidator and RustCore.tunAdmission) decides:
 *
 *     if (allowedUids.isEmpty()) -> always true
 *     uid < 0                    -> DNS to tunDns || (vpnMode != ONLY_SELECTED && !blockUnowned)
 *     onlySelected               -> uid in allowedUids
 *     allExcept                  -> uid !in allowedUids
 *
 * with blockUnowned = excludedPackages.isNotEmpty() && !allowTethering. A lookup that
 * threw is decided as uid < 0: refused where ownerless flows are, admitted elsewhere.
 */
class TunOwnerPolicyTest {
    private val own = 10_100
    private val browser = 10_200
    private val excluded = 10_300
    private val other = 10_400
    private val unowned = -1
    private val dns = "1.1.1.1"

    /** The rule above, transcribed literally. */
    private fun go(vpnMode: VpnMode, allowedUids: Set<Int>, blockUnowned: Boolean, uid: Int?): Boolean {
        if (allowedUids.isEmpty()) return true
        if (uid == null || uid < 0) return vpnMode != VpnMode.ONLY_SELECTED && !blockUnowned
        return if (vpnMode == VpnMode.ONLY_SELECTED) uid in allowedUids else uid !in allowedUids
    }

    @Test
    fun matchesGoForEveryModeTetheringAndOwner() {
        val uids = listOf(null, unowned, own, browser, excluded, other)
        for (vpnMode in VpnMode.entries) {
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
        val policy = TunOwnerPolicy.of(VpnMode.ONLY_SELECTED, setOf(browser), emptyList(), allowTethering = true)
        assertTrue(policy.needsAdmission)
        assertTrue(policy.admitFlow(WEB, 443) { browser })
        // Tethering, an unselected app bound to tun0, or an OEM's INVALID_UID for a
        // selected app's bound socket: all dropped, as in Go.
        assertFalse(policy.admitFlow(WEB, 443) { unowned })
        assertFalse(policy.admitFlow(WEB, 443) { other })
        assertEquals(2, policy.denied)
    }

    @Test
    fun allExceptBlocksUnownedOnlyWithExclusionsAndTetheringOff() {
        val strict = TunOwnerPolicy.of(VpnMode.ALL_EXCEPT, setOf(own, excluded), listOf("x"), allowTethering = false)
        assertTrue(strict.needsAdmission)
        assertFalse(strict.admit(unowned))
        assertTrue(strict.admit(browser))
        assertFalse(strict.admit(excluded))

        val tethering = TunOwnerPolicy.of(VpnMode.ALL_EXCEPT, setOf(own, excluded), listOf("x"), allowTethering = true)
        assertTrue(tethering.admit(unowned))
        // Android never reports an excluded UID to this VPN (INVALID_UID instead), so
        // nothing reachable is refused and the core keeps running without the hook.
        assertFalse(tethering.needsAdmission)

        val noExclusions = TunOwnerPolicy.of(VpnMode.ALL_EXCEPT, setOf(own), emptyList(), allowTethering = false)
        assertTrue(noExclusions.admit(unowned))
        assertFalse(noExclusions.needsAdmission)
    }

    @Test
    fun unownedDnsToTunResolverIsAdmittedInEveryMode() {
        // Android 10: netd owns resolver sockets, lookup returns INVALID_UID (issue #155).
        val only = TunOwnerPolicy.of(VpnMode.ONLY_SELECTED, setOf(browser), emptyList(), false, dns)
        assertTrue(only.admitFlow(dns, 53) { unowned })
        assertFalse(only.admitFlow(dns, 443) { unowned })
        assertFalse(only.admitFlow("8.8.8.8", 53) { unowned })
        assertFalse(only.admitFlow(dns, 53) { other })

        val strict = TunOwnerPolicy.of(VpnMode.ALL_EXCEPT, setOf(own, excluded), listOf("x"), false, dns)
        assertTrue(strict.admit(unowned, dns, 53))
        assertFalse(strict.admit(unowned, "8.8.8.8", 53))
    }

    @Test
    fun failedLookupIsRefusedInModesThatFilter() {
        val logged = mutableListOf<String>()
        val only = TunOwnerPolicy(true, setOf(browser), blockUnowned = false, tunDns = dns) { _, m -> logged += m }
        assertTrue(only.needsAdmission)
        assertFalse(only.admitFlow(WEB, 443) { throw SecurityException("not the active VPN") })
        assertFalse(only.admitFlow(WEB, 443) { throw IllegalArgumentException("bad tuple") })
        // The resolver exception still holds when the lookup throws.
        assertTrue(only.admitFlow(dns, 53) { throw SecurityException("not the active VPN") })
        assertFalse(only.admitFlow("8.8.8.8", 53) { throw SecurityException("not the active VPN") })
        assertEquals(3, only.denied)
        assertEquals(3, only.deniedOnLookupError)
        // Logged at the 1st and 2nd refusal, not at the 3rd.
        assertEquals(2, logged.size)
        assertTrue(logged[0].contains("SecurityException"))

        val strict = TunOwnerPolicy.of(VpnMode.ALL_EXCEPT, setOf(own, excluded), listOf("x"), false, dns)
        assertTrue(strict.needsAdmission)
        assertFalse(strict.admitFlow(WEB, 443) { throw SecurityException("not the active VPN") })
        assertTrue(strict.admitFlow(dns, 53) { throw SecurityException("not the active VPN") })
        assertEquals(1, strict.deniedOnLookupError)
    }

    @Test
    fun failedLookupIsAdmittedWhereOwnerlessFlowsAre() {
        for (policy in listOf(
            TunOwnerPolicy.of(VpnMode.ALL_EXCEPT, setOf(own, excluded), listOf("x"), allowTethering = true),
            TunOwnerPolicy.of(VpnMode.ALL_EXCEPT, setOf(own), emptyList(), allowTethering = false),
            TunOwnerPolicy.of(VpnMode.ONLY_SELECTED, emptySet(), emptyList(), allowTethering = false),
        )) {
            assertTrue(policy.admitFlow(WEB, 443) { throw SecurityException("not the active VPN") })
            assertEquals(0, policy.denied)
        }
    }

    @Test
    fun refusalWithAWorkingLookupIsNotCountedAsLookupError() {
        val policy = TunOwnerPolicy.of(VpnMode.ONLY_SELECTED, setOf(browser), emptyList(), allowTethering = false)
        assertFalse(policy.admitFlow(WEB, 443) { other })
        assertEquals(1, policy.denied)
        assertEquals(0, policy.deniedOnLookupError)
    }

    @Test
    fun emptyUidListIsGoAllowAll() {
        val policy = TunOwnerPolicy.of(VpnMode.ONLY_SELECTED, emptySet(), emptyList(), allowTethering = false)
        assertTrue(policy.admit(unowned))
        assertTrue(policy.admit(other))
        assertFalse(policy.needsAdmission)
    }

    private companion object {
        const val WEB = "93.184.216.34"
    }
}
