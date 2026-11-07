package com.teapodstream.teapodstream.core

import org.json.JSONArray
import org.json.JSONObject

/** Логин/пароль SOCKS-inbound `socks-in` из сохранённого конфига ядра; ("", "") — нет. */
object SocksCredentials {
    private const val INBOUND_TAG = "socks-in"

    /** xray: `inbounds[tag=socks-in].settings.accounts[0].user/pass`. */
    fun xray(config: String): Pair<String, String> = first(config) { inbound ->
        inbound.optJSONObject("settings")?.optJSONArray("accounts")?.optJSONObject(0)
            ?.let { it.optString("user", "") to it.optString("pass", "") }
    }

    /** sing-box: `inbounds[tag=socks-in].users[0].username/password`. */
    fun singBox(config: String): Pair<String, String> = first(config) { inbound ->
        inbound.optJSONArray("users")?.optJSONObject(0)
            ?.let { it.optString("username", "") to it.optString("password", "") }
    }

    private fun first(config: String, read: (JSONObject) -> Pair<String, String>?): Pair<String, String> = try {
        val inbounds = JSONObject(config).optJSONArray("inbounds") ?: JSONArray()
        (0 until inbounds.length()).map { inbounds.getJSONObject(it) }
            .firstOrNull { it.optString("tag") == INBOUND_TAG }?.let(read) ?: ("" to "")
    } catch (_: Exception) {
        "" to ""
    }
}
