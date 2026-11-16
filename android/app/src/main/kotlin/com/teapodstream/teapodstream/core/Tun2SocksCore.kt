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

/** A core behind teapod-tun2socks: the engine listens on a local SOCKS5, tun2socks reads TUN. */
abstract class Tun2SocksCore : VpnCore {
    override val tunDnsServer = "1.1.1.1"

    /** Prefix of the engine's runtime logs: `[xray]`, `[sing-box]`. */
    protected abstract val logTag: String

    /** Starts the engine with [config]; blocks until ready. */
    protected abstract fun startEngine(config: String, filesDir: String)

    /** Stops the engine (may hang, called with a deadline). */
    protected abstract fun stopEngine()

    protected var log: (String, String) -> Unit = { _, _ -> }
        private set
    private var connectivity: ConnectivityManager? = null
    private var filesDir: String = ""

    override fun init(service: VpnService, log: (level: String, message: String) -> Unit) {
        this.log = log
        connectivity = service.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        filesDir = service.filesDir.absolutePath
        Teapodcore.registerVpnProtector(object : VpnProtector {
            override fun protect(fd: Long): Boolean = service.protect(fd.toInt())
        })
        // Engine runtime logs (dial errors, access log) — to vpn_log.txt.
        // Info/access → "debug": to the file, but not to the release build's UI.
        Teapodcore.registerLogListener(object : LogListener {
            override fun onLog(message: String) {
                val level = when {
                    message.contains("[Error]") -> "error"
                    message.contains("[Warning]") -> "warning"
                    else -> "debug"
                }
                log(level, "[$logTag] $message")
            }
        })
    }

    override fun start(config: String, params: CoreStartParams) {
        startEngine(config, filesDir)
        log("info", "$logTag started")
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

    /** Waits for the engine start callback (up to 30 s); [launch] receives the callback. */
    protected fun awaitStart(name: String, launch: (XrayCallback) -> Unit) {
        val latch = CountDownLatch(1)
        val failed = AtomicBoolean(false)
        launch(object : XrayCallback {
            override fun onStatus(status: Long, message: String) {
                log("info", "[$logTag] $message")
                if (status != 0L) failed.set(true)
                latch.countDown()
            }
        })
        if (!latch.await(30, TimeUnit.SECONDS)) throw IllegalStateException("$name start timeout (30s)")
        if (failed.get()) throw IllegalStateException("$name failed to start")
    }

    /**
     * [blockUnowned] — drop flows without a visible owner (uid=-1) in allExcept.
     * An excluded app can bind a socket to TUN (SO_BINDTODEVICE), and
     * getConnectionOwnerUid() returns INVALID_UID — such a bypass is indistinguishable from
     * tethering and is blocked when there are exclusions unless tethering is allowed.
     */
    private fun buildTunValidator(allowedUids: Set<Int>, vpnMode: String, blockUnowned: Boolean): TunValidator? {
        val cm = connectivity ?: return null
        val policy = TunOwnerPolicy(vpnMode == "onlySelected", allowedUids, blockUnowned, tunDnsServer)
        // "EXCEPT" without blocking ownerless flows rejects nobody: null —
        // tun2socks lets everything through itself, without binder IPC per connection.
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
        log("info", "Stopping $logTag")
        // Stopping the engine may hang while goroutines drain connections.
        runWithDeadline("stop $logTag", 3000) { stopEngine() }
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
}
