package com.teapodstream.teapodstream.core

import java.util.concurrent.atomic.AtomicLong

/**
 * GoCore's flow owner rule (TunValidator) as a pure function for xray-rust TUN
 * admission. No Android types — covered by JVM tests.
 * Ported from PR #152 (vivatfreedom).
 *
 * [listedUids] are the allowed UIDs in "ONLY" (own UID removed) and the excluded
 * UIDs plus the app's own in "EXCEPT". A uid below zero is INVALID_UID: a tethered
 * client, or an app the VPN does not apply to that bound its socket to tun0.
 *
 * [tunDns] — the address from addDnsServer(). On Android 10 netd opens DNS sockets
 * under its own name, and the lookup gives INVALID_UID: without an exception for DNS to this address
 * selected apps can't resolve names (issue #155).
 *
 * [log] gets a warning when a failed owner lookup refuses a flow: the first one, then
 * at every power of two, so a lookup that keeps failing doesn't flood the log.
 */
internal class TunOwnerPolicy(
    val onlySelected: Boolean,
    val listedUids: Set<Int>,
    val blockUnowned: Boolean,
    val tunDns: String = "",
    private val log: (level: String, message: String) -> Unit = { _, _ -> },
) {
    private val deniedFlows = AtomicLong()
    private val deniedOnErrorFlows = AtomicLong()

    /** Flows refused since this policy was created; diagnostics only. */
    val denied: Long get() = deniedFlows.get()

    /** Of [denied], the flows refused because the owner lookup threw; diagnostics only. */
    val deniedOnLookupError: Long get() = deniedOnErrorFlows.get()

    /**
     * The decision for one flow. [uid] null means the owner lookup threw: the flow is
     * treated as ownerless (INVALID_UID), so a mode that refuses ownerless flows refuses
     * it too (DNS to [tunDns] aside), and a mode that admits them admits it. An empty
     * UID list gets Go's allow-all validator.
     */
    fun admit(uid: Int?, dstIp: String = "", dstPort: Int = 0): Boolean {
        if (listedUids.isEmpty()) return true
        val owner = uid ?: INVALID_UID
        if (owner < 0) return (dstPort == 53 && dstIp == tunDns) || (!onlySelected && !blockUnowned)
        return if (onlySelected) owner in listedUids else owner !in listedUids
    }

    /** Runs the owner [lookup] for one new flow, as Go's TunValidator.onValidate. */
    fun admitFlow(dstIp: String, dstPort: Int, lookup: () -> Int): Boolean {
        var error: Exception? = null
        val uid = try { lookup() } catch (e: Exception) { error = e; null }
        val admitted = admit(uid, dstIp, dstPort)
        if (admitted) return true
        deniedFlows.incrementAndGet()
        if (error != null) {
            val n = deniedOnErrorFlows.incrementAndGet()
            if (n and (n - 1) == 0L) {
                log("warning", "TUN owner lookup failed, flow refused ($n so far): " +
                    "${error.javaClass.simpleName}: ${error.message}")
            }
        }
        return false
    }

    /**
     * Whether [admit] can refuse a flow that reaches this TUN, so the core needs the
     * hook. Android's getConnectionOwnerUid reports INVALID_UID for every UID the VPN
     * does not apply to (the Go service relies on the same fact), so in "EXCEPT" the
     * listed (excluded) UIDs never come back as such and only [blockUnowned] can deny.
     * Without the hook xray-rust keeps its local ICMP replies, which an enabled policy
     * drops along with other protocols it cannot check.
     */
    val needsAdmission: Boolean
        get() = listedUids.isNotEmpty() && (onlySelected || blockUnowned)

    companion object {
        /** android.os.Process.INVALID_UID, kept here so the class stays free of Android types. */
        private const val INVALID_UID = -1

        fun of(
            vpnMode: String,
            listedUids: Set<Int>,
            excludedPackages: Collection<String>,
            allowTethering: Boolean,
            tunDns: String = "",
        ) = TunOwnerPolicy(
            onlySelected = vpnMode == "onlySelected",
            listedUids = listedUids,
            // Go: exclusions exist and the user did not opt into tethering.
            blockUnowned = excludedPackages.isNotEmpty() && !allowTethering,
            tunDns = tunDns,
        )
    }
}
