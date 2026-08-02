package com.teapodstream.teapodstream

import java.io.File

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
    /// "reconnect" — переподключиться к тому же серверу, "urltest" — попросить
    /// Flutter подобрать живой конфиг (событие tunnel_dead).
    val heartbeatAction: String = "reconnect",
    val heartbeatThreshold: Int = 3,
) {
    fun save(dir: File, log: (String, String) -> Unit) {
        try {
            val json = org.json.JSONObject().apply {
                put("socksPort", socksPort)
                put("excludedPackages", org.json.JSONArray(excludedPackages))
                put("includedPackages", org.json.JSONArray(includedPackages))
                put("vpnMode", vpnMode)
                if (ssPrefix != null) put("ssPrefix", ssPrefix)
                put("proxyOnly", proxyOnly)
                put("showNotification", showNotification)
                put("killSwitch", killSwitch)
                put("allowIcmp", allowIcmp)
                put("blockQuic", blockQuic)
                put("ipv6Enabled", ipv6Enabled)
                put("mtu", mtu)
                put("heartbeatAction", heartbeatAction)
                put("heartbeatThreshold", heartbeatThreshold)
            }
            File(dir, "last_connection_meta.json").writeText(json.toString())
        } catch (e: Exception) {
            log("warning", "Failed to save connection params: ${e.message}")
        }
    }

    companion object {
        fun load(dir: File): ConnectionParams? = try {
            val json = org.json.JSONObject(File(dir, "last_connection_meta.json").readText())
            val excluded = json.getJSONArray("excludedPackages")
                .let { arr -> List(arr.length()) { arr.getString(it) } }
            val included = json.getJSONArray("includedPackages")
                .let { arr -> List(arr.length()) { arr.getString(it) } }
            ConnectionParams(
                socksPort = json.getInt("socksPort"),
                excludedPackages = excluded,
                includedPackages = included,
                vpnMode = json.optString("vpnMode", "allExcept"),
                ssPrefix = json.optString("ssPrefix").takeIf { it.isNotEmpty() },
                proxyOnly = json.optBoolean("proxyOnly", false),
                showNotification = json.optBoolean("showNotification", true),
                killSwitch = json.optBoolean("killSwitch", false),
                allowIcmp = json.optBoolean("allowIcmp", false),
                blockQuic = json.optBoolean("blockQuic", false),
                ipv6Enabled = json.optBoolean("ipv6Enabled", false),
                mtu = json.optInt("mtu", 1500).coerceIn(576, 9000),
                heartbeatAction = json.optString("heartbeatAction", "reconnect"),
                heartbeatThreshold = json.optInt("heartbeatThreshold", 3).coerceIn(1, 10),
            )
        } catch (_: Exception) {
            null
        }
    }
}
