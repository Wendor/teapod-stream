package com.teapodstream.teapodstream

import android.content.Context
import android.net.ConnectivityManager
import android.net.InetAddresses
import android.net.Network
import android.net.NetworkCapabilities
import android.net.VpnService
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import org.xrayrust.mobile.XrayCore
import org.xrayrust.mobile.XrayCoreException
import org.xrayrust.mobile.XrayDnsBootstrapMode
import org.xrayrust.mobile.XrayHysteriaStreamLimits
import org.xrayrust.mobile.XrayOutboundProbeResult
import org.xrayrust.mobile.XrayTunAdmissionOptions
import org.xrayrust.mobile.XrayTunFileDescriptor
import org.xrayrust.mobile.XrayTunRuntimeProfile
import org.xrayrust.mobile.XrayTunStats
import java.net.URI
import java.util.concurrent.ExecutorService
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.Semaphore
import java.util.concurrent.SynchronousQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/** Owns one Rust runtime. Android owns the borrowed TUN descriptor. */
internal object RustCore {
    const val VERSION = "xray-rust 0.8.1"
    private const val RESOLVE_TIMEOUT_SECONDS = 5L
    private const val RESOLVE_TIMEOUT_MESSAGE = "Не удалось вовремя разрешить адрес VPN-сервера"
    private const val RESOLVE_DNS_TIMEOUT_MESSAGE = "Не удалось вовремя разрешить адрес DNS-сервера"
    /** Tag of the proxy leaf in the app's Rust configs (XrayConfigBuilder). */
    const val PROXY_TAG = "proxy"
    private val PROXY_PROTOCOLS = setOf("vless", "vmess", "trojan", "shadowsocks", "hysteria")
    /**
     * Hysteria concurrent-flow limits per outbound (core default 64/32). 256 TCP is
     * the Mobile TUN profile's own cap on active TCP flows (`MOBILE_FLOW_BUDGET_POLICY`,
     * two 32 KiB smoltcp buffers each), so Hysteria refuses no flow a VLESS profile
     * would carry. Buffering does not grow with the limit: QUIC receive windows are
     * fixed per connection (3 MiB, `XRAY_INITIAL_CONNECTION_RECEIVE_WINDOW`), the send
     * window is connection-wide (2–10 MB), queued UDP payload shares one 1 MiB budget
     * (`HysteriaLimits::udp_queue_bytes`) and TUN TCP buffering keeps its 40 MiB hard
     * total (`MOBILE_TCP_REMOTE_BUFFER_POLICY`) for every protocol. 128 UDP is the API
     * maximum, well inside the profile's 512 UDP flows.
     */
    private val HYSTERIA_STREAM_LIMITS = XrayHysteriaStreamLimits(maxTcpStreams = 256, maxUdpSessions = 128)
    /** In-core heartbeat probe bound, the same 10 s the SOCKS probe allows per step. */
    const val HEARTBEAT_PROBE_TIMEOUT_MS = 10_000L
    /** Candidate probe bound: the core observatory's fixed 5 s probe timeout. */
    private const val CANDIDATE_PROBE_TIMEOUT_MS = 5_000L
    /**
     * How long a queued candidate waits for a slot, then counts as unmeasured. switchConfig
     * sends every candidate at once, so this bounds the whole batch near Go's worst case
     * (all candidates at once, two 12 s attempts each): 20 s + 5 s DNS + 5 s probe.
     */
    private const val CANDIDATE_SLOT_WAIT_MS = 20_000L
    /** Candidate target when the core refuses the heartbeat URL: the heartbeat's default. */
    private const val DEFAULT_PROBE_URL = "http://cp.cloudflare.com/generate_204"
    /** XrayStatus INVALID_ARGUMENT (xray_ffi.h): the probe URL, tag or timeout. */
    private const val XRAY_STATUS_INVALID_ARGUMENT = 9
    private const val TAG = "RustCore"
    /**
     * Each temporary core owns a Tokio runtime (2–6 workers) beside the running VPN
     * core; switchConfig asks for every candidate at once, so at most two are alive.
     */
    private val candidateSlots = Semaphore(2, true)
    private var core: XrayCore? = null
    // The VpnService of the running core: candidate cores protect their sockets with it.
    private var service: VpnService? = null
    private var proxyTag: String? = null
    private var hysteria = false
    private var lastRxBytes = 0L
    private var lastRxAt = 0L
    private var lastTcpTxBytes = 0L
    private var lastTcpTxAt = 0L
    private var geodataRevision = ""
    // A timed-out platform resolver may ignore interruption. Bound its workers
    // as well as the wait, so repeated reconnects cannot leak resolver threads.
    private val resolver = ThreadPoolExecutor(0, 2, 30, TimeUnit.SECONDS,
        SynchronousQueue(), { work -> Thread(work, "rust-dns-bootstrap").apply { isDaemon = true } })
    // switchConfig lookups get their own two workers: a lookup abandoned at its deadline
    // keeps its thread, so measurement must never take the VPN start's resolver. Queued,
    // so a busy pool costs a candidate its own deadline instead of failing it at once.
    private val candidateResolver = ThreadPoolExecutor(2, 2, 30, TimeUnit.SECONDS,
        LinkedBlockingQueue(), { work -> Thread(work, "rust-dns-candidate").apply { isDaemon = true } })
        .apply { allowCoreThreadTimeOut(true) }

    /**
     * Resolve every proxy server name before installing TUN, including during a
     * reconnect. StaticOnly bootstrap lets the core resolve carrier hosts only
     * from `dns.hosts`; IP literals need no entry. The same holds for DNS server
     * names in direct DNS mode, see [directDnsServerNames]. [pool] runs the lookups;
     * switchConfig candidates pass their own.
     */
    fun prepareConfig(config: String, context: Context, pool: ExecutorService = resolver): String {
        val json = JSONObject(config)
        val names = serverNames(json.getJSONArray("outbounds"))
            .associateWith { RESOLVE_TIMEOUT_MESSAGE to "Не удалось разрешить адрес VPN-сервера" } +
            directDnsServerNames(json).associateWith {
                RESOLVE_DNS_TIMEOUT_MESSAGE to "Не удалось разрешить адрес DNS-сервера $it"
            }
        if (names.isEmpty()) return config
        val dns = json.optJSONObject("dns") ?: JSONObject().also { json.put("dns", it) }
        val hosts = dns.optJSONObject("hosts") ?: JSONObject().also { dns.put("hosts", it) }
        val network = physicalNetwork(context)
        // One budget for all names, so several servers cannot stack 5 s waits.
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(RESOLVE_TIMEOUT_SECONDS)
        for ((name, messages) in names) {
            val (timeoutMessage, failureMessage) = messages
            val remaining = deadline - System.nanoTime()
            if (remaining <= 0) throw TimeoutException(timeoutMessage)
            val lookup = try {
                pool.submit<List<String>> { network.getAllByName(name).mapNotNull { it.hostAddress } }
            } catch (_: RejectedExecutionException) {
                // Both workers still wait on lookups that timed out earlier.
                throw TimeoutException(timeoutMessage)
            }
            val addresses = try {
                lookup.get(remaining, TimeUnit.NANOSECONDS)
            } catch (_: TimeoutException) {
                throw TimeoutException(timeoutMessage)
            } finally {
                lookup.cancel(true)
            }
            check(addresses.isNotEmpty()) { failureMessage }
            hosts.put("full:$name", JSONArray(addresses))
        }
        // Literal-IP DNS and the bundled DoH/DoT presets carry static hosts; DNS
        // through the VPN resolves a DNS server name remotely. Never recurse through TUN.
        return json.toString()
    }

    /**
     * DNS server names to pin when the DNS module (`dns.tag`) is routed to `direct`
     * (the Rust direct DNS mode). Through Freedom, StaticOnly bootstrap finds a
     * server name only in `dns.hosts`, so a custom DoH/DoT/UDP server given by name
     * would fail; through the proxy the server resolves it and nothing leaks
     * here. Names already in `dns.hosts` (the presets' fallback IPs) stay as given.
     */
    private fun directDnsServerNames(json: JSONObject): Set<String> {
        val dns = json.optJSONObject("dns") ?: return emptySet()
        val tag = dns.optString("tag").takeIf { it.isNotEmpty() } ?: return emptySet()
        val rules = json.optJSONObject("routing")?.optJSONArray("rules") ?: return emptySet()
        val direct = (0 until rules.length()).any { i ->
            val rule = rules.optJSONObject(i) ?: return@any false
            val tags = rule.optJSONArray("inboundTag") ?: return@any false
            rule.optString("outboundTag") == "direct" &&
                (0 until tags.length()).any { tags.optString(it) == tag }
        }
        if (!direct) return emptySet()
        val hosts = dns.optJSONObject("hosts")
        val servers = dns.optJSONArray("servers") ?: return emptySet()
        val names = linkedSetOf<String>()
        for (i in 0 until servers.length()) {
            val address = servers.optJSONObject(i)?.optString("address") ?: servers.optString(i)
            // `https://h[:p]/path`, `tls://h[:p]`, `tcp://h` or a bare UDP server.
            val host = if ("://" in address) runCatching { URI(address).host }.getOrNull() else address
            val name = host?.removeSurrounding("[", "]")
            if (name.isNullOrEmpty() || InetAddresses.isNumericAddress(name)) continue
            if (hosts?.has(name) == true || hosts?.has("full:$name") == true) continue
            names.add(name)
        }
        return names
    }

    /**
     * Server host names of the proxy outbounds: every `vnext` entry of VLESS and
     * VMess, every `servers` entry of Trojan and Shadowsocks, the Hysteria
     * server. xray-rust also accepts the flattened `address` form of the last
     * four; the app's builder writes the list form, either is read here. An XHTTP
     * `downloadSettings` server dials through the same bootstrap and is added too.
     */
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
            // `extra` replaces the outer XHTTP fields (except host/path/mode), as in Xray.
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
        val candidates = (listOfNotNull(cm.activeNetwork) + cm.allNetworks).distinct().filter {
            val caps = cm.getNetworkCapabilities(it)
            caps != null && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        }
        return candidates.firstOrNull {
            cm.getNetworkCapabilities(it)?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
        } ?: candidates.firstOrNull() ?: error("Нет доступной сети для подключения VPN")
    }

    /**
     * [tunAdmission] installs the per-flow owner check; null keeps every flow that
     * Android routes into the TUN, as before.
     */
    @Synchronized
    fun start(config: String, service: VpnService, tunFd: Int, tunAdmission: XrayTunAdmissionOptions? = null) {
        check(core == null) { "Rust runtime is already running" }
        val outbounds = JSONObject(config).optJSONArray("outbounds") ?: JSONArray()
        val usesHysteria = protocols(outbounds).contains("hysteria")
        val runtime = GeodataStore.withDirectory(service) { geodata ->
            geodataRevision = geodata.name
            XrayCore.create(
                configJson = config,
                vpnService = service,
                tunFileDescriptor = XrayTunFileDescriptor(tunFd),
                tunRuntimeProfile = XrayTunRuntimeProfile.Mobile,
                dnsBootstrapMode = XrayDnsBootstrapMode.StaticOnly,
                // Other protocols keep the core defaults untouched.
                hysteriaStreamLimits = if (usesHysteria) HYSTERIA_STREAM_LIMITS else null,
                tunAdmission = tunAdmission,
                geodataDirectory = geodata,
            )
        }
        try {
            runtime.start()
            core = runtime
            this.service = service
            proxyTag = proxyLeafTag(outbounds)
            hysteria = usesHysteria
            lastRxBytes = 0
            lastRxAt = 0
            lastTcpTxBytes = 0
            lastTcpTxAt = 0
        } catch (error: Throwable) {
            runtime.close()
            throw error
        }
    }

    /** Must finish before the service closes or reuses its borrowed fd. */
    @Synchronized
    fun stop() {
        val runtime = core ?: return
        core = null
        service = null
        proxyTag = null
        hysteria = false
        try {
            runtime.stop()
        } finally {
            runtime.close()
        }
    }

    @Synchronized
    fun isRunning(): Boolean = core != null

    /** The running config has a Hysteria outbound, whose carrier can be rebound. */
    @Synchronized
    fun usesHysteria(): Boolean = core != null && hysteria

    /**
     * Queues fresh protected Hysteria carrier sockets on the current network; live
     * QUIC connections migrate and keep their flows (ABI 1.7). The count is accepted
     * requests (0 for an idle outbound, whose next flow dials afresh), not recovery.
     * Throws when the runtime is stopped or the core cannot rebind.
     */
    fun rebindHysteria(): Long {
        val runtime = synchronized(this) { core } ?: error("Rust runtime is not running")
        return runtime.rebindHysteria()
    }

    /**
     * XRAYDELAY: one HTTP(S) GET through the proxy leaf of the running core
     * (`probeOutboundUrl`, ABI 1.9). Routing rules are bypassed, so «ТОЛЬКО»
     * routing, whose default outbound is direct, cannot report a dead proxy as alive.
     * Blocks up to [timeoutMs] outside this object's lock; stop() cancels it.
     */
    fun probeProxy(url: String, timeoutMs: Long = HEARTBEAT_PROBE_TIMEOUT_MS): XrayOutboundProbeResult {
        val (runtime, tag) = synchronized(this) {
            (core ?: error("Rust runtime is not running")) to proxyTag
        }
        return runtime.probeOutboundUrl(url, timeoutMs, tag)
    }

    /**
     * switchConfig candidate delay in ms, -1 when unreachable: a temporary core
     * without TUN (xray-rust starts only with an inbound, so the probe config carries
     * a loopback SOCKS on an ephemeral port) probes [url] through its proxy leaf and
     * is always closed. While the VPN runs, its VpnService protects the candidate's
     * sockets, so they bypass the tunnel. Server names are pinned as for the VPN, on
     * the candidates' own resolver workers. A candidate that finds no free slot within
     * [CANDIDATE_SLOT_WAIT_MS] counts as unmeasured. A URL the core refuses is
     * measured through [DEFAULT_PROBE_URL], as the heartbeat falls back for it.
     */
    fun measureCandidate(context: Context, config: String, url: String): Long {
        if (!candidateSlots.tryAcquire(CANDIDATE_SLOT_WAIT_MS, TimeUnit.MILLISECONDS)) return -1L
        try {
            val prepared = prepareConfig(config, context, candidateResolver)
            val protector = synchronized(this) { service }
            XrayCore.create(
                configJson = prepared,
                vpnService = protector,
                dnsBootstrapMode = XrayDnsBootstrapMode.StaticOnly,
            ).use { candidate ->
                candidate.start()
                try {
                    val tag = proxyLeafTag(JSONObject(prepared).optJSONArray("outbounds") ?: JSONArray())
                    val result = try {
                        candidate.probeOutboundUrl(url, CANDIDATE_PROBE_TIMEOUT_MS, tag)
                    } catch (e: IllegalArgumentException) {
                        defaultTargetAfterRefusal(e)
                        candidate.probeOutboundUrl(DEFAULT_PROBE_URL, CANDIDATE_PROBE_TIMEOUT_MS, tag)
                    } catch (e: XrayCoreException) {
                        // IPv6 literal, userinfo, fragment or an upper-case scheme: Go
                        // measures these URLs, so measure the default target instead.
                        if (e.code != XRAY_STATUS_INVALID_ARGUMENT) throw e
                        defaultTargetAfterRefusal(e)
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

    // The URL itself may carry userinfo, so only the core's message is logged.
    private fun defaultTargetAfterRefusal(e: Exception) {
        Log.w(TAG, "switchConfig: the core refused the probe URL (${e.message}), measuring $DEFAULT_PROBE_URL")
    }

    private fun protocols(outbounds: JSONArray): Set<String> =
        (0 until outbounds.length()).mapNotNull { outbounds.optJSONObject(it)?.optString("protocol") }.toSet()

    /** The app's proxy leaf, or the first proxy-protocol outbound of a foreign config. */
    private fun proxyLeafTag(outbounds: JSONArray): String? {
        val leaves = (0 until outbounds.length()).mapNotNull { outbounds.optJSONObject(it) }
        val proxy = leaves.firstOrNull { it.optString("tag") == PROXY_TAG }
            ?: leaves.firstOrNull { it.optString("protocol") in PROXY_PROTOCOLS }
        return proxy?.optString("tag")?.takeIf { it.isNotEmpty() }
    }

    /**
     * Upload/download payload bytes of TUN flows, counted live as the core writes to
     * and reads from each outbound (proxy and direct alike, DNS upstream exchanges
     * included). The outbound accounting snapshot adds a connection only once it
     * closes, so speed stayed at zero during a long transfer. The app's own SOCKS
     * probe is not TUN traffic and is left out, as in Go's tun2socks counters.
     */
    @Synchronized
    fun trafficTotals(): Pair<Long, Long> {
        val stats = core?.let(::tunStats) ?: return 0L to 0L
        sampleRx(stats)
        return (stats.tcpRemoteWrittenBytes + stats.udpRemoteWrittenBytes) to
            (stats.tcpRemoteReadBytes + stats.udpRemoteReadBytes)
    }

    /** Null when the runtime is stopped or its stats cannot be read. */
    private fun tunStats(runtime: XrayCore): XrayTunStats? =
        try { runtime.stats() } catch (_: RuntimeException) { null }

    /**
     * lastRx is the last time data arrived from the network for a TUN flow: TCP or
     * UDP remote read bytes grew. outboundPackets also counted packets the core
     * writes itself (DNS/FakeDNS answers, ICMP echo replies, TCP handshakes and
     * ACKs), so a silent server could look alive. Resolution is the sampling
     * period: the stats thread samples every 1 s, or 10 s with the screen off.
     */
    private fun sampleRx(stats: XrayTunStats) {
        val now = System.currentTimeMillis()
        val bytes = stats.tcpRemoteReadBytes + stats.udpRemoteReadBytes
        if (bytes > lastRxBytes) lastRxAt = now
        lastRxBytes = bytes
        // TCP payload the outbound accepted. A reply-less upload (HTTP/1.1 PUT, FTP STOR)
        // is alive while it moves; a half-open upstream stops accepting writes once the
        // socket buffer fills. UDP sends never block, so they are not proof of life.
        if (stats.tcpRemoteWrittenBytes > lastTcpTxBytes) lastTcpTxAt = now
        lastTcpTxBytes = stats.tcpRemoteWrittenBytes
    }

    @Synchronized
    fun lastRxActivityMs(): Long {
        core?.let(::tunStats)?.let(::sampleRx)
        return lastRxAt
    }

    /**
     * TUN stall watchdog only: the last downstream payload or accepted TCP upload.
     * Go's tun2socks refreshes lastRx with every TUN write, including the ACKs for an
     * app's upload; xray-rust ACKs locally, so a long reply-less upload would look
     * stalled on reads alone. Zero until the first downstream byte, as before.
     */
    @Synchronized
    fun lastTunActivityMs(): Long {
        core?.let(::tunStats)?.let(::sampleRx)
        return if (lastRxAt > 0) maxOf(lastRxAt, lastTcpTxAt) else 0L
    }

    /**
     * Why the TUN data path is down, or null while it works — the counterpart of
     * Go's isTunRunning(). xray-rust keeps the runtime up after a TUN fd read or
     * write loop stops on an fd error (for example a descriptor closed by the
     * system), so isRunning() alone would report a tunnel that no longer moves packets.
     */
    @Synchronized
    fun tunFailure(): String? {
        val runtime = core ?: return "runtime stopped"
        val stats = tunStats(runtime) ?: return "TUN stats unavailable"
        sampleRx(stats)
        if (stats.tunFdReadLoopExits > 0 || stats.tunFdWriteLoopExits > 0) {
            return "TUN fd loop exited (read=${stats.tunFdReadLoopExits}, write=${stats.tunFdWriteLoopExits})"
        }
        return null
    }

    fun isTunRunning(): Boolean = tunFailure() == null

    /** Open TCP + UDP flows of the TUN stack, like tun2socks' active connections. */
    @Synchronized
    fun tunActiveFlows(): Long {
        val stats = core?.let(::tunStats) ?: return 0
        sampleRx(stats)
        return stats.activeTcpFlows + stats.activeUdpFlows
    }

    /** Connections tracked by the core, including the SOCKS probe; diagnostics only. */
    @Synchronized
    fun activeConnections(): Long = core?.connectionSnapshot()?.connections?.size?.toLong() ?: 0

    @Synchronized
    fun closeConnections(): Int {
        val runtime = core ?: return 0
        return runtime.connectionSnapshot().connections.count {
            runCatching { runtime.closeConnection(it.id) }.isSuccess
        }
    }

    /**
     * Snapshot for the heartbeat log. A failed core query leaves its fields out
     * instead of throwing: the heartbeat would count an exception as a failed
     * probe, and PASSIVE runs no probe at all.
     */
    @Synchronized
    fun diagnostics(): String {
        val runtime = core ?: return ""
        val stats = tunStats(runtime) ?: return ""
        sampleRx(stats)
        val json = JSONObject().apply {
            put("engine", VERSION)
            put("tunBackend", "fd")
            put("geodata", geodataRevision)
            put("inboundPackets", stats.inboundPackets)
            put("outboundPackets", stats.outboundPackets)
            put("droppedPackets", stats.droppedPackets)
            // Live payload bytes of TUN flows; tcpDown + udpDown drive lastRx.
            put("tcpUp", stats.tcpRemoteWrittenBytes)
            put("tcpDown", stats.tcpRemoteReadBytes)
            put("udpUp", stats.udpRemoteWrittenBytes)
            put("udpDown", stats.udpRemoteReadBytes)
            put("tcpFlows", stats.activeTcpFlows)
            put("udpFlows", stats.activeUdpFlows)
            put("tcpOpenErrors", stats.tcpOpenErrors)
            put("udpOpenErrors", stats.udpOpenErrors)
            put("remoteReadErrors", stats.tcpRemoteReadErrors + stats.udpRemoteReadErrors)
            put("remoteWriteErrors", stats.tcpRemoteWriteErrors + stats.udpRemoteWriteErrors)
            put("tunFdLoopExits", stats.tunFdReadLoopExits + stats.tunFdWriteLoopExits)
            put("tunFdTransientErrors", stats.tunFdTransientIoErrors)
        }
        return try {
            json.put("routingRules", runtime.routingPolicySnapshot().ruleCount)
            json.put("activeConnections", activeConnections())
            // Closed connections only: the core adds a connection's bytes when it ends.
            json.put("outbounds", JSONArray(runtime.outboundAccountingSnapshot().outbounds.map {
                JSONObject().put("tag", it.outboundTag).put("upload", it.uplinkBytes)
                    .put("download", it.downlinkBytes).put("connections", it.openedConnections)
            }))
            json.toString()
        } catch (_: RuntimeException) {
            json.toString()
        }
    }
}
