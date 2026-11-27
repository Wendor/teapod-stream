package com.teapodstream.teapodstream.core

import org.json.JSONArray
import org.json.JSONObject

/**
 * Login/password of the SOCKS inbound in the saved core config — the only place the quick start reads it from;
 * ("", "") — none. The inbound tagged `socks-in`, else the first SOCKS one: a managed config keeps the server's tag
 * (or `socks`) for it.
 */
object SocksCredentials {
    private const val INBOUND_TAG = "socks-in"

    /** xray: `inbounds[socks].settings.accounts[0].user/pass`. */
    fun xray(config: String): Pair<String, String> = first(config, { it.optString("protocol") == "socks" }) { inbound ->
        inbound.optJSONObject("settings")?.optJSONArray("accounts")?.optJSONObject(0)
            ?.let { it.optString("user", "") to it.optString("pass", "") }
    }

    /** sing-box: `inbounds[socks].users[0].username/password`. */
    fun singBox(config: String): Pair<String, String> =
        first(config, { it.optString("type") in setOf("socks", "mixed") }) { inbound ->
        inbound.optJSONArray("users")?.optJSONObject(0)
            ?.let { it.optString("username", "") to it.optString("password", "") }
    }

    private fun first(
        config: String,
        isSocks: (JSONObject) -> Boolean,
        read: (JSONObject) -> Pair<String, String>?,
    ): Pair<String, String> = try {
        val inbounds = JSONObject(config).optJSONArray("inbounds") ?: JSONArray()
        val all = (0 until inbounds.length()).mapNotNull { inbounds.optJSONObject(it) }
        (all.firstOrNull { it.optString("tag") == INBOUND_TAG } ?: all.firstOrNull(isSocks))?.let(read) ?: ("" to "")
    } catch (_: Exception) {
        "" to ""
    }
}
