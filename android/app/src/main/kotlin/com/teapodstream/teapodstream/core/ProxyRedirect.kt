package com.teapodstream.teapodstream.core

import org.json.JSONObject

/**
 * Подмена адреса сервера outbound'а `proxy` на локальный (Shadowsocks `?prefix=`:
 * трафик идёт через [com.teapodstream.teapodstream.PrefixTcpProxy]).
 * [redirect] получает реальный адрес и возвращает локальный порт (null — отказ).
 */
object ProxyRedirect {
    private const val PROXY_TAG = "proxy"
    private const val LOOPBACK = "127.0.0.1"

    /** Конфиг формата xray: `outbounds[tag=proxy].settings.servers[0]`. */
    fun xray(config: String, redirect: (host: String, port: Int) -> Int?): String? {
        val json = JSONObject(config)
        val server = proxyOutbound(json)?.optJSONObject("settings")
            ?.optJSONArray("servers")?.optJSONObject(0) ?: return null
        val port = redirect(server.getString("address"), server.getInt("port")) ?: return null
        server.put("address", LOOPBACK)
        server.put("port", port)
        return json.toString()
    }

    /** Конфиг sing-box: `outbounds[tag=proxy].server/server_port`. */
    fun singBox(config: String, redirect: (host: String, port: Int) -> Int?): String? {
        val json = JSONObject(config)
        val outbound = proxyOutbound(json)?.takeIf { it.has("server") } ?: return null
        val port = redirect(outbound.getString("server"), outbound.getInt("server_port")) ?: return null
        outbound.put("server", LOOPBACK)
        outbound.put("server_port", port)
        return json.toString()
    }

    private fun proxyOutbound(json: JSONObject): JSONObject? {
        val outbounds = json.optJSONArray("outbounds") ?: return null
        return (0 until outbounds.length()).map { outbounds.getJSONObject(it) }
            .firstOrNull { it.optString("tag") == PROXY_TAG }
    }
}
