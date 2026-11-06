package com.teapodstream.teapodstream.core

import android.content.Context
import android.net.VpnService

enum class CoreKind(val id: String, val versionKey: String) {
    GO("go", "xray-go"), RUST("rust", "xray-rust"), BOX("box", "sing-box");

    companion object {
        fun fromId(id: String?): CoreKind = entries.firstOrNull { it.id == id } ?: GO
    }
}

data class CoreStartParams(
    /** null — proxy-only (без TUN). */
    val tunFd: Int?,
    val mtu: Int,
    val socksPort: Int,
    val socksUser: String,
    val socksPassword: String,
    val allowIcmp: Boolean,
    val blockQuic: Boolean,
    val vpnMode: String,
    /** onlySelected — разрешённые UID, allExcept — исключённые. */
    val allowedUids: Set<Int>,
    /** allExcept: отбрасывать потоки без владельца (тетеринг/обход через tun0). */
    val blockUnowned: Boolean,
)

/** Ядро VPN: всё, что [com.teapodstream.teapodstream.XrayVpnService] делает с движком. */
interface VpnCore {
    val kind: CoreKind

    fun init(service: VpnService, log: (level: String, message: String) -> Unit)

    /** Блокирует до готовности; бросает IllegalStateException с причиной. */
    fun start(config: String, params: CoreStartParams)

    /** Останавливает ядро; суммарно не дольше ~8 с. */
    fun stop()

    fun isTunRunning(): Boolean
    fun activeConnections(): Long
    fun uploadBytes(): Long
    fun downloadBytes(): Long
    fun lastRxActivityMs(): Long
    fun closeAllConnections(): Long
    fun statsLine(): String
    fun diagnostics(): String

    /** XRAYDELAY-проба через запущенное ядро, мс; < 0 — ошибка. */
    fun measureDelay(url: String): Long

    /** Временный инстанс с [config] без TUN: задержка до [url], мс; < 0 — ошибка. */
    fun measureOutbound(context: Context, config: String, url: String): Long

    fun version(): String

    /** Ядро работает на fd TUN напрямую (без dup): stop() — до закрытия fd. */
    val borrowsTunFd: Boolean get() = false

    /** DNS-сервер, который получает TUN-интерфейс. */
    val tunDnsServer: String

    /** MTU TUN-интерфейса с учётом ограничений ядра. */
    fun tunMtu(requested: Int): Int = requested

    /** Подменить сервер outbound'а `proxy` на 127.0.0.1:<порт из [redirect]>; null — не подменён. */
    fun redirectProxyServer(config: String, redirect: (host: String, port: Int) -> Int?): String? =
        ProxyRedirect.xray(config, redirect)

    /** Логин/пароль локального SOCKS из сохранённого конфига (quick-connect, рестарт сервиса). */
    fun socksCredentials(config: String): Pair<String, String> = SocksCredentials.xray(config)
}

object VpnCores {
    /** Ядро текущей (или последней) сессии. */
    @Volatile var active: VpnCore = GoCore

    fun get(kind: CoreKind): VpnCore = when (kind) {
        CoreKind.GO -> GoCore
        CoreKind.RUST -> RustCore
        CoreKind.BOX -> BoxCore
    }

    fun isAvailable(kind: CoreKind): Boolean = try {
        get(kind).version()
        true
    } catch (_: Throwable) {
        false
    }

    fun versions(): Map<String, String> = CoreKind.entries.associate { kind ->
        kind.versionKey to try { get(kind).version() } catch (_: Throwable) { "—" }
    }
}
