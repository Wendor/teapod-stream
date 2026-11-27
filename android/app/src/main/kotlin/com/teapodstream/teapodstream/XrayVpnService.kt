package com.teapodstream.teapodstream

import android.app.Notification
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.system.OsConstants
import java.io.File
import com.teapodstream.teapodstream.core.CoreKind
import com.teapodstream.teapodstream.core.CoreStartParams
import com.teapodstream.teapodstream.core.VpnCore
import com.teapodstream.teapodstream.core.VpnCores
import com.teapodstream.teapodstream.core.VpnMode
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.Socket
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

class XrayVpnService : VpnService() {

    companion object {
        init {
            System.loadLibrary("vpnhelper")
        }

        @JvmStatic external fun nativeSetMaxFds(maxFds: Int): Int
        const val ACTION_CONNECT = "com.teapodstream.CONNECT"
        const val ACTION_DISCONNECT = "com.teapodstream.DISCONNECT"
        const val ACTION_CONNECT_QUICK = "com.teapodstream.CONNECT_QUICK" // reconnect from notification
        const val ACTION_ITEST_DROP = "com.teapodstream.ITEST_DROP" // itest: unexpected drop
        const val EXTRA_XRAY_CONFIG = "xray_config"
        const val EXTRA_SOCKS_USER = "socks_user"
        const val EXTRA_SOCKS_PASSWORD = "socks_password"
        /** [ConnectionParams.toJson] of the session: everything but the config and the SOCKS login. */
        const val EXTRA_PARAMS = "params"
        /** Flutter's connect attempt (> 0); state events of the session it starts carry it back. */
        const val EXTRA_ATTEMPT = "attempt"
        const val EXTRA_CONFIG_NAME = "config_name"              // config name for the tile

        /** Counts session starts, each after its state is published and before its quick-connect save: Flutter's
         *  quick-connect write checked before a start is stale ([QuickConnectRequests]). */
        val sessionStarts = java.util.concurrent.atomic.AtomicLong()

        private val session = AtomicReference(SessionSnapshot())
        private val publishLock = Any()

        /** The current session; changed only by [publish]. Reading it has no side effects. */
        val snapshot: SessionSnapshot get() = session.get()

        /**
         * Tasker/Anubis integration: [VpnCommandReceiver] commands and the STATE_CHANGED
         * broadcast. Both are visible to any app (turn the VPN off, watch it),
         * so they work only when the option is explicitly enabled (off by default).
         */
        fun automationEnabled(context: android.content.Context): Boolean =
            context.getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                .getBoolean("flutter.automation_enabled", false)

        const val PREFS_NAME = "vpn_prefs"

        private const val CONNECTIVITY_CHECK_HOST = "8.8.8.8"
        private const val STOP_THREAD_TIMEOUT_MS = 5_000L
        private const val RECONNECT_DEBOUNCE_MS = 2_000L
        // Failed CONNECT_QUICK reconnects are retried with linear backoff instead of
        // silently leaving the VPN off (and, with kill switch, traffic leaking).
        private const val MAX_RECONNECT_ATTEMPTS = 3
        private const val RECONNECT_RETRY_BASE_MS = 5_000L


        /** Extracts the bundled geoip.dat / geosite.dat that are missing from filesDir. False when one failed: its
         *  partial copy is removed, so the next call tries again instead of keeping a truncated file. Synchronized:
         *  the channel (on the I/O pool) and startVpn call it, and a second copy of the same file would truncate the
         *  first or delete it on failure. */
        @Synchronized
        fun prepareBinaries(context: android.content.Context): Boolean {
            val filesDir = context.filesDir
            val assets = context.assets
            var ok = true
            for (name in listOf("geoip.dat", "geosite.dat")) {
                val file = java.io.File(filesDir, name)
                if (file.exists()) continue
                try {
                    val input = try { assets.open("binaries/$name") } catch (e: Exception) { assets.open("flutter_assets/assets/binaries/$name") }
                    input.use { i -> file.outputStream().use { o -> i.copyTo(o) } }
                } catch (e: Exception) {
                    file.delete()
                    ok = false
                }
            }
            return ok
        }
    }

    private var tunInterface: ParcelFileDescriptor? = null
    private var statsThread: Thread? = null
    private val isRunning = AtomicBoolean(false)
    @Volatile private var lastConnectedMs: Long = 0L
    /** The desired state the running session was started for: a reconnect replaces only it. */
    @Volatile private var connectedDesired: Desired.On? = null
    /**
     * Flutter's connect attempt the published states are tagged with ([SessionSnapshot.attempt]): set by a connect
     * or a disconnect before it stops or starts a session, 0 for a quick start.
     */
    @Volatile private var sessionAttempt: Long = 0
    // TUN mode (not proxy-only): the stats thread checks that tun2socks still runs.
    @Volatile private var tunModeActive = false
    private var prefixProxy: PrefixTcpProxy? = null
    private var showNotification: Boolean
        // Before parameters are loaded (ACTION_DISCONNECT in a fresh process) — from disk.
        get() = ServiceNotifications.enabled(this)
        set(value) { ServiceNotifications.setEnabled(value) }
    private val screen: ScreenWatcher = ScreenWatcher(this, ::log,
        onScreenOn = {
            // Notification updates are suppressed while the screen is off —
            // refresh once so the shade shows current speeds immediately.
            if (isRunning.get() && snapshot.state == SessionState.CONNECTED) {
                notifications.refresh(SessionStats.uploadSpeed, SessionStats.downloadSpeed, screenOn = true)
            }
        },
        onWake = { heartbeat.probeOnWake() },
    )
    private val screenOn: Boolean get() = screen.screenOn
    private val notifications: ServiceNotifications = ServiceNotifications(this, ::log)
    private val network = NetworkWatcher(this, object : NetworkWatcher.Host {
        override val connectedAt get() = if (snapshot.state == SessionState.CONNECTED) lastConnectedMs else -1L
        override val tunRunning get() = tunModeActive && isRunning.get()
        override val core get() = this@XrayVpnService.core
        override fun reconnect(session: Long) = reconnectInternal(session)
        override fun log(level: String, message: String) = this@XrayVpnService.log(level, message)
    })
    private val heartbeat: Heartbeat = Heartbeat(object : Heartbeat.Host {
        override val running get() = isRunning.get()
        override val tunMode get() = tunModeActive
        override val screenOn get() = this@XrayVpnService.screenOn
        override val deviceIdle get() = screen.deviceIdle
        override val core get() = this@XrayVpnService.core
        override val params get() = this@XrayVpnService.params
        override val socks get() = session.get().let { Heartbeat.Socks(it.socksPort, it.socksUser, it.socksPassword) }
        override val connectedAt get() = lastConnectedMs
        override fun directInternet() = hasDirectInternet()
        override fun reconnect(session: Long?) = reconnectInternal(session)
        override fun log(level: String, message: String) = this@XrayVpnService.log(level, message)
    })
    private var killSwitchEnabled = false
    @Volatile private var allowIcmpEnabled = true
    @Volatile private var blockQuicEnabled = false
    private var proxyOnlyMode = false
    // The one desired session state: commands, revoke, reconnects and retries replace it, one thread brings the
    // session to it. A start that ends off (failed, cancelled) is checked once its run has finished: while it runs it
    // holds the service.
    private val reconciler: SessionReconciler = SessionReconciler(object : SessionDriver {
        override fun running() = isRunning.get()
        override fun sinkHeld() = tunInterface != null
        override fun own(desired: Desired) { sessionAttempt = desired.tag }
        override fun stop(forNext: Boolean) {
            // Decided by what is wanted as the stop begins: an off replaced by a connect meanwhile keeps the sink.
            val next = forNext || reconciler.desired is Desired.On
            stopVpn(explicit = !next, reconnecting = next)
        }
        override fun closeSink() = closeTunSink()
        override fun start(on: Desired.On): Boolean = startSession(on)
        override fun settled(desired: Desired) {
            // The answer Flutter waits for: an off state tagged with the disconnect's attempt.
            if (desired is Desired.Off) {
                sessionAttempt = desired.attempt
                reportOff(desired)
            }
        }
        override fun afterRun() {
            if (snapshot.state.isOff) mainHandler.post(::stopIfIdle)
        }
    })
    /** The startId of the last onStartCommand (main thread): see [stopIfIdle]. */
    private var lastStartId = 0
    /** Set in onDestroy (main thread): reports posted later belong to a stopped instance. */
    private var destroyed = false
    private val store by lazy { QuickConnectStore(filesDir) }
    /** The parameters [tunInterface] was built with: a reconnect reuses the fd only for the same ones. */
    @Volatile private var tunParams: ConnectionParams? = null

    /** The parameters of the session being started or run ([useParams]); null before the first start. */
    @Volatile private var params: ConnectionParams? = null
    private val allowTethering get() = params?.allowTethering ?: false
    private val mainHandler = Handler(Looper.getMainLooper())
    private val reconnectAttempts = AtomicInteger(0)

    @Volatile private var tunMtu = 1500
    // Core of the current session: fixed in startVpn after the CAS so that a core change
    // by a new connect doesn't redirect stop/heartbeat/stats to another core.
    // Before the first start here: the last session's core in this process.
    @Volatile private var sessionCore: VpnCore = VpnCores.get(snapshot.core)
    private val core: VpnCore get() = sessionCore

    override fun onCreate() {
        super.onCreate()
        VpnTileService.migrateLegacyConfigName(this)
        ServiceLog.enabled = getSharedPreferences(PREFS_NAME, MODE_PRIVATE).getBoolean(ServiceLog.PREF_ENABLED, true)
        screen.register()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        lastStartId = startId
        if (intent?.action == ACTION_ITEST_DROP) {
            // itest build only: a drop along the failure path (explicit=false), as on
            // an unexpected tunnel death — the kill switch keeps the TUN sink.
            if (!BuildConfig.ITEST || !isRunning.get()) {
                if (!isRunning.get()) stopSelf(startId)
                return START_NOT_STICKY
            }
            log("warning", "itest: simulated unexpected drop")
            Thread { stopVpn(resultState = SessionState.ERROR, explicit = false) }.start()
            return START_STICKY
        }
        when (intent?.action) {
            ACTION_DISCONNECT -> {
                // Arrived via startForegroundService (Tasker, MainActivity) into a fresh
                // process — without startForeground() the system kills the service after 5 s.
                if (!isRunning.get()) notifications.foreground(connecting = false)
                setUserOff(true)
                turnOff()
                return START_STICKY
            }
            ACTION_CONNECT -> {
                val xrayConfig = intent.getStringExtra(EXTRA_XRAY_CONFIG) ?: ""
                val socksUser = intent.getStringExtra(EXTRA_SOCKS_USER) ?: ""
                val socksPassword = intent.getStringExtra(EXTRA_SOCKS_PASSWORD) ?: ""
                val attempt = intent.getLongExtra(EXTRA_ATTEMPT, 0)
                val params = try {
                    ConnectionParams.fromJson(org.json.JSONObject(intent.getStringExtra(EXTRA_PARAMS) ?: ""))
                } catch (e: Exception) {
                    log("error", "CONNECT without valid parameters: ${e.message}")
                    return START_NOT_STICKY
                }
                showNotificationFor(params)
                setUserOff(false)
                reconnectAttempts.set(0)
                notifications.foreground()
                // The tile's name, like the params, config and login for a quick start, is stored once the session
                // runs with them (startVpn): a cancelled connect leaves the tile with what it will connect.
                val request = StartRequest(
                    xrayConfig, params, socksUser, socksPassword, attempt, reconnect = false,
                    configName = intent.getStringExtra(EXTRA_CONFIG_NAME),
                )
                // Changing server/settings on a live tunnel: the old TUN stays a sink
                // until the new one's establish() — no explicit disconnect and no leak window.
                reconciler.set(Desired.On(request, reconciler.newId()))
                return START_STICKY
            }
            ACTION_CONNECT_QUICK -> {
                // The parameters before ensureForeground, so the right notification type (full or minimal) shows
                // from the start.
                val request = quickStartRequest()
                (request?.params ?: store.params())?.let(::showNotificationFor)
                if (reconciler.desired is Desired.On && (isRunning.get() || reconciler.busy())) {
                    // A session is running or being started — bail here instead so the
                    // state isn't left stuck at "reconnecting" over a live tunnel.
                    // startForegroundService requires startForeground — repeat it with
                    // the live session's notification: "Connecting…" would hang until the speed changes.
                    notifications.foreground(connected = snapshot.state == SessionState.CONNECTED)
                    log("info", "CONNECT_QUICK ignored: VPN already running")
                    return START_STICKY
                }
                notifications.foreground()
                when {
                    // Nothing stored to start (a failed save may have removed it): the session holding the sink, if
                    // any, decides whether it stays.
                    request == null -> abortQuickConnect(killSwitchEnabled)
                    // Permission revoked — the system already disconnected our TUN, nothing to block with.
                    !request.params.proxyOnly && VpnService.prepare(this) != null -> abortQuickConnect(killSwitch = false)
                    else -> {
                        setUserOff(false)
                        setState(SessionState.RECONNECTING, attempt = 0)
                        startQuick(request)
                    }
                }
                return START_STICKY
            }
        }
        // Service restarted by Android after being killed, or started by always-on VPN.
        // The parameters before ensureForeground (as in CONNECT_QUICK).
        val request = quickStartRequest()
        (request?.params ?: store.params())?.let(::showNotificationFor)
        notifications.foreground()
        // Auto-connect unless the user turned the VPN off (the flag file: the choice survives a process restart).
        if (request != null && !store.userOff() && reconciler.desired !is Desired.On &&
            (request.params.proxyOnly || VpnService.prepare(this) == null)
        ) {
            setState(SessionState.RECONNECTING, attempt = 0)
            startQuick(request)
            return START_STICKY
        }
        // Nothing to start: the service doesn't stay in the foreground for an off VPN.
        stopIfIdle()
        return START_STICKY
    }

    /** The session's parameters: the fields derived from them follow ([showNotification], the heartbeat's settings, …). */
    private fun useParams(p: ConnectionParams) {
        params = p
        showNotification = p.showNotification
    }

    /**
     * Before ensureForeground: the notification type (full or minimal) of the session about to start, so the right one
     * shows from the start. A running session keeps its own until [startVpn] replaces it.
     */
    private fun showNotificationFor(p: ConnectionParams) {
        if (!isRunning.get()) showNotification = p.showNotification
    }

    /**
     * The VPN off: `disconnecting` at once, then [Desired.Off] tagged with the last connect received (a connect Flutter
     * still waits for, cancelled from the notification or the tile, gets its answer). A stop stuck past 5 s (Go calls
     * can block after long uptime or network changes): report anyway and close the sink while this off is still
     * wanted; the stop reports again when done.
     */
    private fun turnOff() {
        // The attempt and the off state in one step; `disconnecting` before the worker can report `disconnected`.
        val off = reconciler.turnOff { setState(SessionState.DISCONNECTING, attempt = it.attempt) }
        mainHandler.postDelayed({
            if (reconciler.desired === off && reconciler.busy() && !destroyed) {
                log("warning", "disconnect didn't finish in 5s, forcing disconnected state")
                closeTunSink()
                reportOff(off)
            }
        }, STOP_THREAD_TIMEOUT_MS)
    }

    /** "Turned off by the user", on disk: boot and a system restart read it. */
    private fun setUserOff(off: Boolean) {
        try { store.setUserOff(off) } catch (e: Exception) { log("warning", "user-off flag: ${e.message}") }
    }

    /** The quick start from the store (tile, notification, boot, reconnect, system restart); null — nothing stored. */
    private fun quickStartRequest(): StartRequest? = try {
        store.quickStart(::extractSocksFromConfig)
    } catch (e: Exception) {
        log("warning", "quick start: stored connection unreadable: ${e.message}")
        null
    }

    /** SOCKS login/password from the saved config in the format of core [engine]. */
    private fun extractSocksFromConfig(configJson: String, engine: CoreKind): Pair<String, String> =
        VpnCores.get(engine).socksCredentials(configJson)

    private fun openApp() {
        packageManager.getLaunchIntentForPackage(packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ?.let { startActivity(it) }
    }

    /** Something other than [request]'s session is wanted in [wanted]. */
    private fun superseded(request: StartRequest, wanted: Desired = reconciler.desired) =
        (wanted as? Desired.On)?.request !== request

    /** True when the session runs; false when the start failed (a reconnect may have asked for a retry). */
    private fun startVpn(request: StartRequest): Boolean {
        val (xrayConfig, params, socksUser, socksPassword) = request
        val isReconnect = request.reconnect
        val socksPort = params.socksPort
        val excludedPackages = params.excludedPackages
        val includedPackages = params.includedPackages
        val vpnMode = params.vpnMode
        val ssPrefix = params.ssPrefix
        val proxyOnly = params.proxyOnly
        val killSwitch = params.killSwitch
        val allowIcmp = params.allowIcmp
        val blockQuic = params.blockQuic
        val ipv6Enabled = params.ipv6Enabled
        val mtu = params.mtu
        val engine = params.engine
        // Replaced before it began (e.g. a disconnect after a reconnect's wait): nothing to undo.
        if (superseded(request)) return false
        if (!isRunning.compareAndSet(false, true)) return false
        val notificationTypeChanged = showNotification != request.params.showNotification
        useParams(request.params)
        // The previous session's notification type stayed until here: switch the foreground one to this session's.
        if (notificationTypeChanged) notifications.foreground()
        sessionCore = VpnCores.get(engine)
        // Keep the previous TUN (kill-switch sink left by a reconnect) open until the
        // new one is established: establish() atomically replaces the interface, so
        // app traffic is blackholed by the old TUN instead of leaking while xray starts.
        var previousTun = tunInterface
        val previousTunParams = tunParams
        // A manual connect with the kill switch keeps the sink after a failure only if traffic
        // was already blocked (BLOCKED) — otherwise a broken config would lock the network.
        val keepSinkOnFailure = killSwitch && (isReconnect || previousTun != null)
        tunInterface = null
        killSwitchEnabled = killSwitch
        tunModeActive = !proxyOnly
        allowIcmpEnabled = allowIcmp
        blockQuicEnabled = blockQuic
        proxyOnlyMode = proxyOnly
        tunMtu = core.tunMtu(mtu.coerceIn(576, 9000))
        if (!isReconnect) ServiceLog.rotate(filesDir)
        setState(if (isReconnect) SessionState.RECONNECTING else SessionState.CONNECTING)
        // After the state, before the save: a quick-connect write that read the count before this is dropped, one
        // that read it after sees the running state and isn't queued.
        sessionStarts.incrementAndGet()
        log("info", "Starting VPN (MTU: $tunMtu)")

        try {
            // Enable prefix proxy only when the ss:// URL contains ?prefix=.
            val finalConfig = if (ssPrefix != null) {
                injectPrefixProxy(xrayConfig, ssPrefix) ?: xrayConfig
            } else {
                xrayConfig
            }

            // For a quick start (tile, boot, reconnect): the params, the config, its SOCKS login and the tile's name
            // together (a quick start's name was read with its config). A failed save costs the quick start, not this
            // session. Saved on a reconnect too: the config it runs may differ from the stored one (a new prefix
            // proxy port).
            try {
                store.save(finalConfig, request.params, socksUser, socksPassword, tileName = request.configName ?: "")
            } catch (e: Exception) {
                log("warning", "Quick-connect data not saved: ${e.message}")
            } finally {
                VpnTileService.configNameChanged(this) // a failed save may have removed the old name too
            }
            if (!prepareBinaries(this)) log("warning", "Bundled geodata not extracted: the core may not start")

            core.init(this) { level, message -> log(level, message) }
            fun coreParams(tunFd: Int?, allowedUids: Set<Int> = emptySet(), blockUnowned: Boolean = false) =
                CoreStartParams(
                    tunFd = tunFd, mtu = tunMtu, socksPort = socksPort,
                    socksUser = socksUser, socksPassword = socksPassword,
                    allowIcmp = allowIcmpEnabled, blockQuic = blockQuicEnabled,
                    vpnMode = vpnMode, allowedUids = allowedUids, blockUnowned = blockUnowned,
                )

            if (proxyOnly) {
                // Proxy-only mode: start Xray SOCKS proxy without TUN tunnel or tun2socks
                log("info", "Proxy-only mode: skipping TUN tunnel")
                try { previousTun?.close() } catch (_: Exception) {}

                core.start(finalConfig, coreParams(tunFd = null))
                // Replaced while starting: the next step of the run stops it; don't report it connected meanwhile.
                if (superseded(request)) return true

                log("info", "xray started (proxy-only, SOCKS on port $socksPort)")
                startStatsMonitoring()
                setConnected(socksPort, socksUser, socksPassword)
                heartbeat.start(isReconnect)
                log("info", "Proxy-only mode active")
            } else {
                if (isReconnect && previousTun != null && previousTunParams == request.params) {
                    // Auto-reconnect with the ConnectionParams that established this TUN (a failed manual
                    // connect may have stored other ones — then it is rebuilt), so the fd is reused as-is. Skipping
                    // establish() keeps the VPN network agent alive — no system
                    // "VPN active" notification, no connectivity flap for apps (issue #81).
                    // tun2socks works on a dup'd fd, so the previous engine's shutdown
                    // did not invalidate this one.
                    tunInterface = previousTun
                    previousTun = null
                    log("info", "Reusing existing TUN fd for reconnect")
                } else {
                    val randomSubnet1 = (2..250).random()
                    val randomSubnet2 = (2..250).random()
                    val randomSubnet3 = (2..250).random()
                    val dynamicTunIp = "10.$randomSubnet1.$randomSubnet2.$randomSubnet3"

                    val dynamicSession = "Teapod-${System.currentTimeMillis() % 10000}"

                    val builder = Builder()
                        .setSession(dynamicSession)
                        .setMtu(tunMtu)
                        .addAddress(dynamicTunIp, 32)
                        .addRoute("0.0.0.0", 0)
                        .addDnsServer(core.tunDnsServer)
                        .setBlocking(true)
                        .setMetered(false)

                    // Without an IPv6 address Android blocks the family for tunneled apps
                    // (no leak): connect() fails instantly and apps fall back to IPv4.
                    // With the address, literal-IPv6 destinations (e.g. Telegram DCs) hang
                    // when the VPN server has no IPv6 connectivity (#81).
                    if (ipv6Enabled) {
                        val hex1 = (1..65535).random().toString(16)
                        val hex2 = (1..65535).random().toString(16)
                        val hex3 = (1..65535).random().toString(16)
                        builder.addAddress("fd00:$hex1:$hex2:$hex3::1", 64)
                        builder.addRoute("::", 0)
                    }

                    if (vpnMode == VpnMode.ONLY_SELECTED) {
                        var allowed = 0
                        for (pkg in includedPackages) {
                            try {
                                builder.addAllowedApplication(pkg)
                                allowed++
                            } catch (e: Exception) {
                                log("warning", "Failed to allow $pkg: ${e.message}")
                            }
                        }
                        // Android applies a VPN with no allowed app to every app: traffic stays in the tunnel, but
                        // "only selected apps" covers all of them.
                        if (allowed == 0) log("warning", "Only selected apps, but none is installed: the VPN covers every app")
                    } else {
                        for (pkg in excludedPackages) {
                            try { builder.addDisallowedApplication(pkg) } catch (_: Exception) {}
                        }
                        try { builder.addDisallowedApplication(packageName) } catch (_: Exception) {}
                    }

                    val fdResult = nativeSetMaxFds(65536)
                    log("info", "nativeSetMaxFds result: $fdResult")

                    tunInterface = builder.establish() ?: throw IllegalStateException("Failed to establish TUN")
                    tunParams = request.params
                    // The new interface replaced the old one atomically — the sink fd can go now.
                    try { previousTun?.close() } catch (_: Exception) {}
                    log("info", "TUN established with IP $dynamicTunIp")
                }

                // Split tunneling: UID filter at the core level (tun2socks validator / TUN admission)
                val allowedUids = resolveUids(vpnMode, includedPackages, excludedPackages)
                val blockUnowned = excludedPackages.isNotEmpty() && !allowTethering
                core.start(finalConfig, coreParams(tunInterface!!.fd, allowedUids, blockUnowned))
                // Replaced while starting: the next step of the run stops it; don't report it connected meanwhile.
                if (superseded(request)) return true

                // No permanent wakelock: TUN packets wake the CPU by themselves, and
                // reconnectInternal() takes its own timed wakelock for the cycle. In deep
                // Doze the heartbeat stretches — Heartbeat.probeOnWake() covers wake-up.
                startStatsMonitoring()
                network.start()
                setConnected(socksPort, socksUser, socksPassword)
                heartbeat.start(isReconnect)
                log("info", "VPN connected successfully")
            }
            return true
        } catch (e: Throwable) {
            // Throwable: the core's UnsatisfiedLinkError/ExceptionInInitializerError must also
            // return the service to the stopped state.
            log("error", "Start failed: ${e.message}")
            // If no new TUN was established, restore the old fd: as kill-switch sink
            // (keeps blocking traffic) and/or for reuse by the next reconnect attempt.
            // Otherwise the old fd is obsolete.
            val wanted = reconciler.desired // read once: the decisions below agree
            val replaced = superseded(request, wanted)
            val next = replaced && wanted is Desired.On
            if (tunInterface == null && previousTun != null && (killSwitch || isReconnect || next) && !proxyOnly) {
                tunInterface = previousTun
                tunParams = previousTunParams
            } else {
                try { previousTun?.close() } catch (_: Exception) {}
            }
            if (replaced) {
                // Replaced while starting: no error for it. A new session keeps the sink for its start; an off
                // state stops as a user disconnect does. Its states belong to what is wanted now.
                sessionAttempt = wanted.tag
                stopVpn(explicit = !next, reconnecting = next)
                return false
            }
            val retry = (wanted as? Desired.On)?.takeIf { isReconnect }
            val willRetry = retry != null && reconnectAttempts.incrementAndGet() <= MAX_RECONNECT_ATTEMPTS
            // On final failure with kill switch keep the sink (explicit=false) so
            // traffic stays blocked instead of silently leaking past the VPN.
            stopVpn(resultState = SessionState.ERROR, explicit = !willRetry && !keepSinkOnFailure, reconnecting = willRetry,
                error = if (willRetry) null else e.message ?: e.javaClass.simpleName)
            if (willRetry) {
                val attempt = reconnectAttempts.get()
                val delayMs = RECONNECT_RETRY_BASE_MS * attempt
                log("warning", "Reconnect attempt $attempt/$MAX_RECONNECT_ATTEMPTS failed, retrying in ${delayMs}ms")
                // A new start of the same stored session, unless something else is wanted by then.
                mainHandler.postDelayed({
                    // Still waiting for it: not after the service stopped or a quick start that couldn't start
                    // finished the state (abortQuickConnect).
                    if (destroyed || snapshot.state != SessionState.RECONNECTING) return@postDelayed
                    // The stored session, or the failed request itself when the store has none (a failed save).
                    val again = quickStartRequest() ?: request
                    reconciler.replace(retry!!, Desired.On(again, reconciler.newId()))
                }, delayMs)
            }
            return false
        }
    }

    /**
     * Resolves UIDs for the given package lists based on vpnMode.
     * In [VpnMode.ONLY_SELECTED] mode returns allowed UIDs; otherwise returns excluded UIDs
     * (including the app's own UID to prevent routing loops).
     */
    private fun resolveUids(
        vpnMode: VpnMode,
        includedPackages: List<String>,
        excludedPackages: List<String>,
    ): Set<Int> {
        val uids = mutableSetOf<Int>()
        val packages = if (vpnMode == VpnMode.ONLY_SELECTED) includedPackages else excludedPackages
        for (pkg in packages) {
            try {
                val uid = packageManager.getPackageUid(pkg, PackageManager.GET_META_DATA)
                uids.add(uid)
                log("info", "${if (vpnMode == VpnMode.ONLY_SELECTED) "Allowed" else "Excluded"} UID for $pkg: $uid")
            } catch (e: Exception) {
                log("warning", "Failed to get UID for $pkg: ${e.message}")
            }
        }

        try {
            val ownUid = packageManager.getPackageUid(packageName, PackageManager.GET_META_DATA)
            if (vpnMode == VpnMode.ONLY_SELECTED) {
                if (uids.remove(ownUid)) {
                    log("info", "Removed own UID ($ownUid) from Allowed list to prevent loop")
                }
            } else {
                uids.add(ownUid)
                log("info", "Excluded own UID ($packageName): $ownUid")
            }
        } catch (e: Exception) {
            log("warning", "Failed to resolve own UID: ${e.message}")
        }

        return uids
    }

    /**
     * Parses [xrayConfig] JSON, finds the first proxy Shadowsocks server address,
     * starts a [PrefixTcpProxy] that sends [prefixHex] bytes before forwarding,
     * and returns a modified config pointing Xray to the local proxy.
     */
    private fun injectPrefixProxy(xrayConfig: String, prefixHex: String): String? {
        return try {
            val prefixBytes = prefixHex.chunked(2)
                .map { it.toInt(16).toByte() }
                .toByteArray()

            sessionCore.redirectProxyServer(xrayConfig) { realHost, realPort ->
                val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
                val ownUid = android.os.Process.myUid()
                val proxy = PrefixTcpProxy(realHost, realPort, prefixBytes) { client ->
                    try {
                        val uid = cm.getConnectionOwnerUid(
                            OsConstants.IPPROTO_TCP,
                            client.remoteSocketAddress as InetSocketAddress,
                            InetSocketAddress(client.localAddress, client.localPort)
                        )
                        uid == ownUid
                    } catch (_: SecurityException) {
                        true // proxy-only: we're not the active VPN, lookup is unavailable; listen on loopback only
                    } catch (_: Exception) {
                        false
                    }
                }
                proxy.start()
                prefixProxy = proxy
                log("info", "Prefix proxy: 127.0.0.1:${proxy.localPort} (${prefixBytes.size} prefix bytes)")
                proxy.localPort
            }
        } catch (e: Exception) {
            log("warning", "Failed to start prefix proxy: ${e.message}")
            null
        }
    }

    override fun onRevoke() {
        // Called by Android when the VPN is turned off externally (system settings, another VPN)
        log("info", "VPN revoked by system")
        // Off until the user connects again (reconnects and retries no longer apply); not the user's choice, so not
        // persisted — a restart without the permission doesn't start anyway. The off state answers any waiting
        // connect, and the service stops once it is reached.
        turnOff()
    }

    /** Closes the kill switch's TUN sink if the service is already stopped. */
    private fun closeTunSink() {
        if (isRunning.get()) return
        try { tunInterface?.close() } catch (_: Exception) {}
        tunInterface = null
    }

    private fun stopVpn(
        resultState: SessionState = SessionState.DISCONNECTED,
        explicit: Boolean = false,
        reconnecting: Boolean = false,
        /** The reason of a failed start, reported with [resultState] (or `blocked`). */
        error: String? = null,
    ) {
        if (!isRunning.compareAndSet(true, false)) return  // idempotent — safe to call multiple times
        log("info", "stopVpn: begin (explicit=$explicit, reconnecting=$reconnecting)")
        heartbeat.stop()
        tunModeActive = false
        lastConnectedMs = 0L

        var keptTunAsSink = false
        try {
            network.stop()

            statsThread?.let {
                try { it.interrupt() } catch (e: Exception) {
                    log("warning", "statsThread.interrupt failed: ${e.message}")
                }
            }
            statsThread = null

            try { prefixProxy?.stop() } catch (e: Exception) {
                log("warning", "prefixProxy.stop failed: ${e.message}")
            }
            prefixProxy = null

            // Close TUN fd early so tun2socks goroutines reading from it get EOF and
            // unblock immediately (tun2socks works on a dup'd fd, so this is safe to
            // skip too). During internal reconnects the TUN is always kept open: the
            // next startVpn(isReconnect=true) reuses the same fd (no establish(), no
            // system "VPN active" notification), and in between app traffic is
            // blackholed by the sink instead of leaking past the VPN. Kill-switch
            // path additionally keeps it after non-explicit stops (traffic sink).
            val keepTunAsSink = (killSwitchEnabled || reconnecting) && !explicit && !proxyOnlyMode
                    && tunInterface != null
            keptTunAsSink = keepTunAsSink
            // A core that reads the TUN fd itself (Rust) is stopped before the fd is closed:
            // otherwise the freed fd number could go to someone else's descriptor.
            if (core.borrowsTunFd) core.stop()
            if (!keepTunAsSink) {
                try {
                    tunInterface?.close()
                } catch (e: Exception) {
                    log("warning", "tunInterface.close (early) failed: ${e.message}")
                }
                tunInterface = null
            }

            if (!core.borrowsTunFd) core.stop()

            // Clean up saved credentials on explicit disconnect
            if (explicit) {
                try { store.clearCredentials() } catch (e: Exception) { log("warning", "clearing socks_creds: ${e.message}") }
            }

            if (keepTunAsSink) {
                if (reconnecting) {
                    log("info", "TUN kept open during reconnect (sink + fd reuse)")
                } else {
                    setUnderlyingNetworks(emptyArray())
                    log("info", "Kill switch active: TUN kept open, underlying networks cleared")
                }
            }

            // The stored config stays for a quick reconnect (tile, boot): process-private filesDir.
        } finally {
            val finalState = when {
                // TUN is already a sink: no traffic while we wait for the network (up to 30 s) — not "connected".
                // The snapshot drops the SOCKS login, so the next start reports fresh credentials.
                reconnecting -> SessionState.RECONNECTING
                // The TUN sink stayed open (kill switch) — traffic is blocked,
                // report a state distinct from disconnected.
                keptTunAsSink -> SessionState.BLOCKED
                else -> resultState
            }
            setState(finalState, error)
            // Off without a sink, the service stops (publish); the kill switch's block keeps it with its notification.
            if (keptTunAsSink && !reconnecting) notifications.blocked()
            log("info", "stopVpn: done (state=${finalState.wire})")
            ServiceLog.flush(filesDir)
        }
    }

    override fun onDestroy() {
        destroyed = true
        screen.unregister()
        stopVpn()
        // stopVpn posted "Disconnected" — after the service dies it would remain an orphan.
        notifications.cancel()
        ServiceLog.flush(filesDir)
        super.onDestroy()
    }

    private fun startStatsMonitoring() {
        val generation = SessionStats.reset(System.currentTimeMillis())
        statsThread = Thread {
            while (isRunning.get()) {
                try {
                    Thread.sleep(if (screenOn) SessionStats.INTERVAL_MS else SessionStats.INTERVAL_SCREEN_OFF_MS)
                    // Bound to the session seen dead: a connect that replaced it meanwhile isn't stopped.
                    val session = lastConnectedMs
                    if (tunDied()) {
                        log("warning", "tun2socks stopped while connected, reconnecting")
                        reconnectInternal(session)
                        break
                    }
                    SessionStats.sample(generation, core.uploadBytes(), core.downloadBytes(), System.currentTimeMillis(), screenOn)
                    if (screenOn) notifications.speeds(SessionStats.uploadSpeed, SessionStats.downloadSpeed, screenOn = true)
                } catch (_: InterruptedException) { break } catch (_: Exception) {}
            }
        }.also { it.isDaemon = true; it.start() }
    }

    /**
     * `connected` in TUN mode while tun2socks no longer runs: the TUN fd was likely closed externally (e.g. a system
     * network change during a phone call) without onRevoke(). The stats thread then reconnects, which publishes
     * `reconnecting`, so Flutter and the tile don't show a phantom connection. tun2socks is checked before
     * [isRunning]: a stop clears [isRunning] before it stops the core, so a stopping session is never taken for dead.
     */
    private fun tunDied(): Boolean =
        snapshot.state == SessionState.CONNECTED && tunModeActive && !core.isTunRunning() && isRunning.get()

    /// Restart from saved parameters (CONNECT_QUICK, system restart): the stored session becomes the desired one.
    private fun startQuick(request: StartRequest) {
        reconnectAttempts.set(0)
        reconciler.set(Desired.On(request, reconciler.newId()))
    }

    /**
     * A reconnect of the running session (network change, dead tunnel): a new start of the stored session that first
     * waits for direct internet. [session] — the `lastConnectedMs` of the session seen dead: the reconnect applies only
     * while it is still the connected one. Captured as 0 (a stop cleared it meanwhile) it never matches. Null —
     * whatever is connected.
     */
    private fun reconnectInternal(session: Long? = null) {
        mainHandler.post {
            // The desired state of the session that is connected, not whatever is wanted by now (a probe of a session
            // being replaced must not replace its successor).
            val current = connectedDesired ?: return@post
            if (destroyed || !isRunning.get() || (session != null && (session == 0L || lastConnectedMs != session))) return@post
            // The stored session, or the running one when the store has none (a failed save).
            val request = quickStartRequest() ?: current.request.copy(attempt = 0, reconnect = true)
            log("info", "reconnectInternal: starting reconnect cycle")
            reconnectAttempts.set(0)
            if (!reconciler.replace(current, Desired.On(request, reconciler.newId(), waitForNetwork = true))) {
                log("info", "reconnectInternal: session replaced, skipped")
            }
        }
    }

    /** [on]'s session: a reconnect first waits (up to 30 s, under a wakelock) for direct internet, while it is wanted. */
    private fun startSession(on: Desired.On): Boolean {
        connectedDesired = null
        if (!on.waitForNetwork) return startVpn(on.request).also { if (it) connectedDesired = on }
        val wakeLock = try {
            (getSystemService(POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "TeapodStream:Reconnect")
                .also { it.acquire(40_000) }
        } catch (_: Exception) { null }
        try {
            log("info", "reconnectInternal: waiting for direct internet (deadline +30s)")
            val deadline = System.currentTimeMillis() + 30_000
            while (reconciler.desired === on && System.currentTimeMillis() < deadline && !hasDirectInternet()) {
                try { Thread.sleep(RECONNECT_DEBOUNCE_MS) } catch (_: InterruptedException) { break }
            }
            // Replaced while waiting: the next step of the run handles what is wanted now.
            if (reconciler.desired !== on) return false
            return startVpn(on.request).also { if (it) connectedDesired = on }
        } finally {
            try { wakeLock?.release() } catch (_: Exception) {}
        }
    }

    /** The VPN is off for [off]: `disconnected` tagged with its attempt, once. */
    private fun reportOff(off: Desired.Off) {
        if (snapshot.state == SessionState.DISCONNECTED && snapshot.attempt == off.attempt) return
        setState(SessionState.DISCONNECTED, attempt = off.attempt)
    }

    // Returns true if the physical network (not through VPN) can reach 8.8.8.8:53.
    // The VpnService process UID is excluded from the tunnel, so sockets here bypass TUN.
    // bindSocket() additionally pins the socket to the physical interface, avoiding
    // stale routing state during WiFi→LTE handover.
    private fun hasDirectInternet(): Boolean = try {
        Socket().use { socket ->
            network.physical()?.bindSocket(socket)
            socket.connect(InetSocketAddress(CONNECTIVITY_CHECK_HOST, 53), RECONNECT_DEBOUNCE_MS.toInt())
            true
        }
    } catch (_: Exception) { false }

    /** CONNECT_QUICK didn't start (no config or VPN permission): the tile and
     * the notification must not stay on "Connecting…"; the rest is up to the app.
     * A TUN sink left by an earlier session: with the kill switch we keep it as a block, without it we close it. */
    private fun abortQuickConnect(killSwitch: Boolean) {
        val blocked = killSwitch && tunInterface != null
        if (!blocked) closeTunSink()
        setState(if (blocked) SessionState.BLOCKED else SessionState.DISCONNECTED, attempt = 0)
        if (blocked) notifications.blocked()
        openApp()
    }

    /**
     * Stops the service once the VPN is off and nothing is held ([serviceIdle]). On the main thread, like
     * onStartCommand: every command it has received is already in the queue, and `stopSelf(lastStartId)`
     * is ignored by the system if a newer intent is on its way.
     */
    private fun stopIfIdle() {
        // The queue first: a command finishing after this read is checked again by afterEach (after its reports were
        // posted); once it reads idle no new command can begin (they are queued here, on the main thread).
        if (reconciler.busy() || isRunning.get()) return
        if (!serviceIdle(snapshot.state, tunHeld = tunInterface != null, queueBusy = false)) return
        log("info", "VPN off: the service stops")
        stopSelf(lastStartId)
    }

    /** A state other than connected, tagged with [sessionAttempt]; [error] replaces the failure reason. */
    private fun setState(state: SessionState, error: String? = null, attempt: Long = sessionAttempt) =
        publish { it.moved(state, attempt, error ?: it.error, core.kind) }

    /**
     * The only writer of the session state: stores the snapshot [next] makes of the current one and reports it to
     * Flutter, the itest marker, the tile, the intermediate notification and the automation broadcast. The write and
     * the event post are one step under [publishLock] (neither blocks), so events leave in the order of the writes.
     */
    private fun publish(next: (SessionSnapshot) -> SessionSnapshot) {
        val published = synchronized(publishLock) {
            next(session.get()).also {
                session.set(it)
                VpnEventStreamHandler.sendEvent(it.toMap())
                ItestBridge.emit(it.itestMarker(System.currentTimeMillis()))
            }
        }
        VpnTileService.updateTile(this)
        ServiceNotifications.onState(this, published.state)
        if (published.state.isOff) mainHandler.post(::stopIfIdle)
        // An implicit broadcast is readable by any app — only with the option and without the SOCKS port.
        if (automationEnabled(this)) {
            sendBroadcast(Intent("com.teapodstream.STATE_CHANGED").putExtra("state", published.state.wire))
        }
    }

    private fun setConnected(socksPort: Int, socksUser: String, socksPassword: String) {
        reconnectAttempts.set(0)
        val now = System.currentTimeMillis()
        lastConnectedMs = now
        network.markConnected()
        publish { SessionSnapshot.connected(sessionAttempt, socksPort, socksUser, socksPassword, now, core.kind) }
        // The "Disconnected"/intermediate notification bypasses the dedupe cache —
        // reset it so the connected layout is always posted.
        notifications.connected(screenOn)
        // If notify() is dropped by the rate limit (tile → intermediate → connected within
        // a fraction of a second), a retry after 2 s guarantees the final look (issue #76).
        mainHandler.postDelayed({
            if (snapshot.state == SessionState.CONNECTED) {
                notifications.refresh(SessionStats.uploadSpeed, SessionStats.downloadSpeed, screenOn)
            }
        }, 2_000)
    }

    private fun log(level: String, message: String) = ServiceLog.write(filesDir, level, message)
}
