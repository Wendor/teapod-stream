package com.teapodstream.teapodstream

import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.VpnService
import org.json.JSONArray
import org.json.JSONObject
import org.xrayrust.mobile.XrayCore
import org.xrayrust.mobile.XrayDnsBootstrapMode
import org.xrayrust.mobile.XrayTunFileDescriptor
import org.xrayrust.mobile.XrayTunRuntimeProfile
import java.util.concurrent.SynchronousQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/** Owns one Rust runtime. Android owns the borrowed TUN descriptor. */
internal object RustCore {
    const val VERSION = "xray-rust 0.6.1+geo.1"
    private var core: XrayCore? = null
    private var lastRxPackets = 0L
    private var lastRxAt = 0L
    private var geodataRevision = ""
    // A timed-out platform resolver may ignore interruption. Bound its workers
    // as well as the wait, so repeated reconnects cannot leak resolver threads.
    private val resolver = ThreadPoolExecutor(0, 2, 30, TimeUnit.SECONDS,
        SynchronousQueue(), { work -> Thread(work, "rust-dns-bootstrap").apply { isDaemon = true } })

    /** Resolve the server before installing TUN, including during a reconnect. */
    fun prepareConfig(config: String, service: VpnService): String {
        val json = JSONObject(config)
        val dns = json.getJSONObject("dns")
        val hosts = dns.optJSONObject("hosts") ?: JSONObject().also { dns.put("hosts", it) }
        val cm = service.getSystemService(ConnectivityManager::class.java)
        val candidates = (listOfNotNull(cm.activeNetwork) + cm.allNetworks).distinct().filter {
            val caps = cm.getNetworkCapabilities(it)
            caps != null && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        }
        val network = candidates.firstOrNull {
            cm.getNetworkCapabilities(it)?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
        } ?: candidates.firstOrNull() ?: error("Нет доступной сети для подключения VPN")
        val outbounds = json.getJSONArray("outbounds")
        for (i in 0 until outbounds.length()) {
            val outbound = outbounds.getJSONObject(i)
            if (outbound.optString("protocol") != "vless") continue
            val address = outbound.getJSONObject("settings")
                .getJSONArray("vnext").getJSONObject(0).getString("address")
            val lookup = resolver.submit<List<String>> {
                network.getAllByName(address).mapNotNull { it.hostAddress }
            }
            val addresses = try {
                lookup.get(5, TimeUnit.SECONDS)
            } finally {
                lookup.cancel(true)
            }
            check(addresses.isNotEmpty()) { "Не удалось разрешить адрес VPN-сервера" }
            hosts.put("full:$address", JSONArray(addresses))
        }
        // The initial build accepts literal-IP DNS and the bundled DoH/DoT
        // presets with their static bootstrap hosts. Never recurse through TUN.
        return json.toString()
    }

    @Synchronized
    fun start(config: String, service: VpnService, tunFd: Int) {
        check(core == null) { "Rust runtime is already running" }
        val runtime = GeodataStore.withDirectory(service) { geodata ->
            geodataRevision = geodata.name
            XrayCore.create(
                configJson = config,
                vpnService = service,
                tunFileDescriptor = XrayTunFileDescriptor(tunFd),
                tunRuntimeProfile = XrayTunRuntimeProfile.Mobile,
                dnsBootstrapMode = XrayDnsBootstrapMode.StaticOnly,
                geodataDirectory = geodata,
            )
        }
        try {
            runtime.start()
            core = runtime
            lastRxPackets = 0
            lastRxAt = 0
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
        try {
            runtime.stop()
        } finally {
            runtime.close()
        }
    }

    @Synchronized
    fun isRunning(): Boolean = core != null

    @Synchronized
    fun trafficTotals(): Pair<Long, Long> {
        val runtime = core ?: return 0L to 0L
        sampleRx(runtime)
        val counters = runtime.outboundAccountingSnapshot().outbounds
        return counters.sumOf { it.uplinkBytes } to counters.sumOf { it.downlinkBytes }
    }

    private fun sampleRx(runtime: XrayCore) {
        val packets = runtime.stats().outboundPackets
        if (packets > lastRxPackets) lastRxAt = System.currentTimeMillis()
        lastRxPackets = packets
    }

    @Synchronized
    fun lastRxActivityMs(): Long {
        core?.let { sampleRx(it) }
        return lastRxAt
    }

    @Synchronized
    fun activeConnections(): Long = core?.connectionSnapshot()?.connections?.size?.toLong() ?: 0

    @Synchronized
    fun closeConnections(): Int {
        val runtime = core ?: return 0
        return runtime.connectionSnapshot().connections.count {
            runCatching { runtime.closeConnection(it.id) }.isSuccess
        }
    }

    @Synchronized
    fun diagnostics(): String {
        val runtime = core ?: return ""
        val stats = runtime.stats()
        return JSONObject().apply {
            put("engine", VERSION)
            put("tunBackend", "fd")
            put("geodata", geodataRevision)
            put("routingRules", runtime.routingPolicySnapshot().ruleCount)
            put("inboundPackets", stats.inboundPackets)
            put("outboundPackets", stats.outboundPackets)
            put("droppedPackets", stats.droppedPackets)
            put("activeConnections", activeConnections())
            put("outbounds", JSONArray(runtime.outboundAccountingSnapshot().outbounds.map {
                JSONObject().put("tag", it.outboundTag).put("upload", it.uplinkBytes)
                    .put("download", it.downlinkBytes).put("connections", it.openedConnections)
            }))
        }.toString()
    }
}
