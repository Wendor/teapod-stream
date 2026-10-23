package com.teapodstream.teapodstream

import java.util.concurrent.atomic.AtomicLong

/**
 * The Go service's per-flow owner rule (buildTunValidator + resolveUids +
 * blockUnowned/allowTethering in android/app/src/go/.../XrayVpnService.kt), as a
 * pure function for xray-rust TUN admission. No Android types, so JVM tests cover it.
 *
 * [listedUids] are the allowed UIDs in «ТОЛЬКО» (own UID removed) and the excluded
 * UIDs plus the app's own in «КРОМЕ». A uid below zero is INVALID_UID: a tethered
 * client, or an app the VPN does not apply to that bound its socket to tun0.
 */
internal class TunOwnerPolicy(
    val onlySelected: Boolean,
    val listedUids: Set<Int>,
    val blockUnowned: Boolean,
) {
    private val deniedFlows = AtomicLong()

    /** Flows refused since this policy was created; diagnostics only. */
    val denied: Long get() = deniedFlows.get()

    /**
     * Go's decision. [uid] null means the owner lookup threw: Go allows the flow so a
     * broken lookup never cuts connectivity. An empty UID list gets Go's allow-all
     * validator.
     */
    fun admit(uid: Int?): Boolean {
        if (listedUids.isEmpty() || uid == null) return true
        if (uid < 0) return !onlySelected && !blockUnowned
        return if (onlySelected) uid in listedUids else uid !in listedUids
    }

    /** Runs the owner [lookup] for one new flow, as Go's TunValidator.onValidate. */
    fun admitFlow(lookup: () -> Int): Boolean {
        val uid = try { lookup() } catch (_: Exception) { null }
        return admit(uid).also { if (!it) deniedFlows.incrementAndGet() }
    }

    /**
     * Whether [admit] can refuse a flow that reaches this TUN, so the core needs the
     * hook. Android's getConnectionOwnerUid reports INVALID_UID for every UID the VPN
     * does not apply to (the Go service relies on the same fact), so in «КРОМЕ» the
     * listed (excluded) UIDs never come back as such and only [blockUnowned] can deny.
     * Without the hook xray-rust keeps its local ICMP replies, which an enabled policy
     * drops along with other protocols it cannot check.
     */
    val needsAdmission: Boolean
        get() = listedUids.isNotEmpty() && (onlySelected || blockUnowned)

    companion object {
        fun of(
            vpnMode: String,
            listedUids: Set<Int>,
            excludedPackages: Collection<String>,
            allowTethering: Boolean,
        ) = TunOwnerPolicy(
            onlySelected = vpnMode == "onlySelected",
            listedUids = listedUids,
            // Go: exclusions exist and the user did not opt into tethering.
            blockUnowned = excludedPackages.isNotEmpty() && !allowTethering,
        )
    }
}

/**
 * Heartbeat probes the Rust service runs: "socks" (HTTP/HTTPS through the local
 * SOCKS5), "xrayDelay" (an in-core request through the proxy leaf) and "passive"
 * (TUN counters only). Returns the probe and the requested value it replaced, if any.
 */
internal fun heartbeatProbeOf(requested: String?): Pair<String, String?> = when (requested) {
    "socks", "xrayDelay", "passive" -> requested to null
    null, "" -> "socks" to null
    else -> "socks" to requested
}
