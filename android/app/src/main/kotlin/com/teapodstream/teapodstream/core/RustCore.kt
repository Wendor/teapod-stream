package com.teapodstream.teapodstream.core

import android.content.Context
import android.net.ConnectivityManager
import android.net.InetAddresses
import android.net.Network
import android.net.NetworkCapabilities
import android.net.VpnService
import java.net.URI
import java.util.concurrent.ExecutorService
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.Semaphore
import java.util.concurrent.SynchronousQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import org.json.JSONArray
import org.json.JSONObject
import org.xrayrust.mobile.XrayCore
import org.xrayrust.mobile.XrayCoreException
import org.xrayrust.mobile.XrayDnsBootstrapMode
import org.xrayrust.mobile.XrayHysteriaStreamLimits
import org.xrayrust.mobile.XrayTunAdmissionOptions
import org.xrayrust.mobile.XrayTunFileDescriptor
import org.xrayrust.mobile.XrayTunFlowAdmission
import org.xrayrust.mobile.XrayTunInterface
import org.xrayrust.mobile.XrayTunRuntimeProfile
import org.xrayrust.mobile.XrayTunStats

/**
 * xray-rust: reads the TUN fd itself (own network stack), UID filter — TUN admission.
 * Based on RustCore from PR #152 (vivatfreedom).
 */
object RustCore : VpnCore {
    override val kind = CoreKind.RUST
    override val tunDnsServer: String = XrayTunInterface.DNS_ANCHOR
    override val borrowsTunFd = true

    /** The core drops packets longer than its MTU. */
    override fun tunMtu(requested: Int): Int = XrayTunInterface.MTU

    /** xray-rust-mobile version in teapod-core (XRAY_RUST_VERSION in build.sh). */
    private const val XRAY_RUST_VERSION = "0.10.0"
    private const val RESOLVE_TIMEOUT_SECONDS = 5L
    private const val PROXY_TAG = "proxy"
    private val PROXY_PROTOCOLS = setOf("vless", "vmess", "trojan", "shadowsocks", "hysteria")
    /** Hysteria outbound limits: 256 TCP — the TUN Mobile profile ceiling, 128 UDP — the API maximum. */
    private val HYSTERIA_STREAM_LIMITS = XrayHysteriaStreamLimits(maxTcpStreams = 256, maxUdpSessions = 128)
    private const val HEARTBEAT_PROBE_TIMEOUT_MS = 10_000L
    private const val CANDIDATE_PROBE_TIMEOUT_MS = 5_000L
    private const val CANDIDATE_SLOT_WAIT_MS = 20_000L
    private const val DEFAULT_PROBE_URL = "http://cp.cloudflare.com/generate_204"
    /** XrayStatus INVALID_ARGUMENT (xray_ffi.h). */
    private const val XRAY_STATUS_INVALID_ARGUMENT = 9
    private const val TUN_ADMISSION_TIMEOUT_MS = 5_000
    private const val STOP_TIMEOUT_MS = 5_000L

    private var log: (String, String) -> Unit = { _, _ -> }
    private var service: VpnService? = null
    private var core: XrayCore? = null
    private var proxyTag: String? = null
    private var lastRxBytes = 0L
    private var lastRxAt = 0L
    private var lastTcpTxBytes = 0L
    private var lastTcpTxAt = 0L

    /** Temporary candidate cores live next to the VPN core — at most two. */
    private val candidateSlots = Semaphore(2, true)
    private val resolver = ThreadPoolExecutor(0, 2, 30, TimeUnit.SECONDS,
        SynchronousQueue(), { work -> Thread(work, "rust-dns-bootstrap").apply { isDaemon = true } })
    private val candidateResolver = ThreadPoolExecutor(2, 2, 30, TimeUnit.SECONDS,
        LinkedBlockingQueue(), { work -> Thread(work, "rust-dns-candidate").apply { isDaemon = true } })
        .apply { allowCoreThreadTimeOut(true) }

    override fun init(service: VpnService, log: (level: String, message: String) -> Unit) {
        this.log = log
        this.service = service
    }

    @Synchronized
    override fun start(config: String, params: CoreStartParams) {
        check(core == null) { "Rust runtime is already running" }
        val svc = checkNotNull(service) { "RustCore.init was not called" }
        val tunFd = params.tunFd ?: throw IllegalStateException("proxy-only is not supported by the Rust core")
        val prepared = prepareConfig(config, svc, resolver)
        val outbounds = JSONObject(prepared).optJSONArray("outbounds") ?: JSONArray()
        val policy = TunOwnerPolicy(
            onlySelected = params.vpnMode == VpnMode.ONLY_SELECTED,
            listedUids = params.allowedUids,
            blockUnowned = params.blockUnowned,
            tunDns = tunDnsServer,
            log = log,
        )
        log("info", "TUN owner check: mode=${params.vpnMode.id} uids=${params.allowedUids.size} " +
            "blockUnowned=${params.blockUnowned} admission=${policy.needsAdmission}")
        val runtime = XrayCore.create(
            configJson = prepared,
            vpnService = svc,
            tunFileDescriptor = XrayTunFileDescriptor(tunFd),
            tunRuntimeProfile = XrayTunRuntimeProfile.Mobile,
            dnsBootstrapMode = XrayDnsBootstrapMode.StaticOnly,
            hysteriaStreamLimits = if ("hysteria" in protocols(outbounds)) HYSTERIA_STREAM_LIMITS else null,
            tunAdmission = if (policy.needsAdmission) tunAdmission(svc, policy) else null,
            geodataSearchDirectory = svc.filesDir,
        )
        try {
            runtime.start()
        } catch (error: Throwable) {
            runtime.close()
            throw error
        }
        core = runtime
        proxyTag = proxyLeafTag(outbounds)
        lastRxBytes = 0; lastRxAt = 0; lastTcpTxBytes = 0; lastTcpTxAt = 0
        log("info", "xray-rust started with direct TUN (Mobile profile)")
    }

    /**
     * Owner decision — as in GoCore. A timeout or a full queue rejects
     * the flow (failOpen=false): otherwise an excluded app could flood the queue.
     * A throwing owner lookup is refused by the policy itself (treated as ownerless).
     */
    private fun tunAdmission(service: VpnService, policy: TunOwnerPolicy): XrayTunAdmissionOptions {
        val cm = service.getSystemService(ConnectivityManager::class.java)
        return XrayTunAdmissionOptions(
            callback = XrayTunFlowAdmission { flow ->
                policy.admitFlow(flow.destination.address.hostAddress.orEmpty(), flow.destination.port) { cm.getConnectionOwnerUid(flow.protocol, flow.source, flow.destination) }
            },
            timeoutMs = TUN_ADMISSION_TIMEOUT_MS,
            failOpen = false,
        )
    }

    /**
     * Must finish before the service closes or reuses the fd.
     * The native stop is outside the monitor and has a deadline so a hang doesn't block
     * the next start and diagnostics.
     */
    override fun stop() {
        val runtime = synchronized(this) {
            val r = core ?: return
            core = null
            proxyTag = null
            r
        }
        val thread = Thread {
            try { runtime.stop() } catch (e: Exception) { log("warning", "xray-rust stop failed: ${e.message}") }
            finally { runCatching { runtime.close() } }
        }
        thread.isDaemon = true
        thread.start()
        try {
            thread.join(STOP_TIMEOUT_MS)
            if (thread.isAlive) log("warning", "xray-rust stop timed out after ${STOP_TIMEOUT_MS / 1000}s, forcing continuation")
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
    }

    /**
     * StaticOnly bootstrap: the core resolves server addresses only from `dns.hosts`.
     * Names of proxy servers (and DNS servers with direct DNS) are resolved here via
     * the physical network, with a shared budget of [RESOLVE_TIMEOUT_SECONDS].
     */
    private fun prepareConfig(config: String, context: Context, pool: ExecutorService): String {
        val json = JSONObject(config)
        val names = serverNames(json.optJSONArray("outbounds") ?: JSONArray()) + directDnsServerNames(json)
        if (names.isEmpty()) return config
        val dns = json.optJSONObject("dns") ?: JSONObject().also { json.put("dns", it) }
        val hosts = dns.optJSONObject("hosts") ?: JSONObject().also { dns.put("hosts", it) }
        val network = physicalNetwork(context)
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(RESOLVE_TIMEOUT_SECONDS)
        for (name in names) {
            val remaining = deadline - System.nanoTime()
            if (remaining <= 0) throw TimeoutException("Couldn't resolve address $name in time")
            val lookup = try {
                pool.submit<List<String>> { network.getAllByName(name).mapNotNull { it.hostAddress } }
            } catch (_: RejectedExecutionException) {
                throw TimeoutException("Couldn't resolve address $name in time")
            }
            val addresses = try {
                lookup.get(remaining, TimeUnit.NANOSECONDS)
            } catch (_: TimeoutException) {
                throw TimeoutException("Couldn't resolve address $name in time")
            } finally {
                lookup.cancel(true)
            }
            check(addresses.isNotEmpty()) { "Couldn't resolve address $name" }
            hosts.put("full:$name", JSONArray(addresses))
        }
        return json.toString()
    }

    /** DNS server names when the DNS module (`dns.tag`) is routed to direct. */
    private fun directDnsServerNames(json: JSONObject): Set<String> {
        val dns = json.optJSONObject("dns") ?: return emptySet()
        val tag = dns.optString("tag").takeIf { it.isNotEmpty() } ?: return emptySet()
        val rules = json.optJSONObject("routing")?.optJSONArray("rules") ?: return emptySet()
        val direct = (0 until rules.length()).any { i ->
            val rule = rules.optJSONObject(i) ?: return@any false
            val tags = rule.optJSONArray("inboundTag") ?: return@any false
            rule.optString("outboundTag") == "direct" && (0 until tags.length()).any { tags.optString(it) == tag }
        }
        if (!direct) return emptySet()
        val hosts = dns.optJSONObject("hosts")
        val servers = dns.optJSONArray("servers") ?: return emptySet()
        val names = linkedSetOf<String>()
        for (i in 0 until servers.length()) {
            val address = servers.optJSONObject(i)?.optString("address") ?: servers.optString(i)
            val host = if ("://" in address) runCatching { URI(address).host }.getOrNull() else address
            val name = host?.removeSurrounding("[", "]")
            if (name.isNullOrEmpty() || InetAddresses.isNumericAddress(name)) continue
            if (hosts?.has(name) == true || hosts?.has("full:$name") == true) continue
            names.add(name)
        }
        return names
    }

    /** Hosts of proxy outbounds (vnext / servers / address) and XHTTP downloadSettings. */
    private fun serverNames(outbounds: JSONArray): Set<String> {
        val names = linkedSetOf<String>()
        for (i in 0 until outbounds.length()) {
            val outbound = outbounds.getJSONObject(i)
            val settings = outbound.optJSONObject("settings") ?: continue
            val list = when (outbound.optString("protocol")) {
                "vless", "vmess" -> "vnext"
                "trojan", "shadowsocks" -> "servers"
                "hysteria" -> null
                else -> continue
            }
            val servers = list?.let(settings::optJSONArray)
            if (servers == null) {
                names.add(settings.getString("address"))
            } else {
                for (j in 0 until servers.length()) names.add(servers.getJSONObject(j).getString("address"))
            }
            val xhttp = outbound.optJSONObject("streamSettings")?.optJSONObject("xhttpSettings")
            val download = xhttp?.optJSONObject("extra")?.optJSONObject("downloadSettings")
                ?: xhttp?.takeUnless { it.has("extra") }?.optJSONObject("downloadSettings")
            download?.optString("address")?.trim()?.takeIf { it.isNotEmpty() }?.let(names::add)
        }
        names.removeAll { InetAddresses.isNumericAddress(it.removeSurrounding("[", "]")) }
        return names
    }

    private fun physicalNetwork(context: Context): Network {
        val cm = context.getSystemService(ConnectivityManager::class.java)
        @Suppress("DEPRECATION")
        val candidates = (listOfNotNull(cm.activeNetwork) + cm.allNetworks).distinct().filter {
            val caps = cm.getNetworkCapabilities(it)
            caps != null && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        }
        return candidates.firstOrNull {
            cm.getNetworkCapabilities(it)?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
        } ?: candidates.firstOrNull() ?: error("No network available for the VPN connection")
    }

    private fun protocols(outbounds: JSONArray): Set<String> =
        (0 until outbounds.length()).mapNotNull { outbounds.optJSONObject(it)?.optString("protocol") }.toSet()

    private fun proxyLeafTag(outbounds: JSONArray): String? {
        val leaves = (0 until outbounds.length()).mapNotNull { outbounds.optJSONObject(it) }
        val proxy = leaves.firstOrNull { it.optString("tag") == PROXY_TAG }
            ?: leaves.firstOrNull { it.optString("protocol") in PROXY_PROTOCOLS }
        return proxy?.optString("tag")?.takeIf { it.isNotEmpty() }
    }

    /** A single GET through the running core's proxy exit, bypassing routing. */
    override fun measureDelay(url: String): Long {
        val (runtime, tag) = synchronized(this) { (core ?: return -1L) to proxyTag }
        val result = try {
            runtime.probeOutboundUrl(url, HEARTBEAT_PROBE_TIMEOUT_MS, tag)
        } catch (e: IllegalArgumentException) {
            runtime.probeOutboundUrl(DEFAULT_PROBE_URL, HEARTBEAT_PROBE_TIMEOUT_MS, tag)
        } catch (e: XrayCoreException) {
            if (e.code != XRAY_STATUS_INVALID_ARGUMENT) throw e
            runtime.probeOutboundUrl(DEFAULT_PROBE_URL, HEARTBEAT_PROBE_TIMEOUT_MS, tag)
        }
        return result.delayMs ?: -1L
    }

    /**
     * Candidate latency: a temporary core without TUN (the probe config carries a loopback SOCKS
     * on an ephemeral port), sockets protected by the running VPN's VpnService.
     */
    override fun measureOutbound(context: Context, config: String, url: String): Long {
        if (!candidateSlots.tryAcquire(CANDIDATE_SLOT_WAIT_MS, TimeUnit.MILLISECONDS)) return -1L
        try {
            val prepared = prepareConfig(config, context, candidateResolver)
            val protector = synchronized(this) { if (core != null) service else null }
            XrayCore.create(
                configJson = prepared,
                vpnService = protector,
                dnsBootstrapMode = XrayDnsBootstrapMode.StaticOnly,
                geodataSearchDirectory = context.filesDir,
            ).use { candidate ->
                candidate.start()
                try {
                    val tag = proxyLeafTag(JSONObject(prepared).optJSONArray("outbounds") ?: JSONArray())
                    val result = try {
                        candidate.probeOutboundUrl(url, CANDIDATE_PROBE_TIMEOUT_MS, tag)
                    } catch (_: IllegalArgumentException) {
                        candidate.probeOutboundUrl(DEFAULT_PROBE_URL, CANDIDATE_PROBE_TIMEOUT_MS, tag)
                    } catch (e: XrayCoreException) {
                        if (e.code != XRAY_STATUS_INVALID_ARGUMENT) throw e
                        candidate.probeOutboundUrl(DEFAULT_PROBE_URL, CANDIDATE_PROBE_TIMEOUT_MS, tag)
                    }
                    return result.delayMs ?: -1L
                } finally {
                    candidate.stop()
                }
            }
        } finally {
            candidateSlots.release()
        }
    }

    private fun tunStats(runtime: XrayCore): XrayTunStats? =
        try { runtime.stats() } catch (_: RuntimeException) { null }

    /** lastRx — the last growth of bytes received from the network by TUN flows; tx — TCP bytes accepted by the outbound. */
    private fun sampleRx(stats: XrayTunStats) {
        val now = System.currentTimeMillis()
        val bytes = stats.tcpRemoteReadBytes + stats.udpRemoteReadBytes
        if (bytes > lastRxBytes) lastRxAt = now
        lastRxBytes = bytes
        if (stats.tcpRemoteWrittenBytes > lastTcpTxBytes) lastTcpTxAt = now
        lastTcpTxBytes = stats.tcpRemoteWrittenBytes
    }

    private inline fun <T> withStats(default: T, block: (XrayCore, XrayTunStats) -> T): T = synchronized(this) {
        val runtime = core ?: return default
        val stats = tunStats(runtime) ?: return default
        sampleRx(stats)
        block(runtime, stats)
    }

    /** "Alive" = the runtime is started and reports stats (the fd loop exit counters are not checked). */
    override fun isTunRunning(): Boolean = withStats(false) { _, _ -> true }

    override fun activeConnections(): Long = synchronized(this) {
        core?.let { runCatching { it.connectionSnapshot().connections.size.toLong() }.getOrNull() } ?: 0L
    }
    override fun uploadBytes(): Long = withStats(0L) { _, s -> s.uplinkBytes }
    override fun downloadBytes(): Long = withStats(0L) { _, s -> s.downlinkBytes }

    /**
     * For the stall detector: the last incoming payload or accepted TCP upload
     * (xray-rust ACKs locally, a long upload without a reply would otherwise look stuck).
     */
    override fun lastRxActivityMs(): Long = withStats(lastRxAt) { _, _ ->
        if (lastRxAt > 0) maxOf(lastRxAt, lastTcpTxAt) else 0L
    }

    override fun closeAllConnections(): Long = synchronized(this) {
        val runtime = core ?: return 0L
        val connections = runCatching { runtime.connectionSnapshot().connections }.getOrNull() ?: return 0L
        connections.count { runCatching { runtime.closeConnection(it.id) }.isSuccess }.toLong()
    }

    override fun statsLine(): String = diagnostics()

    override fun diagnostics(): String = withStats("") { runtime, stats ->
        val json = JSONObject().apply {
            put("engine", version())
            put("inboundPackets", stats.inboundPackets)
            put("outboundPackets", stats.outboundPackets)
            put("droppedPackets", stats.droppedPackets)
            put("tcpUp", stats.tcpRemoteWrittenBytes)
            put("tcpDown", stats.tcpRemoteReadBytes)
            put("udpUp", stats.udpRemoteWrittenBytes)
            put("udpDown", stats.udpRemoteReadBytes)
            put("tcpOpens", stats.tcpOpenEvents)
            put("udpOpens", stats.udpRemoteOpenEvents)
        }
        try {
            json.put("routingRules", runtime.routingPolicySnapshot().ruleCount)
        } catch (_: RuntimeException) {
        }
        json.toString()
    }

    override fun version(): String =
        XrayCore.ffiInfo().version.let { "xray-rust $XRAY_RUST_VERSION (ffi ${it.major}.${it.minor})" }
}
