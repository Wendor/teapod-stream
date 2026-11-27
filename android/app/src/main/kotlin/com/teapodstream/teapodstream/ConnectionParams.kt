package com.teapodstream.teapodstream

import android.util.Log
import com.teapodstream.teapodstream.core.CoreKind
import com.teapodstream.teapodstream.core.VpnMode
import org.json.JSONArray
import org.json.JSONObject

/** How the heartbeat probes the tunnel. [id] is the stored and Flutter form. */
internal enum class HeartbeatProbe(val id: String) {
    /** HTTP through the session's SOCKS inbound. */
    SOCKS("socks"),
    /** A delay measured inside the core. */
    XRAY_DELAY("xrayDelay"),
    /** No active probes: only tun2socks metrics. */
    PASSIVE("passive"),
}

/** What the heartbeat does about a dead tunnel. [id] is the stored and Flutter form. */
internal enum class HeartbeatAction(val id: String) {
    /** Reconnect to the same server. */
    RECONNECT("reconnect"),
    /** Ask Flutter to pick a live config (the tunnel_dead event). */
    SWITCH_CONFIG("switchConfig"),
}

internal data class ConnectionParams(
    val socksPort: Int,
    val excludedPackages: List<String>,
    val includedPackages: List<String>,
    val vpnMode: VpnMode,
    val ssPrefix: String?,
    val proxyOnly: Boolean,
    val showNotification: Boolean,
    val killSwitch: Boolean,
    val allowIcmp: Boolean,
    val blockQuic: Boolean,
    val ipv6Enabled: Boolean = false,
    val mtu: Int = 1500,
    val heartbeatProbe: HeartbeatProbe = HeartbeatProbe.SOCKS,
    val heartbeatAction: HeartbeatAction = HeartbeatAction.RECONNECT,
    val heartbeatThreshold: Int = 3,
    val heartbeatUrl: String = DEFAULT_HEARTBEAT_URL,
    /// allExcept: let ownerless flows through (tethering) when exclusions are non-empty.
    val allowTethering: Boolean = false,
    /// The session core; quick-reconnect brings up the same core.
    val engine: CoreKind = CoreKind.GO,
) {
    /** The persisted ([QuickConnectStore]) and Intent form; [fromJson] reads it back. */
    fun toJson(): JSONObject = JSONObject().apply {
        put("socksPort", socksPort)
        put("excludedPackages", JSONArray(excludedPackages))
        put("includedPackages", JSONArray(includedPackages))
        put("vpnMode", vpnMode.id)
        if (ssPrefix != null) put("ssPrefix", ssPrefix)
        put("proxyOnly", proxyOnly)
        put("showNotification", showNotification)
        put("killSwitch", killSwitch)
        put("allowIcmp", allowIcmp)
        put("blockQuic", blockQuic)
        put("ipv6Enabled", ipv6Enabled)
        put("allowTethering", allowTethering)
        put("mtu", mtu)
        put("heartbeatProbe", heartbeatProbe.id)
        put("heartbeatAction", heartbeatAction.id)
        put("heartbeatThreshold", heartbeatThreshold)
        put("heartbeatUrl", heartbeatUrl)
        put("engine", engine.id)
    }

    companion object {
        const val DEFAULT_HEARTBEAT_URL = "http://cp.cloudflare.com/generate_204"

        /**
         * The one place for defaults and limits: the file, the service Intent and Flutter's connect arguments all
         * go through here. Throws when `socksPort` or the package lists are missing. A missing choice gets its
         * default; an unknown one (a file written by a newer version) gets the default too, with a logcat line.
         */
        fun fromJson(json: JSONObject): ConnectionParams = ConnectionParams(
            socksPort = json.getInt("socksPort"),
            excludedPackages = json.getJSONArray("excludedPackages").strings(),
            includedPackages = json.getJSONArray("includedPackages").strings(),
            vpnMode = json.choice("vpnMode", VpnMode.entries, VpnMode.ALL_EXCEPT) { it.id },
            ssPrefix = json.optString("ssPrefix").takeIf { it.isNotEmpty() },
            proxyOnly = json.optBoolean("proxyOnly", false),
            showNotification = json.optBoolean("showNotification", true),
            killSwitch = json.optBoolean("killSwitch", false),
            allowIcmp = json.optBoolean("allowIcmp", false),
            blockQuic = json.optBoolean("blockQuic", false),
            ipv6Enabled = json.optBoolean("ipv6Enabled", false),
            allowTethering = json.optBoolean("allowTethering", false),
            mtu = json.optInt("mtu", 1500).coerceIn(576, 9000),
            heartbeatProbe = json.choice("heartbeatProbe", HeartbeatProbe.entries, HeartbeatProbe.SOCKS) { it.id },
            heartbeatAction = json.choice("heartbeatAction", HeartbeatAction.entries, HeartbeatAction.RECONNECT) { it.id },
            heartbeatThreshold = json.optInt("heartbeatThreshold", 3).coerceIn(1, 10),
            heartbeatUrl = json.optString("heartbeatUrl", DEFAULT_HEARTBEAT_URL).ifEmpty { DEFAULT_HEARTBEAT_URL },
            engine = json.choice("engine", CoreKind.entries, CoreKind.GO) { it.id },
        )

        /**
         * Flutter's `connect` / `saveQuickConnect` arguments. Missing `socksPort` and lists get the same defaults
         * the Dart side would send; secrets (`xrayConfig`, SOCKS login) stay out.
         */
        fun fromArgs(args: Map<*, *>): ConnectionParams {
            val json = JSONObject()
            for ((k, v) in args) if (k is String && v != null) json.put(k, JSONObject.wrap(v))
            if (!json.has("socksPort")) json.put("socksPort", 10808)
            if (!json.has("excludedPackages")) json.put("excludedPackages", JSONArray())
            if (!json.has("includedPackages")) json.put("includedPackages", JSONArray())
            return fromJson(json)
        }

        private fun JSONArray.strings() = List(length()) { getString(it) }

        private fun <E> JSONObject.choice(key: String, values: List<E>, default: E, id: (E) -> String): E {
            val raw = optString(key)
            if (raw.isEmpty()) return default
            return values.firstOrNull { id(it) == raw }
                ?: default.also { Log.w("ConnectionParams", "unknown $key '$raw', using '${id(default)}'") }
        }
    }
}
