package com.teapodstream.teapodstream

import android.content.Context

internal object CoreBridge {
    const val ENGINE = "rust"
    fun diagnostics() = RustCore.diagnostics()
    fun versions() = mapOf("xray" to RustCore.VERSION, "tun2socks" to "Rust direct TUN")
    fun prepare(context: Context) = GeodataStore.directory(context).absolutePath
    fun activate(context: Context, revision: String): String {
        GeodataStore.activate(context, revision)
        return prepare(context)
    }
    // Замер кандидата для switchConfig: временный инстанс xray-rust без TUN с
    // probe-конфигом кандидата (RustConfigBuilder.buildProbeJson). -1 — не ответил.
    fun measureOutboundDelay(context: Context, config: String, url: String): Long =
        RustCore.measureCandidate(context, config, url)
}
