package com.teapodstream.teapodstream

import com.teapodstream.teapodstream.core.CoreKind
import org.json.JSONArray
import org.json.JSONObject

internal data class ConnectionParams(
    val socksPort: Int,
    val excludedPackages: List<String>,
    val includedPackages: List<String>,
    val vpnMode: String,
    val ssPrefix: String?,
    val proxyOnly: Boolean,
    val showNotification: Boolean,
    val killSwitch: Boolean,
    val allowIcmp: Boolean,
    val blockQuic: Boolean,
    val ipv6Enabled: Boolean = false,
    val mtu: Int = 1500,
    /// "socks" | "xrayDelay" | "passive" — how we probe the tunnel.
    val heartbeatProbe: String = "socks",
    /// "reconnect" — reconnect to the same server, "switchConfig" — ask
    /// Flutter to pick a live config (the tunnel_dead event).
    val heartbeatAction: String = "reconnect",
    val heartbeatThreshold: Int = 3,
    val heartbeatUrl: String = DEFAULT_HEARTBEAT_URL,
    /// allExcept: let ownerless flows through (tethering) when exclusions are non-empty.
    val allowTethering: Boolean = false,
    /// "go" | "rust" | "box" — the session core; quick-reconnect brings up the same core.
    val engine: String = "go",
) {
    /** The persisted ([QuickConnectStore]) and Intent form; [fromJson] reads it back. */
    fun toJson(): JSONObject = JSONObject().apply {
        put("socksPort", socksPort)
        put("excludedPackages", JSONArray(excludedPackages))
        put("includedPackages", JSONArray(includedPackages))
        put("vpnMode", vpnMode)
        if (ssPrefix != null) put("ssPrefix", ssPrefix)
        put("proxyOnly", proxyOnly)
        put("showNotification", showNotification)
        put("killSwitch", killSwitch)
        put("allowIcmp", allowIcmp)
        put("blockQuic", blockQuic)
        put("ipv6Enabled", ipv6Enabled)
        put("allowTethering", allowTethering)
        put("mtu", mtu)
        put("heartbeatProbe", heartbeatProbe)
        put("heartbeatAction", heartbeatAction)
        put("heartbeatThreshold", heartbeatThreshold)
        put("heartbeatUrl", heartbeatUrl)
        put("engine", engine)
    }

    companion object {
        const val DEFAULT_HEARTBEAT_URL = "http://cp.cloudflare.com/generate_204"

        /**
         * The one place for defaults and limits: the file, the service Intent and Flutter's connect arguments all
         * go through here. Throws when `socksPort` or the package lists are missing.
         */
        fun fromJson(json: JSONObject): ConnectionParams = ConnectionParams(
            socksPort = json.getInt("socksPort"),
            excludedPackages = json.getJSONArray("excludedPackages").strings(),
            includedPackages = json.getJSONArray("includedPackages").strings(),
            vpnMode = json.optString("vpnMode", "allExcept").ifEmpty { "allExcept" },
            ssPrefix = json.optString("ssPrefix").takeIf { it.isNotEmpty() },
            proxyOnly = json.optBoolean("proxyOnly", false),
            showNotification = json.optBoolean("showNotification", true),
            killSwitch = json.optBoolean("killSwitch", false),
            allowIcmp = json.optBoolean("allowIcmp", false),
            blockQuic = json.optBoolean("blockQuic", false),
            ipv6Enabled = json.optBoolean("ipv6Enabled", false),
            allowTethering = json.optBoolean("allowTethering", false),
            mtu = json.optInt("mtu", 1500).coerceIn(576, 9000),
            heartbeatProbe = json.optString("heartbeatProbe", "socks").ifEmpty { "socks" },
            heartbeatAction = json.optString("heartbeatAction", "reconnect").ifEmpty { "reconnect" },
            heartbeatThreshold = json.optInt("heartbeatThreshold", 3).coerceIn(1, 10),
            heartbeatUrl = json.optString("heartbeatUrl", DEFAULT_HEARTBEAT_URL).ifEmpty { DEFAULT_HEARTBEAT_URL },
            engine = CoreKind.fromId(json.optString("engine")).id,
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
    }
}
