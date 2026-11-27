package com.teapodstream.teapodstream

import com.teapodstream.teapodstream.core.VpnMode
import kotlin.random.Random

/** An address or a route with its prefix length. */
data class IpPrefix(val address: String, val prefix: Int)

/**
 * What the TUN is built with: pure, so the addresses, routes and app lists are tested on the JVM; [XrayVpnService]
 * passes it to `VpnService.Builder` and calls `establish()`. [onlySelected] — [allowed] lists the apps in the tunnel
 * (none installed: Android puts every app in it), else [disallowed] lists the ones outside; never both, Android refuses
 * a builder that mixes them.
 */
data class TunSpec(
    val session: String,
    val mtu: Int,
    val addresses: List<IpPrefix>,
    val routes: List<IpPrefix>,
    val dnsServer: String,
    val onlySelected: Boolean,
    val allowed: List<String>,
    val disallowed: List<String>,
) {
    companion object {
        /**
         * A random `10.x.x.x/32` (and `fd00:…::1/64` with [ipv6]) for each TUN, IPv4 default route (IPv6 one with
         * [ipv6]). [VpnMode.ONLY_SELECTED] allows [included]; otherwise [excluded] and the app itself ([ownPackage],
         * so its own connections don't loop through the tunnel) are disallowed.
         */
        fun of(
            mtu: Int,
            dnsServer: String,
            ipv6: Boolean,
            vpnMode: VpnMode,
            included: List<String>,
            excluded: List<String>,
            ownPackage: String,
            nowMs: Long,
            random: Random = Random.Default,
        ): TunSpec {
            val ipv4 = "10.${(2..250).random(random)}.${(2..250).random(random)}.${(2..250).random(random)}"
            val addresses = mutableListOf(IpPrefix(ipv4, 32))
            val routes = mutableListOf(IpPrefix("0.0.0.0", 0))
            // Without an IPv6 address Android blocks the family for tunneled apps (no leak): connect() fails instantly
            // and apps fall back to IPv4. With the address, literal-IPv6 destinations (e.g. Telegram DCs) hang when the
            // VPN server has no IPv6 connectivity (#81).
            if (ipv6) {
                fun hex() = (1..65535).random(random).toString(16)
                addresses += IpPrefix("fd00:${hex()}:${hex()}:${hex()}::1", 64)
                routes += IpPrefix("::", 0)
            }
            val onlySelected = vpnMode == VpnMode.ONLY_SELECTED
            return TunSpec(
                session = "Teapod-${nowMs % 10000}",
                mtu = mtu,
                addresses = addresses,
                routes = routes,
                dnsServer = dnsServer,
                onlySelected = onlySelected,
                allowed = if (onlySelected) included else emptyList(),
                disallowed = if (onlySelected) emptyList() else excluded + ownPackage,
            )
        }
    }
}
