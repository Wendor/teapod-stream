package com.teapodstream.teapodstream

import android.content.Context

internal object CoreBridge {
    const val ENGINE = "go"
    fun diagnostics() = teapodcore.Teapodcore.getTunDiagnostics()
    fun versions() = mapOf("xray" to teapodcore.Teapodcore.getXrayVersion(), "tun2socks" to "teapod-core (AAR)")
    fun prepare(context: Context): String {
        XrayVpnService.prepareBinaries(context)
        return context.filesDir.absolutePath
    }
    fun activate(context: Context, revision: String): String =
        error("Atomic geodata activation is only used by the Rust build")
}
