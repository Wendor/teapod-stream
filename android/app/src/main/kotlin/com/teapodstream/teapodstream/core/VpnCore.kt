package com.teapodstream.teapodstream.core

import android.content.Context
import android.net.VpnService

enum class CoreKind(val id: String, val versionKey: String) {
    GO("go", "xray-go"), RUST("rust", "xray-rust"), BOX("box", "sing-box");

    companion object {
        fun fromId(id: String?): CoreKind = entries.firstOrNull { it.id == id } ?: GO
    }
}

data class CoreStartParams(
    /** null — proxy-only (no TUN). */
    val tunFd: Int?,
    val mtu: Int,
    val socksPort: Int,
    val socksUser: String,
    val socksPassword: String,
    val allowIcmp: Boolean,
    val blockQuic: Boolean,
    val vpnMode: String,
    /** onlySelected — allowed UIDs, allExcept — excluded ones. */
    val allowedUids: Set<Int>,
    /** allExcept: drop ownerless flows (tethering/bypass via tun0). */
    val blockUnowned: Boolean,
)

/** VPN core: everything [com.teapodstream.teapodstream.XrayVpnService] does with the engine. */
interface VpnCore {
    val kind: CoreKind

    fun init(service: VpnService, log: (level: String, message: String) -> Unit)

    /** Blocks until ready; throws IllegalStateException with the reason. */
    fun start(config: String, params: CoreStartParams)

    /** Stops the core; no longer than ~8 s in total. */
    fun stop()

    fun isTunRunning(): Boolean
    fun activeConnections(): Long
    fun uploadBytes(): Long
    fun downloadBytes(): Long
    fun lastRxActivityMs(): Long
    fun closeAllConnections(): Long
    fun statsLine(): String
    fun diagnostics(): String

    /** XRAYDELAY probe through the running core, ms; < 0 — error. */
    fun measureDelay(url: String): Long

    /** Temporary instance with [config] without TUN: latency to [url], ms; < 0 — error. */
    fun measureOutbound(context: Context, config: String, url: String): Long

    fun version(): String

    /** The core works on the TUN fd directly (no dup): stop() — before the fd is closed. */
    val borrowsTunFd: Boolean get() = false

    /** DNS server the TUN interface gets. */
    val tunDnsServer: String

    /** TUN interface MTU respecting the core's limits. */
    fun tunMtu(requested: Int): Int = requested

    /** Replace the `proxy` outbound's server with 127.0.0.1:<port from [redirect]>; null — not replaced. */
    fun redirectProxyServer(config: String, redirect: (host: String, port: Int) -> Int?): String? =
        ProxyRedirect.xray(config, redirect)

    /** Local SOCKS login/password from the saved config (quick-connect, service restart). */
    fun socksCredentials(config: String): Pair<String, String> = SocksCredentials.xray(config)
}

object VpnCores {
    /** Core of the current (or last) session. */
    @Volatile var active: VpnCore = GoCore

    fun get(kind: CoreKind): VpnCore = when (kind) {
        CoreKind.GO -> GoCore
        CoreKind.RUST -> RustCore
        CoreKind.BOX -> BoxCore
    }

    fun isAvailable(kind: CoreKind): Boolean = try {
        get(kind).version()
        true
    } catch (_: Throwable) {
        false
    }

    fun versions(): Map<String, String> = CoreKind.entries.associate { kind ->
        kind.versionKey to try { get(kind).version() } catch (_: Throwable) { "—" }
    }
}
