package com.teapodstream.teapodstream.core

import java.util.concurrent.atomic.AtomicLong

/**
 * Правило владельца потока GoCore (TunValidator) как чистая функция для TUN
 * admission xray-rust. Без Android-типов — покрыто JVM-тестами.
 * Перенесено из PR #152 (vivatfreedom).
 *
 * [listedUids] are the allowed UIDs in «ТОЛЬКО» (own UID removed) and the excluded
 * UIDs plus the app's own in «КРОМЕ». A uid below zero is INVALID_UID: a tethered
 * client, or an app the VPN does not apply to that bound its socket to tun0.
 *
 * [tunDns] — адрес из addDnsServer(). На Android 10 DNS-сокеты открывает netd от
 * своего имени, и lookup даёт INVALID_UID: без исключения для DNS на этот адрес
 * выбранные приложения не резолвят имена (issue #155).
 */
internal class TunOwnerPolicy(
    val onlySelected: Boolean,
    val listedUids: Set<Int>,
    val blockUnowned: Boolean,
    val tunDns: String = "",
) {
    private val deniedFlows = AtomicLong()

    /** Flows refused since this policy was created; diagnostics only. */
    val denied: Long get() = deniedFlows.get()

    /**
     * Go's decision. [uid] null means the owner lookup threw: Go allows the flow so a
     * broken lookup never cuts connectivity. An empty UID list gets Go's allow-all
     * validator.
     */
    fun admit(uid: Int?, dstIp: String = "", dstPort: Int = 0): Boolean {
        if (listedUids.isEmpty() || uid == null) return true
        if (uid < 0) return (dstPort == 53 && dstIp == tunDns) || (!onlySelected && !blockUnowned)
        return if (onlySelected) uid in listedUids else uid !in listedUids
    }

    /** Runs the owner [lookup] for one new flow, as Go's TunValidator.onValidate. */
    fun admitFlow(dstIp: String, dstPort: Int, lookup: () -> Int): Boolean {
        val uid = try { lookup() } catch (_: Exception) { null }
        return admit(uid, dstIp, dstPort).also { if (!it) deniedFlows.incrementAndGet() }
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
