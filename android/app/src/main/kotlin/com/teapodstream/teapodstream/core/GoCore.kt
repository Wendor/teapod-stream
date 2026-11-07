package com.teapodstream.teapodstream.core

import android.content.Context
import teapodcore.Teapodcore

/** xray-core (Go) + teapod-tun2socks через локальный SOCKS5. */
object GoCore : Tun2SocksCore() {
    override val kind = CoreKind.GO
    override val logTag = "xray"

    override fun startEngine(config: String, filesDir: String) {
        Teapodcore.initCoreEnv(filesDir, "")
        awaitStart("xray") { Teapodcore.startXray(config, it) }
    }

    override fun stopEngine() = Teapodcore.stopXray()

    override fun measureDelay(url: String) = Teapodcore.measureXrayDelay(url)
    override fun measureOutbound(context: Context, config: String, url: String) =
        Teapodcore.measureOutboundDelay(config, url)
    override fun version(): String = Teapodcore.getXrayVersion()
}
