package com.teapodstream.teapodstream.core

import android.content.Context
import android.net.ConnectivityManager
import android.net.VpnService
import java.net.InetSocketAddress
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import teapodcore.LogListener
import teapodcore.Teapodcore
import teapodcore.TunValidator
import teapodcore.VpnProtector
import teapodcore.XrayCallback

/** xray-core (Go) + teapod-tun2socks через локальный SOCKS5. */
object GoCore : VpnCore {
    override val kind = CoreKind.GO
    override val tunDnsServer = "1.1.1.1"

    private var log: (String, String) -> Unit = { _, _ -> }
    private var connectivity: ConnectivityManager? = null
    private var filesDir: String = ""

    override fun init(service: VpnService, log: (level: String, message: String) -> Unit) {
        this.log = log
        connectivity = service.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        filesDir = service.filesDir.absolutePath
        Teapodcore.registerVpnProtector(object : VpnProtector {
            override fun protect(fd: Long): Boolean = service.protect(fd.toInt())
        })
        // Runtime-логи xray-core (ошибки дозвона, access log) — в vpn_log.txt.
        // Info/access → "debug": в файл, но не в UI release-сборки.
        Teapodcore.registerLogListener(object : LogListener {
            override fun onLog(message: String) {
                val level = when {
                    message.contains("[Error]") -> "error"
                    message.contains("[Warning]") -> "warning"
                    else -> "debug"
                }
                log(level, "[xray] $message")
            }
        })
    }

    override fun start(config: String, params: CoreStartParams) {
        Teapodcore.initCoreEnv(filesDir, "")
        startXrayAndWait(config)
        log("info", "xray started")
        val tunFd = params.tunFd ?: return
        log("info", "Starting tun2socks: mode=${params.vpnMode} uids=${params.allowedUids.size} blockUnowned=${params.blockUnowned}")
        val err = Teapodcore.startTun2Socks(
            tunFd.toLong(),
            params.mtu.toLong(),
            params.socksPort.toLong(),
            params.socksUser,
            params.socksPassword,
            params.allowIcmp,
            params.blockQuic,
            buildTunValidator(params.allowedUids, params.vpnMode, params.blockUnowned),
        )
        if (err.isNotEmpty()) throw IllegalStateException("tun2socks: $err")
        log("info", "tun2socks started successfully")
    }

    private fun startXrayAndWait(config: String) {
        val latch = CountDownLatch(1)
        val failed = AtomicBoolean(false)
        Teapodcore.startXray(config, object : XrayCallback {
            override fun onStatus(status: Long, message: String) {
                log("info", "[xray] $message")
                if (status != 0L) failed.set(true)
                latch.countDown()
            }
        })
        if (!latch.await(30, TimeUnit.SECONDS)) throw IllegalStateException("xray start timeout (30s)")
        if (failed.get()) throw IllegalStateException("xray failed to start")
    }

    /**
     * [blockUnowned] — отбрасывать потоки без видимого владельца (uid=-1) в allExcept.
     * Исключённое приложение может привязать сокет к TUN (SO_BINDTODEVICE), и
     * getConnectionOwnerUid() вернёт INVALID_UID — такой обход неотличим от
     * тетеринга и блокируется при наличии исключений, если тетеринг не разрешён.
     */
    private fun buildTunValidator(allowedUids: Set<Int>, vpnMode: String, blockUnowned: Boolean): TunValidator? {
        val cm = connectivity ?: return null
        val policy = TunOwnerPolicy(vpnMode == "onlySelected", allowedUids, blockUnowned, tunDnsServer)
        // «КРОМЕ» без блокировки бесхозных потоков никого не отвергает: null —
        // tun2socks пропускает всё сам, без binder-IPC на каждое соединение.
        if (!policy.needsAdmission) return null
        return object : TunValidator {
            override fun onValidate(srcIP: String, srcPort: Long, dstIP: String, dstPort: Long, protocol: Long) =
                policy.admitFlow(dstIP, dstPort.toInt()) {
                    cm.getConnectionOwnerUid(
                        protocol.toInt(),
                        InetSocketAddress(srcIP, srcPort.toInt()),
                        InetSocketAddress(dstIP, dstPort.toInt()),
                    )
                }
        }
    }

    override fun stop() {
        log("info", "Stopping tun2socks")
        runWithDeadline("stopTun2Socks", 5000) { Teapodcore.stopTun2Socks() }
        log("info", "Stopping xray")
        // stopXray() может висеть, пока горутины дренируют соединения.
        runWithDeadline("stopXray", 3000) { Teapodcore.stopXray() }
    }

    private fun runWithDeadline(name: String, timeoutMs: Long, block: () -> Unit) {
        val thread = Thread {
            try { block() } catch (e: Exception) { log("warning", "$name failed: ${e.message}") }
        }
        thread.isDaemon = true
        thread.start()
        try {
            thread.join(timeoutMs)
            if (thread.isAlive) log("warning", "$name timed out after ${timeoutMs / 1000}s, forcing continuation")
            else log("info", "stopVpn: $name done")
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
    }

    override fun isTunRunning() = Teapodcore.isTunRunning()
    override fun activeConnections() = Teapodcore.tunActiveConnections()
    override fun uploadBytes() = Teapodcore.getTunUploadBytes()
    override fun downloadBytes() = Teapodcore.getTunDownloadBytes()
    override fun lastRxActivityMs() = Teapodcore.getTunLastRxActivityMs()
    override fun closeAllConnections() = Teapodcore.forceTunCloseAllConnections()
    override fun statsLine(): String = Teapodcore.getTunStatsLine()
    override fun diagnostics(): String = Teapodcore.getTunDiagnostics()
    override fun measureDelay(url: String) = Teapodcore.measureXrayDelay(url)
    override fun measureOutbound(context: Context, config: String, url: String) =
        Teapodcore.measureOutboundDelay(config, url)
    override fun version(): String = Teapodcore.getXrayVersion()
}
