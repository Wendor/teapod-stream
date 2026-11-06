package com.teapodstream.teapodstream.core

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ProxyRedirectTest {
    private val xrayConfig = """{"outbounds":[{"tag":"direct","protocol":"freedom"},
        {"tag":"proxy","protocol":"shadowsocks","settings":{"servers":[{"address":"ss.example.com","port":8388}]}}]}"""
    private val boxConfig = """{"outbounds":[{"type":"direct","tag":"direct"},
        {"type":"shadowsocks","tag":"proxy","server":"ss.example.com","server_port":8388}]}"""

    private fun proxy(json: String, isBox: Boolean): JSONObject {
        val outbounds = JSONObject(json).getJSONArray("outbounds")
        return (0 until outbounds.length()).map { outbounds.getJSONObject(it) }.first { it.optString("tag") == "proxy" }
            .let { if (isBox) it else it.getJSONObject("settings").getJSONArray("servers").getJSONObject(0) }
    }

    @Test
    fun `xray replaces first server of proxy outbound`() {
        var seen: Pair<String, Int>? = null
        val result = ProxyRedirect.xray(xrayConfig) { host, port -> seen = host to port; 40000 }!!
        assertEquals("ss.example.com" to 8388, seen)
        val server = proxy(result, isBox = false)
        assertEquals("127.0.0.1", server.getString("address"))
        assertEquals(40000, server.getInt("port"))
    }

    @Test
    fun `singBox replaces server of proxy outbound`() {
        var seen: Pair<String, Int>? = null
        val result = ProxyRedirect.singBox(boxConfig) { host, port -> seen = host to port; 40001 }!!
        assertEquals("ss.example.com" to 8388, seen)
        val out = proxy(result, isBox = true)
        assertEquals("127.0.0.1", out.getString("server"))
        assertEquals(40001, out.getInt("server_port"))
    }

    @Test
    fun `returns null without proxy outbound`() {
        assertNull(ProxyRedirect.xray("""{"outbounds":[{"tag":"direct"}]}""") { _, _ -> 1 })
        assertNull(ProxyRedirect.singBox("""{"outbounds":[{"tag":"direct"}]}""") { _, _ -> 1 })
    }

    @Test
    fun `returns null when redirect returns null`() {
        assertNull(ProxyRedirect.xray(xrayConfig) { _, _ -> null })
        assertNull(ProxyRedirect.singBox(boxConfig) { _, _ -> null })
    }
}
