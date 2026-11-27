package com.teapodstream.teapodstream

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import com.teapodstream.teapodstream.core.VpnCore

/// The physical network under a running session: tracks it, sets it as the VPN's underlying
/// network and reconnects on a change as [NetworkChangePolicy] decides. [start] on connect,
/// [stop] when the session stops.
internal class NetworkWatcher(private val service: VpnService, private val host: Host) {
    interface Host {
        /** When the session connected; -1 — not connected (no reconnects before connected). */
        val connectedAt: Long
        /** The TUN mode session is running: tun2socks connections can be closed. */
        val tunRunning: Boolean
        val core: VpnCore
        /** Reconnect the stored session while [session] is the connected one. */
        fun reconnect(session: Long)
        fun log(level: String, message: String)
    }

    private var callback: ConnectivityManager.NetworkCallback? = null
    @Volatile private var underlying: Network? = null
    // The physical network at the moment of connected — the deferred network-change check compares against it.
    @Volatile private var connected: Network? = null
    private val policy = NetworkChangePolicy()
    private val handler = Handler(Looper.getMainLooper())
    private var pending: Runnable? = null

    /** The session connected on the current physical network. */
    fun markConnected() {
        connected = underlying
    }

    /** The session stopped: no callback, no pending reconnect. */
    fun stop() {
        underlying = null
        pending?.let { handler.removeCallbacks(it) }
        pending = null
        policy.reset()
        try { unregister() } catch (e: Exception) {
            host.log("warning", "unregisterNetworkCallback failed: ${e.message}")
        }
    }

    fun start() {
        try {
            val cm = service.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            // Pre-seed underlying before registering so the initial onAvailable
            // callback sees prev == current and does NOT trigger a spurious reconnect.
            updateUnderlyingNetworks(cm)
            callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    host.log("info", "Network available: $network")
                    val prev = underlying
                    updateUnderlyingNetworks(cm)
                    val current = underlying
                    // Trigger if network changed (prev→current) OR if prev was null but we now
                    // have a network (covers WiFi→LTE when onLost fired before onAvailable).
                    if (current != null && prev != current) {
                        scheduleNetworkChanged(switched = true)
                    }
                }

                override fun onLost(network: Network) {
                    host.log("info", "Network lost: $network")
                    // Force-close all active tun2socks connections immediately on network loss.
                    // Stale gVisor TCP connections survive across brief network blips and cause
                    // app-level freezes (Telegram, etc.) because the SOCKS5 heartbeat cannot
                    // observe per-connection gVisor state. Closing them now forces apps to
                    // reconnect through a clean path when the network comes back.
                    if (host.tunRunning) {
                        val closed = host.core.closeAllConnections()
                        if (closed > 0) host.log("debug", "Network lost: force-closed $closed TUN connections")
                    }
                    // Snapshot BEFORE clearing — needed for smooth-handover case where
                    // onAvailable(LTE) fires before onLost(WiFi): prev=wifi, after=LTE → trigger.
                    val prev = underlying
                    if (underlying == network) {
                        underlying = null
                    }
                    updateUnderlyingNetworks(cm)
                    if (prev != null && underlying != null && prev != underlying) {
                        scheduleNetworkChanged(switched = true)
                    }
                }

                override fun onCapabilitiesChanged(
                    network: Network,
                    networkCapabilities: NetworkCapabilities
                ) {
                    if (cm.activeNetwork == network) {
                        val prev = underlying
                        updateUnderlyingNetworks(cm)
                        // Captive portal / temporary internet loss: VALIDATED is removed
                        // without triggering onLost/onAvailable — detect and reconnect.
                        val validated = networkCapabilities.hasCapability(
                            NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                        // The network became the default only after onAvailable (LTE → Wi-Fi after
                        // airplane mode): the core's sockets stayed on the previous network.
                        val switched = prev != null && underlying != null &&
                            prev != underlying
                        if (!validated) scheduleNetworkChanged()
                        else if (switched) scheduleNetworkChanged(switched = true)
                    }
                }
            }
            val request = NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()
            cm.registerNetworkCallback(request, callback!!)
        } catch (e: Exception) {
            host.log("warning", "Failed to register network callback: ${e.message}")
        }
    }

    fun physical(): Network? {
        val cm = service.getSystemService(ConnectivityManager::class.java)
        val activeNetwork = cm.activeNetwork ?: return null

        val caps = cm.getNetworkCapabilities(activeNetwork)
        if (caps == null || caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
            // Active is VPN — pick a physical internet network: VALIDATED first (Wi-Fi
            // without internet must not win over working LTE), then Wi-Fi over others.
            return try {
                cm.allNetworks.mapNotNull { n -> cm.getNetworkCapabilities(n)?.let { n to it } }
                    .filter { (_, c) ->
                        c.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                            !c.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
                    }
                    .maxByOrNull { (_, c) ->
                        (if (c.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) 2 else 0) +
                            (if (c.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) 1 else 0)
                    }?.first
            } catch (e: Exception) { null }
        }

        // Active is not VPN — use it (WiFi or LTE)
        return activeNetwork
    }

    private fun updateUnderlyingNetworks(cm: ConnectivityManager) {
        val activeNetwork = cm.activeNetwork ?: run {
            service.setUnderlyingNetworks(null)
            underlying = null
            return
        }

        // Use findPhysicalNetwork to get WiFi/LTE (not VPN)
        val physicalNetwork = physical()
        if (physicalNetwork == null) {
            if (underlying != null) {
                service.setUnderlyingNetworks(null)
                underlying = null
                host.log("info", "All underlying networks lost")
            }
            return
        }

        if (physicalNetwork == underlying) return
        underlying = physicalNetwork
        service.setUnderlyingNetworks(arrayOf(physicalNetwork))
        host.log("info", "Underlying network set to physical: $physicalNetwork")
    }

    /// [switched] — the physical network changed: before reconnecting compare with the network
    /// we connected on (back on it — the core's sockets are alive, no reconnect needed).
    private fun scheduleNetworkChanged(switched: Boolean = false) {
        // Only reconnect when fully connected — prevents spurious reconnects during the
        // initial startVpn() phase when onAvailable fires right after registration.
        val session = host.connectedAt
        if (session < 0) return
        val plan = policy.schedule(switched, session, System.currentTimeMillis())
        host.log(if (plan.settling) "debug" else "info",
            "Network change: ${if (plan.check) "check" else "reconnect"} scheduled in ${plan.delayMs}ms")
        pending?.let { handler.removeCallbacks(it) }
        val r = Runnable {
            var now: Network? = null
            val reconnect = policy.onFire(plan, { physical().also { now = it } }, connected)
            if (host.connectedAt != session) return@Runnable
            if (!reconnect) {
                host.log("debug", "Network change: still on ${now ?: "no physical network"}, no reconnect")
                return@Runnable
            }
            if (now != null) host.log("info", "Network change: ${connected ?: "unknown"} → $now, reconnecting")
            host.reconnect(session)
        }
        pending = r
        handler.postDelayed(r, plan.delayMs)
    }

    private fun unregister() {
        try {
            val cm = service.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            callback?.let {
                cm.unregisterNetworkCallback(it)
                callback = null
            }
        } catch (e: Exception) {
            // Ignore
        }
    }
}
