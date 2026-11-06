package com.teapodstream.teapodstream.core

import android.content.Context
import teapodcore.Teapodcore

/** sing-box + teapod-tun2socks через локальный SOCKS5 (inbound mixed). */
object BoxCore : Tun2SocksCore() {
    override val kind = CoreKind.BOX
    override val logTag = "sing-box"

    override fun startEngine(config: String, filesDir: String) =
        awaitStart("sing-box") { Teapodcore.startBox(config, filesDir, it) }

    override fun stopEngine() = Teapodcore.stopBox()

    override fun measureDelay(url: String) = Teapodcore.measureBoxDelay(url)
    override fun measureOutbound(context: Context, config: String, url: String) =
        Teapodcore.measureBoxOutboundDelay(config, context.filesDir.absolutePath, url)
    override fun version(): String = Teapodcore.getBoxVersion()

    override fun redirectProxyServer(config: String, redirect: (host: String, port: Int) -> Int?): String? =
        ProxyRedirect.singBox(config, redirect)

    override fun socksCredentials(config: String): Pair<String, String> = SocksCredentials.singBox(config)
}
