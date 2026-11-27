package com.teapodstream.teapodstream.core

import org.junit.Assert.assertEquals
import org.junit.Test

class SocksCredentialsTest {
    @Test
    fun `xray socks-in accounts`() {
        val config = """{"inbounds":[{"tag":"socks-in","protocol":"socks",
            "settings":{"auth":"password","accounts":[{"user":"u1","pass":"p1"}]}}]}"""
        assertEquals("u1" to "p1", SocksCredentials.xray(config))
    }

    @Test
    fun `sing-box mixed users`() {
        val config = """{"inbounds":[{"type":"mixed","tag":"socks-in","listen":"127.0.0.1",
            "users":[{"username":"u2","password":"p2"}]}]}"""
        assertEquals("u2" to "p2", SocksCredentials.singBox(config))
        assertEquals("u2" to "p2", BoxCore.socksCredentials(config))
    }

    @Test
    fun `a managed config's socks inbound is found by its protocol`() {
        val config = """{"inbounds":[{"tag":"tun","protocol":"dokodemo-door"},{"tag":"socks","protocol":"socks",
            "settings":{"auth":"password","accounts":[{"user":"m1","pass":"mp"}]}}]}"""
        assertEquals("m1" to "mp", SocksCredentials.xray(config))
        val box = """{"inbounds":[{"type":"tun","tag":"tun-in"},{"type":"socks","tag":"in",
            "users":[{"username":"m2","password":"mp2"}]}]}"""
        assertEquals("m2" to "mp2", SocksCredentials.singBox(box))
    }

    @Test
    fun `the socks-in tag wins over another socks inbound`() {
        val config = """{"inbounds":[{"tag":"other","protocol":"socks","settings":{"accounts":[{"user":"x","pass":"x"}]}},
            {"tag":"socks-in","protocol":"socks","settings":{"accounts":[{"user":"u","pass":"p"}]}}]}"""
        assertEquals("u" to "p", SocksCredentials.xray(config))
    }

    @Test
    fun `no auth or broken json gives empty credentials`() {
        assertEquals("" to "", SocksCredentials.xray("""{"inbounds":[{"tag":"socks-in","settings":{}}]}"""))
        assertEquals("" to "", SocksCredentials.singBox("""{"inbounds":[{"tag":"socks-in"}]}"""))
        assertEquals("" to "", SocksCredentials.singBox("not json"))
    }
}
