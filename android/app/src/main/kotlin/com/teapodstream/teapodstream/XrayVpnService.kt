package com.teapodstream.teapodstream

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.system.OsConstants
import android.util.LruCache
import androidx.core.app.NotificationCompat
import java.io.File
import com.teapodstream.teapodstream.core.CoreKind
import com.teapodstream.teapodstream.core.CoreStartParams
import com.teapodstream.teapodstream.core.VpnCore
import com.teapodstream.teapodstream.core.VpnCores
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.Socket
import java.net.URL
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
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

        private val session = AtomicReference(SessionSnapshot())
        private val publishLock = Any()

        /** The current session; changed only by [publish]. Reading it has no side effects. */
        val snapshot: SessionSnapshot get() = session.get()

        // Set true on explicit user disconnect, false on connect — guards reconnectInternal()
        val userRequestedDisconnect = AtomicBoolean(false)

        /** The attempt of the last ACTION_CONNECT received (main thread); a disconnect tags its stop with it. */
        @Volatile private var requestedAttempt: Long = 0

        /**
         * Tasker/Anubis integration: [VpnCommandReceiver] commands and the STATE_CHANGED
         * broadcast. Both are visible to any app (turn the VPN off, watch it),
         * so they work only when the option is explicitly enabled (off by default).
         */
        fun automationEnabled(context: android.content.Context): Boolean =
            context.getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                .getBoolean("flutter.automation_enabled", false)

        const val LOG_FILE_NAME = "vpn_log.txt"
        const val LOG_PREV_FILE_NAME = "vpn_log.prev.txt"
        val LOG_FILE_LOCK = Any()
        const val PREFS_NAME = "vpn_prefs"
        const val PREF_LOGS_ENABLED = "logs_enabled"

        // User toggle: when off, only warning/error are logged (file + UI) so a broken
        // session still leaves diagnostics. Persisted in PREFS_NAME by MainActivity.
        @Volatile var logsEnabled = true

        // Log lines are buffered and flushed in batches: a FileWriter open per line wakes
        // flash storage on every heartbeat/xray-access event. warning/error flush
        // immediately so crash diagnostics never sit in the buffer.
        private val logBuffer = StringBuilder()
        private var lastLogFlushMs = 0L
        private const val LOG_FLUSH_INTERVAL_MS = 5_000L
        private const val LOG_FLUSH_SIZE_CHARS = 8 * 1024

        @JvmStatic fun flushLogBuffer(filesDir: File) {
            synchronized(LOG_FILE_LOCK) { flushLogBufferLocked(filesDir) }
        }

        private fun flushLogBufferLocked(filesDir: File) {
            if (logBuffer.isEmpty()) return
            try {
                java.io.FileWriter(File(filesDir, LOG_FILE_NAME), true).use { it.write(logBuffer.toString()) }
            } catch (_: Exception) {}
            logBuffer.setLength(0)
            lastLogFlushMs = System.currentTimeMillis()
        }

        private const val NOTIFICATION_CHANNEL_ID = "vpn_service"
        private const val NOTIFICATION_CHANNEL_MINIMAL_ID = "vpn_service_minimal"
        private const val NOTIFICATION_ID = 1

        private const val CONNECTIVITY_CHECK_HOST = "8.8.8.8"
        private const val HEARTBEAT_INTERVAL_MS = 15_000L
        // Screen off: nobody is watching, the radio should be allowed to idle between
        // probes. Dead-tunnel detection grows to ~3 min while asleep — acceptable,
        // checkTunStallOnWake() probes immediately on SCREEN_ON.
        private const val HEARTBEAT_INTERVAL_SCREEN_OFF_MS = 60_000L
        private const val NOTIFICATION_MIN_INTERVAL_MS = 5_000L
        // If tun2socks has more than this many active proxy goroutines the gVisor TCP
        // state machine is leaking connections. Trigger a reconnect to reset it.
        private const val TUN_CONN_LEAK_THRESHOLD = 200L
        // If no data has reached the TUN interface for this long while ≥2 connections
        // are active, tun2socks goroutines are stuck (proxy connections held alive by
        // keepalives but real data not flowing). SOCKS5 heartbeat won't catch this.
        private const val TUN_STALL_TIMEOUT_MS = 120_000L
        // After a reconnect xray establishes its outbound connection lazily. Probes run every
        // 15 s but failures are not counted until the first probe succeeds (warmup mode). This
        // self-adjusts to actual network speed instead of relying on a fixed timer. Hard ceiling:
        // if no probe succeeds within HEARTBEAT_WARMUP_TIMEOUT_MS → something is genuinely broken.
        private const val HEARTBEAT_WARMUP_TIMEOUT_MS = 30_000L
        // How long to wait for Flutter's reaction to tunnel_dead before reconnecting ourselves.
        private const val TUNNEL_DEAD_NOTIFY_COOLDOWN_MS = 45_000L
        private const val STATS_INTERVAL_MS = 1_000L
        private const val STATS_INTERVAL_SCREEN_OFF_MS = 10_000L
        private const val STOP_THREAD_TIMEOUT_MS = 5_000L
        private const val RECONNECT_DEBOUNCE_MS = 2_000L
        // Failed CONNECT_QUICK reconnects are retried with linear backoff instead of
        // silently leaving the VPN off (and, with kill switch, traffic leaking).
        private const val MAX_RECONNECT_ATTEMPTS = 3
        private const val RECONNECT_RETRY_BASE_MS = 5_000L

        @Volatile private var totalUpload: Long = 0
        @Volatile private var totalDownload: Long = 0
        @Volatile private var lastUploadSpeed: Long = 0
        @Volatile private var lastDownloadSpeed: Long = 0

        private const val MAX_STATS_HISTORY = 300
        private val speedHistory = SpeedHistory(MAX_STATS_HISTORY)

        fun getStats(): Map<String, Long> = mapOf(
            "upload" to totalUpload,
            "download" to totalDownload,
            "uploadSpeed" to lastUploadSpeed,
            "downloadSpeed" to lastDownloadSpeed,
        )

        /** Chart history after point [since] of epoch [epoch] (see [SpeedHistory.since]). */
        fun getStatsHistory(epoch: Int, since: Long): Map<String, Any> = speedHistory.since(epoch, since)

        // showNotification of the last connection. null — the service in this process hasn't
        // loaded parameters yet (tile/events before the service): read from disk (issue #76).
        @Volatile private var showNotificationFlag: Boolean? = null
        // The last posted intermediate state: re-notify() with the same text
        // eats the update rate limit (the system silently drops extra ones), and the final
        // "connected" got lost — the notification "hung" on "Connecting…" (issue #76).
        @Volatile private var lastIntermediate: Boolean? = null
        // A constant `when`: otherwise every update lifts the notification to the top of the shade.
        private val notificationWhen = System.currentTimeMillis()

        private fun notificationsEnabled(context: Context): Boolean =
            showNotificationFlag
                ?: (QuickConnectStore(context.filesDir).params()?.showNotification ?: true).also { showNotificationFlag = it }

        /** Notification on state change: intermediate for connecting/disconnecting/reconnecting. */
        @JvmStatic fun onStateNotification(context: Context, state: SessionState) {
            val connecting = when (state) {
                SessionState.CONNECTING, SessionState.RECONNECTING -> true
                SessionState.DISCONNECTING -> false
                else -> { lastIntermediate = null; return }
            }
            if (!notificationsEnabled(context) || lastIntermediate == connecting) return
            try {
                val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                ensureNotificationChannels(context, manager)
                manager.notify(NOTIFICATION_ID, buildIntermediateNotification(context, connecting))
                lastIntermediate = connecting
            } catch (_: Exception) { }
        }

        private fun buildIntermediateNotification(context: Context, connecting: Boolean): Notification =
            baseNotification(context, NOTIFICATION_CHANNEL_ID)
                .setContentText(context.appString(if (connecting) R.string.state_connecting else R.string.state_disconnecting))
                .setProgress(0, 0, true)
                .build()

        private fun baseNotification(context: Context, channel: String): NotificationCompat.Builder =
            NotificationCompat.Builder(context, channel)
                .setContentTitle("TeapodStream VPN")
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setWhen(notificationWhen)
                .setShowWhen(false)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                // Android 12+ otherwise delays showing the FGS notification by 10 s.
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)

        private fun ensureNotificationChannels(context: Context, manager: NotificationManager) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            manager.createNotificationChannel(
                NotificationChannel(NOTIFICATION_CHANNEL_ID, context.appString(R.string.channel_status_name), NotificationManager.IMPORTANCE_LOW)
                    .apply { description = context.appString(R.string.channel_status_description) }
            )
            manager.createNotificationChannel(
                NotificationChannel(NOTIFICATION_CHANNEL_MINIMAL_ID, context.appString(R.string.channel_minimal_name), NotificationManager.IMPORTANCE_MIN)
                    .apply { description = context.appString(R.string.channel_minimal_description) }
            )
        }

        fun prepareBinaries(context: android.content.Context): Boolean {
            val filesDir = context.filesDir
            val assets = context.assets
            val assetsToCopy = listOf("geoip.dat", "geosite.dat")
            for (name in assetsToCopy) {
                val file = java.io.File(filesDir, name)
                if (file.exists()) continue
                try {
                    val input = try { assets.open("binaries/$name") } catch (e: Exception) { assets.open("flutter_assets/assets/binaries/$name") }
                    input.use { i -> file.outputStream().use { o -> i.copyTo(o) } }
                } catch (e: Exception) { }
            }
            return true
        }
    }

    private var tunInterface: ParcelFileDescriptor? = null
    private var statsThread: Thread? = null
    private val isRunning = AtomicBoolean(false)
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    @Volatile private var lastUnderlyingNetwork: Network? = null
    @Volatile private var lastConnectedMs: Long = 0L
    /**
     * Flutter's connect attempt the published states are tagged with ([SessionSnapshot.attempt]): set by a connect
     * or a disconnect before it stops or starts a session, 0 for a quick start.
     */
    @Volatile private var sessionAttempt: Long = 0
    // TUN mode (not proxy-only): the stats thread checks that tun2socks still runs.
    @Volatile private var tunModeActive = false
    // The physical network at the moment of connected — the deferred network-change check compares against it.
    @Volatile private var connectedNetwork: Network? = null
    private var prefixProxy: PrefixTcpProxy? = null
    private var showNotification: Boolean
        // Before parameters are loaded (ACTION_DISCONNECT in a fresh process) — from disk.
        get() = notificationsEnabled(this)
        set(value) { showNotificationFlag = value }
    @Volatile private var screenOn = true
    @Volatile private var deviceIdle = false
    @Volatile private var lastNotificationText: String? = null
    @Volatile private var lastNotificationMs = 0L
    private var screenReceiver: android.content.BroadcastReceiver? = null
    private var killSwitchEnabled = false
    @Volatile private var allowIcmpEnabled = true
    @Volatile private var blockQuicEnabled = false
    private var proxyOnlyMode = false
    private val networkChangeHandler = Handler(Looper.getMainLooper())
    // Session commands (ACTION_CONNECT / ACTION_DISCONNECT) run in the order they were received;
    // their lock is also the one session changes and a deferred reconnect's stop take, so a stale
    // reconnect won't stop an already new session.
    // A start that ends off (failed, cancelled) is checked once it has finished: while it runs it holds the service.
    private val sessionCommands = SessionCommands(afterEach = { if (snapshot.state.isOff) mainHandler.post(::stopIfIdle) })
    /** The startId of the last onStartCommand (main thread): see [stopIfIdle]. */
    private var lastStartId = 0
    /** Set in onDestroy (main thread): reports posted later belong to a stopped instance. */
    private var destroyed = false
    private val sessionLock = sessionCommands.lock
    // Among the deferred events there was a loss of VALIDATED — reconnect without checking the network.
    @Volatile private var pendingForce = false
    private var pendingNetworkRunnable: Runnable? = null
    private var heartbeatThread: Thread? = null
    private val heartbeatFailures = AtomicInteger(0)
    private val store by lazy { QuickConnectStore(filesDir) }
    /** The parameters [tunInterface] was built with: a reconnect reuses the fd only for the same ones. */
    @Volatile private var tunParams: ConnectionParams? = null

    /** The parameters of the session being started or run ([useParams]); null before the first start. */
    @Volatile private var params: ConnectionParams? = null
    // How we probe the tunnel: "socks" (HTTP via SOCKS5), "xrayDelay" (measured inside
    // the core) or "passive" (only tun2socks metrics, no active probes).
    private val heartbeatProbe get() = params?.heartbeatProbe ?: "socks"
    // Behavior on a dead tunnel: "reconnect" — reconnect to the same server,
    // "switchConfig" — leave the decision to Flutter (it picks a live config).
    private val heartbeatAction get() = params?.heartbeatAction ?: "reconnect"
    private val heartbeatThreshold get() = params?.heartbeatThreshold ?: 3
    private val heartbeatUrl get() = params?.heartbeatUrl ?: ConnectionParams.DEFAULT_HEARTBEAT_URL
    private val allowTethering get() = params?.allowTethering ?: false
    private val mainHandler = Handler(Looper.getMainLooper())
    private var lastTunnelDeadNotifyAt = 0L
    private val wakeProbeRunning = AtomicBoolean(false)
    private val reconnectAttempts = AtomicInteger(0)

    @Volatile private var tunMtu = 1500
    // Core of the current session: fixed in startVpn after the CAS so that a core change
    // by a new connect doesn't redirect stop/heartbeat/stats to another core.
    @Volatile private var sessionCore: VpnCore = VpnCores.active
    private val core: VpnCore get() = sessionCore

    override fun onCreate() {
        super.onCreate()
        logsEnabled = getSharedPreferences(PREFS_NAME, MODE_PRIVATE).getBoolean(PREF_LOGS_ENABLED, true)
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        screenOn = pm.isInteractive
        deviceIdle = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) pm.isDeviceIdleMode else false
        registerScreenReceiver()
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
                if (!isRunning.get()) ensureForeground(connecting = false)
                setUserOff(true)
                // Flutter may still wait for the last connect it sent (a disconnect from the notification or
                // the tile cancels it): the stop's events answer that attempt — the one received before this.
                val answers = requestedAttempt
                // Signal disconnecting immediately so the button turns yellow
                // even when triggered from the notification (no Flutter-side handler).
                setState(SessionState.DISCONNECTING)
                // Stop in the session queue, after the commands received before this one. Go calls
                // (stopTun2Socks/stopXray) can block if goroutines are stuck after long uptime or network changes.
                lateinit var command: SessionCommands.Command
                // "disconnected", on the main thread like onStartCommand (so the check and a new command can't
                // interleave) — unless a start was received meanwhile: its session (and its attempt tag) owns the
                // state. Answers the connect Flutter may wait for.
                val report = {
                    mainHandler.post {
                        if (destroyed) {
                            // A late report (the 5 s supervisor) of a stopped instance: a newer one may own the
                            // session state, which is process-wide.
                            log("info", "disconnect report after the service stopped: dropped")
                        } else if (sessionCommands.startAfter(command.id)) {
                            log("info", "disconnect finished after a new start: final state left to it")
                        } else {
                            sessionAttempt = answers
                            setState(SessionState.DISCONNECTED)
                        }
                    }
                }
                command = sessionCommands.submit(SessionCommands.Kind.DISCONNECT) {
                    sessionAttempt = answers
                    stopVpn(explicit = true)
                    // From the blocked state stopVpn exits on the CAS (isRunning is already false),
                    // the kill switch's TUN sink must be closed explicitly.
                    closeTunSink()
                    report()
                }
                // A stop stuck (or queued behind a stuck command) past 5 s: report anyway and close the sink
                // without the queue, as long as no newer start took over. The queued stop reports again when done.
                Thread {
                    try {
                        command.done.get(STOP_THREAD_TIMEOUT_MS, java.util.concurrent.TimeUnit.MILLISECONDS)
                    } catch (e: java.util.concurrent.TimeoutException) {
                        log("warning", "disconnect didn't finish in 5s, forcing disconnected state")
                        if (!sessionCommands.startAfter(command.id)) closeTunSink()
                        report()
                    } catch (e: Exception) {
                        log("warning", "disconnect failed: ${e.message}")
                        report()
                    }
                }.start()
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
                requestedAttempt = attempt
                showNotificationFor(params)
                setUserOff(false)
                reconnectAttempts.set(0)
                ensureForeground()
                // The tile's name, like the params, config and login for a quick start, is stored once the session
                // runs with them (startVpn): a cancelled connect leaves the tile with what it will connect.
                val request = StartRequest(
                    xrayConfig, params, socksUser, socksPassword, attempt, reconnect = false,
                    configName = intent.getStringExtra(EXTRA_CONFIG_NAME),
                )
                // Changing server/settings on a live tunnel: the old TUN stays a sink
                // until the new one's establish() — no explicit disconnect and no leak window.
                sessionCommands.submit(SessionCommands.Kind.CONNECT, skipped = {
                    log("info", "CONNECT skipped: a newer connect or disconnect was received")
                }) {
                    // Revoked (onRevoke stops outside the queue) or disconnected meanwhile: don't start. Flutter
                    // waits for this attempt, so answer it.
                    if (userRequestedDisconnect.get()) {
                        log("info", "CONNECT cancelled: VPN revoked or disconnected meanwhile")
                        sessionAttempt = request.attempt
                        setState(SessionState.DISCONNECTED)
                        return@submit
                    }
                    // Before the old session stops: its events from here on belong to this attempt.
                    sessionAttempt = request.attempt
                    if (isRunning.get()) stopVpn(reconnecting = true)
                    startVpn(request)
                }
                return START_STICKY
            }
            ACTION_CONNECT_QUICK -> {
                // The parameters before ensureForeground, so the right notification type (full or minimal) shows
                // from the start.
                val request = quickStartRequest()
                (request?.params ?: store.params())?.let(::showNotificationFor)
                if (isRunning.get()) {
                    // startVpn would bail on its CAS anyway — bail here instead so the
                    // state isn't left stuck at "reconnecting" over a live tunnel.
                    // startForegroundService requires startForeground — repeat it with
                    // the live session's notification: "Connecting…" would hang until the speed changes.
                    val live = snapshot.state == SessionState.CONNECTED && showNotification
                    if (live) lastNotificationText = null  // the next stats tick updates the speed
                    ensureForeground(override = if (live) buildConnectedNotification(0, 0) else null)
                    log("info", "CONNECT_QUICK ignored: VPN already running")
                    return START_STICKY
                }
                ensureForeground()
                when {
                    // Nothing stored to start (a failed save may have removed it): the session holding the sink, if
                    // any, decides whether it stays.
                    request == null -> abortQuickConnect(killSwitchEnabled)
                    // Permission revoked — the system already disconnected our TUN, nothing to block with.
                    !request.params.proxyOnly && VpnService.prepare(this) != null -> abortQuickConnect(killSwitch = false)
                    else -> {
                        setUserOff(false)
                        setState(SessionState.RECONNECTING)
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
        ensureForeground()
        // Auto-connect unless the user turned the VPN off: the flag file covers process restarts (the static
        // userRequestedDisconnect is false in a fresh process, but the user's choice must survive).
        if (request != null && !userRequestedDisconnect.get() && !store.userOff() && !isRunning.get() &&
            (request.params.proxyOnly || VpnService.prepare(this) == null)
        ) {
            setState(SessionState.RECONNECTING)
            startQuick(request)
            return START_STICKY
        }
        // Nothing to start: the service doesn't stay in the foreground for an off VPN.
        stopIfIdle()
        return START_STICKY
    }

    /** The session's parameters: the fields derived from them follow ([heartbeatProbe], [showNotification], …). */
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

    /** "Turned off by the user", in memory and on disk (boot and a system restart read the file). */
    private fun setUserOff(off: Boolean) {
        userRequestedDisconnect.set(off)
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
    private fun extractSocksFromConfig(configJson: String, engine: String): Pair<String, String> =
        VpnCores.get(CoreKind.fromId(engine)).socksCredentials(configJson)

    private fun openApp() {
        packageManager.getLaunchIntentForPackage(packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ?.let { startActivity(it) }
    }

    private fun startVpn(request: StartRequest) {
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
        if (!isRunning.compareAndSet(false, true)) return
        val notificationTypeChanged = showNotification != request.params.showNotification
        useParams(request.params)
        // The previous session's notification type stayed until here: switch the foreground one to this session's.
        if (notificationTypeChanged) ensureForeground()
        sessionCore = VpnCores.get(CoreKind.fromId(engine))
        VpnCores.active = sessionCore
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
        if (!isReconnect) clearLogFile()
        setState(if (isReconnect) SessionState.RECONNECTING else SessionState.CONNECTING)
        log("info", "Starting VPN (MTU: $tunMtu)")

        try {
            // Enable prefix proxy only when the ss:// URL contains ?prefix=.
            val finalConfig = if (ssPrefix != null) {
                injectPrefixProxy(xrayConfig, ssPrefix) ?: xrayConfig
            } else {
                xrayConfig
            }

            // For a quick start (tile, boot, reconnect): the params, the config and its SOCKS login together, then
            // the tile's name. A failed save costs the quick start, not this session. Saved on a reconnect too: the
            // config it runs may differ from the stored one (a new prefix proxy port).
            try {
                store.save(finalConfig, request.params, socksUser, socksPassword)
                if (!request.reconnect) VpnTileService.saveConfigName(this, request.configName)
            } catch (e: Exception) {
                log("warning", "Quick-connect data not saved: ${e.message}")
            }
            prepareBinaries(this)

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

                log("info", "xray started (proxy-only, SOCKS on port $socksPort)")
                startStatsMonitoring()
                setConnected(socksPort, socksUser, socksPassword)
                startHeartbeat(isReconnect)
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

                    if (vpnMode == "onlySelected") {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            for (pkg in includedPackages) {
                                try {
                                    builder.addAllowedApplication(pkg)
                                } catch (e: Exception) {
                                    log("warning", "Failed to allow $pkg: ${e.message}")
                                }
                            }
                        } else {
                            log("warning", "onlySelected mode requires Android 10+, falling back to allExcept")
                            for (pkg in excludedPackages) {
                                try { builder.addDisallowedApplication(pkg) } catch (_: Exception) {}
                            }
                            try { builder.addDisallowedApplication(packageName) } catch (_: Exception) {}
                        }
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

                // No permanent wakelock: TUN packets wake the CPU by themselves, and
                // reconnectInternal() takes its own timed wakelock for the cycle. In deep
                // Doze the heartbeat stretches — checkTunStallOnWake() covers wake-up.
                startStatsMonitoring()
                registerNetworkCallback()
                setConnected(socksPort, socksUser, socksPassword)
                startHeartbeat(isReconnect)
                log("info", "VPN connected successfully")
            }
        } catch (e: Throwable) {
            // Throwable: the core's UnsatisfiedLinkError/ExceptionInInitializerError must also
            // return the service to the stopped state.
            log("error", "Start failed: ${e.message}")
            // If no new TUN was established, restore the old fd: as kill-switch sink
            // (keeps blocking traffic) and/or for reuse by the next reconnect attempt.
            // Otherwise the old fd is obsolete.
            if (tunInterface == null && previousTun != null && (killSwitch || isReconnect) && !proxyOnly) {
                tunInterface = previousTun
                tunParams = previousTunParams
            } else {
                try { previousTun?.close() } catch (_: Exception) {}
            }
            val willRetry = isReconnect && !userRequestedDisconnect.get()
                    && reconnectAttempts.incrementAndGet() <= MAX_RECONNECT_ATTEMPTS
            // On final failure with kill switch keep the sink (explicit=false) so
            // traffic stays blocked instead of silently leaking past the VPN.
            stopVpn(resultState = SessionState.ERROR, explicit = !willRetry && !keepSinkOnFailure, reconnecting = willRetry,
                error = if (willRetry) null else e.message ?: e.javaClass.simpleName)
            if (willRetry) {
                val attempt = reconnectAttempts.get()
                val delayMs = RECONNECT_RETRY_BASE_MS * attempt
                log("warning", "Reconnect attempt $attempt/$MAX_RECONNECT_ATTEMPTS failed, retrying in ${delayMs}ms")
                try { Thread.sleep(delayMs) } catch (_: InterruptedException) { return }
                if (!userRequestedDisconnect.get() && !isRunning.get()) {
                    startService(Intent(this, XrayVpnService::class.java).setAction(ACTION_CONNECT_QUICK))
                }
            }
        }
    }

    /**
     * Resolves UIDs for the given package lists based on vpnMode.
     * In "onlySelected" mode returns allowed UIDs; otherwise returns excluded UIDs
     * (including the app's own UID to prevent routing loops).
     */
    private fun resolveUids(
        vpnMode: String,
        includedPackages: List<String>,
        excludedPackages: List<String>,
    ): Set<Int> {
        val uids = mutableSetOf<Int>()
        val packages = if (vpnMode == "onlySelected") includedPackages else excludedPackages
        for (pkg in packages) {
            try {
                val uid = packageManager.getPackageUid(pkg, PackageManager.GET_META_DATA)
                uids.add(uid)
                log("info", "${if (vpnMode == "onlySelected") "Allowed" else "Excluded"} UID for $pkg: $uid")
            } catch (e: Exception) {
                log("warning", "Failed to get UID for $pkg: ${e.message}")
            }
        }

        try {
            val ownUid = packageManager.getPackageUid(packageName, PackageManager.GET_META_DATA)
            if (vpnMode == "onlySelected") {
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
        // Prevent START_STICKY auto-reconnect while the user is e.g. on a phone call.
        // The user did not request disconnect, but we must not reconnect until they explicitly
        // connect again — VPN permission may be temporarily revoked by the system.
        userRequestedDisconnect.set(true)
        stopVpn(explicit = true)
        // Force state update in case stopVpn returned early (isRunning was already false
        // during a reconnect cycle when the user tapped the system VPN popup).
        setState(SessionState.DISCONNECTED)
        stopSelf()
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
        stopHeartbeat()
        tunModeActive = false
        lastUnderlyingNetwork = null
        lastConnectedMs = 0L
        pendingNetworkRunnable?.let { networkChangeHandler.removeCallbacks(it) }
        pendingNetworkRunnable = null
        pendingForce = false

        var keptTunAsSink = false
        try {
            try { unregisterNetworkCallback() } catch (e: Exception) {
                log("warning", "unregisterNetworkCallback failed: ${e.message}")
            }

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
                    && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
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
            if (keptTunAsSink && !reconnecting) showBlockedNotification()
            log("info", "stopVpn: done (state=${finalState.wire})")
            flushLogBuffer(filesDir)
        }
    }

    override fun onDestroy() {
        destroyed = true
        try { unregisterReceiver(screenReceiver) } catch (_: Exception) {}
        screenReceiver = null
        stopVpn()
        // stopVpn posted "Disconnected" — after the service dies it would remain an orphan.
        try { (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIFICATION_ID) } catch (_: Exception) {}
        flushLogBuffer(filesDir)
        super.onDestroy()
    }

    private fun registerScreenReceiver() {
        screenReceiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(context: android.content.Context, intent: android.content.Intent) {
                when (intent.action) {
                    android.content.Intent.ACTION_SCREEN_OFF -> {
                        screenOn = false
                        log("info", "Screen off")
                    }
                    android.content.Intent.ACTION_SCREEN_ON  -> {
                        screenOn = true
                        log("info", "Screen on")
                        // Notification updates are suppressed while the screen is off —
                        // refresh once so the shade shows current speeds immediately.
                        if (isRunning.get() && snapshot.state == SessionState.CONNECTED) {
                            lastNotificationText = null
                            updateNotification(lastUploadSpeed, lastDownloadSpeed)
                        }
                        checkTunStallOnWake()
                    }
                    android.os.PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED -> {
                        val pm = context.getSystemService(POWER_SERVICE) as PowerManager
                        val idle = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) pm.isDeviceIdleMode else false
                        deviceIdle = idle
                        log("info", "Doze mode: ${if (idle) "entered" else "exited"}")
                        // Leaving Doze = a maintenance window or wake-up: if TUN
                        // was silent for long, the tunnel might have gone stale — probe as on SCREEN_ON.
                        if (!idle) checkTunStallOnWake()
                    }
                }
            }
        }
        val filter = android.content.IntentFilter().apply {
            addAction(android.content.Intent.ACTION_SCREEN_OFF)
            addAction(android.content.Intent.ACTION_SCREEN_ON)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                addAction(android.os.PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
            }
        }
        registerReceiver(screenReceiver, filter)
    }

    private fun checkTunStallOnWake() {
        if (!tunModeActive || !isRunning.get()) return
        val lastRx = core.lastRxActivityMs()
        if (lastRx <= 0) return
        val idleSec = (System.currentTimeMillis() - lastRx) / 1000
        if (idleSec < TUN_STALL_TIMEOUT_MS / 1000) return
        // Don't require activeConns >= 2: after Doze, connections drain to 0 naturally
        // but the tunnel session (xray upstream) may be stale for new connections.
        // Idle alone isn't proof of death though — probe the upstream through xray
        // and reconnect only if it actually fails (issue #81: blind reconnects on
        // every wake). onReceive runs on the main thread, so probe off-thread.
        if (heartbeatProbe == "passive") return
        if (!wakeProbeRunning.compareAndSet(false, true)) return
        Thread {
            try {
                val port = snapshot.socksPort
                if (port <= 0) return@Thread
                try {
                    runProbe(port)
                    log("info", "TUN idle ${idleSec}s on wake but tunnel alive, skipping reconnect")
                } catch (e: Exception) {
                    log("warning", "TUN stall on wake: no data for ${idleSec}s, probe failed (${e.message}), reconnecting")
                    reconnectInternal()
                }
            } finally {
                wakeProbeRunning.set(false)
            }
        }.also { it.isDaemon = true; it.start() }
    }

    private fun startStatsMonitoring() {
        var lastUp = 0L
        var lastDown = 0L
        var lastTime = System.currentTimeMillis()

        totalUpload = 0
        totalDownload = 0
        lastUploadSpeed = 0
        lastDownloadSpeed = 0
        lastUp = 0
        lastDown = 0
        lastTime = System.currentTimeMillis()
        speedHistory.reset()

        statsThread = Thread {
            while (isRunning.get()) {
                try {
                    // Nobody looks at speeds while the screen is off — poll 10x slower so
                    // the CPU isn't woken every second all night. Totals stay exact
                    // (cumulative counters), speeds average over the longer interval.
                    val wasScreenOn = screenOn
                    Thread.sleep(if (wasScreenOn) STATS_INTERVAL_MS else STATS_INTERVAL_SCREEN_OFF_MS)
                    // Bound to the session seen dead: a connect that replaced it meanwhile isn't stopped.
                    val session = lastConnectedMs
                    if (tunDied()) {
                        log("warning", "tun2socks stopped while connected, reconnecting")
                        reconnectInternal(session)
                        break
                    }
                    val now = System.currentTimeMillis()
                    val elapsed = (now - lastTime) / 1000.0

                    val currentTx = core.uploadBytes()
                    val currentRx = core.downloadBytes()

                    totalUpload = currentTx
                    totalDownload = currentRx

                    if (elapsed > 0) {
                        lastUploadSpeed = ((currentTx - lastUp) / elapsed).toLong().coerceAtLeast(0)
                        lastDownloadSpeed = ((currentRx - lastDown) / elapsed).toLong().coerceAtLeast(0)
                    }
                    lastUp = totalUpload
                    lastDown = totalDownload
                    lastTime = now
                    if (screenOn) {
                        speedHistory.add(lastUploadSpeed, lastDownloadSpeed)
                        updateNotification(lastUploadSpeed, lastDownloadSpeed)
                    }
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

    private fun registerNetworkCallback() {
        try {
            val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
            // Pre-seed lastUnderlyingNetwork before registering so the initial onAvailable
            // callback sees prev == current and does NOT trigger a spurious reconnect.
            updateUnderlyingNetworks(cm)
            networkCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    log("info", "Network available: $network")
                    val prev = lastUnderlyingNetwork
                    updateUnderlyingNetworks(cm)
                    val current = lastUnderlyingNetwork
                    // Trigger if network changed (prev→current) OR if prev was null but we now
                    // have a network (covers WiFi→LTE when onLost fired before onAvailable).
                    if (current != null && prev != current) {
                        scheduleNetworkChanged(switched = true)
                    }
                }

                override fun onLost(network: Network) {
                    log("info", "Network lost: $network")
                    // Force-close all active tun2socks connections immediately on network loss.
                    // Stale gVisor TCP connections survive across brief network blips and cause
                    // app-level freezes (Telegram, etc.) because the SOCKS5 heartbeat cannot
                    // observe per-connection gVisor state. Closing them now forces apps to
                    // reconnect through a clean path when the network comes back.
                    if (tunModeActive && isRunning.get()) {
                        val closed = core.closeAllConnections()
                        if (closed > 0) log("debug", "Network lost: force-closed $closed TUN connections")
                    }
                    // Snapshot BEFORE clearing — needed for smooth-handover case where
                    // onAvailable(LTE) fires before onLost(WiFi): prev=wifi, after=LTE → trigger.
                    val prev = lastUnderlyingNetwork
                    if (lastUnderlyingNetwork == network) {
                        lastUnderlyingNetwork = null
                    }
                    updateUnderlyingNetworks(cm)
                    if (prev != null && lastUnderlyingNetwork != null && prev != lastUnderlyingNetwork) {
                        scheduleNetworkChanged(switched = true)
                    }
                }

                override fun onCapabilitiesChanged(
                    network: Network,
                    networkCapabilities: NetworkCapabilities
                ) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        if (cm.activeNetwork == network) {
                            val prev = lastUnderlyingNetwork
                            updateUnderlyingNetworks(cm)
                            // Captive portal / temporary internet loss: VALIDATED is removed
                            // without triggering onLost/onAvailable — detect and reconnect.
                            val validated = networkCapabilities.hasCapability(
                                NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                            // The network became the default only after onAvailable (LTE → Wi-Fi after
                            // airplane mode): the core's sockets stayed on the previous network.
                            val switched = prev != null && lastUnderlyingNetwork != null &&
                                prev != lastUnderlyingNetwork
                            if (!validated) scheduleNetworkChanged()
                            else if (switched) scheduleNetworkChanged(switched = true)
                        }
                    }
                }
            }
            val request = NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()
            cm.registerNetworkCallback(request, networkCallback!!)
        } catch (e: Exception) {
            log("warning", "Failed to register network callback: ${e.message}")
        }
    }

    private fun findPhysicalNetwork(): Network? {
        val cm = getSystemService(ConnectivityManager::class.java)
        val activeNetwork = cm.activeNetwork ?: return null

        val caps = cm.getNetworkCapabilities(activeNetwork)
        if (caps == null || caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
            // Active is VPN — pick a physical internet network: VALIDATED first (Wi-Fi
            // without internet must not win over working LTE), then Wi-Fi over others.
            return try {
                cm.allNetworks.mapNotNull { n -> cm.getNetworkCapabilities(n)?.let { n to it } }
                    .filter { (_, c) ->
                        c.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                            !c.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
                    }
                    .maxByOrNull { (_, c) ->
                        (if (c.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) 2 else 0) +
                            (if (c.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) 1 else 0)
                    }?.first
            } catch (e: Exception) { null }
        }

        // Active is not VPN — use it (WiFi or LTE)
        return activeNetwork
    }

    private fun updateUnderlyingNetworks(cm: ConnectivityManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val activeNetwork = cm.activeNetwork ?: run {
                setUnderlyingNetworks(null)
                lastUnderlyingNetwork = null
                return
            }

            // Use findPhysicalNetwork to get WiFi/LTE (not VPN)
            val physicalNetwork = findPhysicalNetwork()
            if (physicalNetwork == null) {
                if (lastUnderlyingNetwork != null) {
                    setUnderlyingNetworks(null)
                    lastUnderlyingNetwork = null
                    log("info", "All underlying networks lost")
                }
                return
            }

            if (physicalNetwork == lastUnderlyingNetwork) return
            lastUnderlyingNetwork = physicalNetwork
            setUnderlyingNetworks(arrayOf(physicalNetwork))
            log("info", "Underlying network set to physical: $physicalNetwork")
        }
    }

    /// [switched] — the physical network changed: before reconnecting compare with the network
    /// we connected on (back on it — the core's sockets are alive, no reconnect needed).
    private fun scheduleNetworkChanged(switched: Boolean = false) {
        // Only reconnect when fully connected — prevents spurious reconnects during the
        // initial startVpn() phase when onAvailable fires right after registration.
        if (snapshot.state != SessionState.CONNECTED) return
        // On mobile data Android fires onAvailable/onCapabilitiesChanged right after VPN
        // connects. In the first 5 s we don't reconnect right away: when the window ends we compare
        // the physical network with the connection network — a real change isn't lost.
        val session = lastConnectedMs
        val msSinceConnect = System.currentTimeMillis() - session
        val settling = session > 0 && msSinceConnect < 5_000L
        // A loss of VALIDATED outside the window — a reconnect is mandatory, even if a network
        // change event follows and the network turns out to be the same.
        if (!switched && !settling) pendingForce = true
        val checkNetwork = (switched || settling) && !pendingForce
        val delay = if (settling) 5_000L - msSinceConnect + RECONNECT_DEBOUNCE_MS else RECONNECT_DEBOUNCE_MS
        log(if (settling) "debug" else "info",
            "Network change: ${if (checkNetwork) "check" else "reconnect"} scheduled in ${delay}ms")
        pendingNetworkRunnable?.let { networkChangeHandler.removeCallbacks(it) }
        val r = Runnable {
            val force = pendingForce
            pendingForce = false
            if (snapshot.state != SessionState.CONNECTED || lastConnectedMs != session) return@Runnable
            if (checkNetwork && !force) {
                val now = findPhysicalNetwork() ?: return@Runnable
                if (now == connectedNetwork) {
                    log("debug", "Network change: still on $now, no reconnect")
                    return@Runnable
                }
                log("info", "Network change: ${connectedNetwork ?: "unknown"} → $now, reconnecting")
            }
            reconnectInternal(session)
        }
        pendingNetworkRunnable = r
        networkChangeHandler.postDelayed(r, delay)
    }

    /// Restart from saved parameters (CONNECT_QUICK, system restart) — queued in [sessionCommands] after the
    /// commands received before it. Won't begin on top of a live session or after the user disconnected.
    private fun startQuick(request: StartRequest) {
        // Not queued after the user disconnected: it would only skip itself, and as a start received after the
        // disconnect it would take the disconnect's final state.
        if (userRequestedDisconnect.get()) {
            log("info", "quick start skipped: disconnected by user")
            return
        }
        sessionCommands.submit(SessionCommands.Kind.QUICK) {
            if (userRequestedDisconnect.get() || isRunning.get()) {
                log("info", "quick start skipped (disconnected by user or already running)")
                return@submit
            }
            sessionAttempt = request.attempt
            startVpn(request)
        }
    }

    /// [session] — `lastConnectedMs` of the session the reconnect is scheduled for;
    /// a new session (ACTION_CONNECT) cancels it. 0 — not bound.
    private fun reconnectInternal(session: Long = 0L) {
        if (userRequestedDisconnect.get()) return
        if (!isRunning.get()) return
        networkChangeHandler.post {
            if (userRequestedDisconnect.get() || !isRunning.get()) return@post
            if (session != 0L && lastConnectedMs != session) return@post
            log("info", "reconnectInternal: starting reconnect cycle")
            reconnectAttempts.set(0)
            Thread {
                // Hold a WakeLock for the entire reconnect cycle so the CPU can't sleep
                // between stopVpn() releasing the main WakeLock and CONNECT_QUICK acquiring it.
                val reconnectWakeLock = try {
                    (getSystemService(POWER_SERVICE) as PowerManager)
                        .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "TeapodStream:Reconnect")
                        .also { it.acquire(40_000) }
                } catch (_: Exception) { null }
                try {
                    val stopped = synchronized(sessionLock) {
                        if (session != 0L && lastConnectedMs != session) false
                        else { stopVpn(reconnecting = true); true }
                    }
                    if (!stopped) {
                        log("info", "reconnectInternal: session replaced, skipped")
                        return@Thread
                    }
                    log("info", "reconnectInternal: waiting for direct internet (deadline +30s)")
                    val deadline = System.currentTimeMillis() + 30_000
                    while (!userRequestedDisconnect.get() && System.currentTimeMillis() < deadline) {
                        if (hasDirectInternet()) {
                            log("info", "reconnectInternal: internet available, launching CONNECT_QUICK")
                            break
                        }
                        Thread.sleep(RECONNECT_DEBOUNCE_MS)
                    }
                    if (userRequestedDisconnect.get()) {
                        log("info", "reconnectInternal: cancelled (user disconnect)")
                        return@Thread
                    }
                    if (System.currentTimeMillis() >= deadline) {
                        log("info", "reconnectInternal: internet wait expired, launching CONNECT_QUICK anyway")
                    }
                    val intent = Intent(this@XrayVpnService, XrayVpnService::class.java)
                        .setAction(ACTION_CONNECT_QUICK)
                    startService(intent)
                } finally {
                    try { reconnectWakeLock?.release() } catch (_: Exception) {}
                }
            }.start()
        }
    }

    // Returns true if the physical network (not through VPN) can reach 8.8.8.8:53.
    // The VpnService process UID is excluded from the tunnel, so sockets here bypass TUN.
    // bindSocket() additionally pins the socket to the physical interface, avoiding
    // stale routing state during WiFi→LTE handover.
    private fun hasDirectInternet(): Boolean = try {
        Socket().use { socket ->
            findPhysicalNetwork()?.bindSocket(socket)
            socket.connect(InetSocketAddress(CONNECTIVITY_CHECK_HOST, 53), RECONNECT_DEBOUNCE_MS.toInt())
            true
        }
    } catch (_: Exception) { false }

    /// Failure limit reached. Returns true if the heartbeat loop continues
    /// (false alarm or we wait for Flutter to pick another config), false — a reconnect
    /// was started and the thread must finish.
    private fun handleHeartbeatExhausted(failures: Int, reason: String): Boolean {
        // Probe rides through the routing balancer and can land on a dead detour while
        // real traffic flows fine — a false positive. If the TUN saw downstream data
        // within the last probe interval, keep the session and just reset the counter.
        if (isTunRxFresh()) {
            log("warning", "Heartbeat failing but TUN traffic is alive, skipping reconnect")
            heartbeatFailures.set(0)
            return true
        }
        if (heartbeatAction == "switchConfig") {
            val now = System.currentTimeMillis()
            if (now - lastTunnelDeadNotifyAt >= TUNNEL_DEAD_NOTIFY_COOLDOWN_MS) {
                lastTunnelDeadNotifyAt = now
                log("warning", "$reason (failures: $failures) → picking another config")
                VpnEventStreamHandler.sendTunnelDeadEvent(failures)
                heartbeatFailures.set(0)
                return true
            }
            // Flutter didn't react within the cooldown (app killed / no live
            // candidates) — degrade to a plain reconnect of the current server.
            log("warning", "switchConfig: no switch within cooldown, falling back to reconnect")
        }
        log("warning", "$reason (failures: $failures) → reconnect")
        reconnectInternal()
        return false
    }

    private fun startHeartbeat(isReconnect: Boolean = false) {
        log("info", "startHeartbeat (isReconnect=$isReconnect)")
        heartbeatThread?.interrupt()
        heartbeatFailures.set(0)
        lastTunnelDeadNotifyAt = 0L
        heartbeatThread = Thread {
            // In reconnect mode: probes run every 15 s but failures are ignored until the
            // first probe succeeds (warmup). This self-adjusts to actual network conditions —
            // no magic fixed delay. Hard ceiling: warmupDeadline prevents staying in warmup
            // forever if the server is genuinely unreachable.
            var warmupDone = !isReconnect
            var warmupDeadline = 0L  // set on first probe iteration, not at thread start
            // Counts consecutive skips due to no physical internet. When internet returns
            // after a long absence the tunnel session is stale regardless of protocol, so
            // the first probe failure should immediately trigger a reconnect.
            var noInternetStreak = 0
            var successCount = 0
            var lastStallWarnAt = 0L

            while (!Thread.currentThread().isInterrupted && isRunning.get()) {
                try {
                    // Warmup keeps the fast cadence: after a reconnect the first success
                    // must be detected promptly regardless of screen state.
                    Thread.sleep(
                        if (screenOn || !warmupDone) HEARTBEAT_INTERVAL_MS
                        else HEARTBEAT_INTERVAL_SCREEN_OFF_MS
                    )
                    if (!isRunning.get()) break
                    // Deep Doze: don't wake the radio with probes — counters are untouched,
                    // on leaving idle (maintenance window) the receiver probes.
                    if (deviceIdle) continue
                    // Start deadline from first actual probe — not from thread creation,
                    // which may be long before xray is ready after a slow reconnect.
                    if (!warmupDone && warmupDeadline == 0L) {
                        warmupDeadline = System.currentTimeMillis() + HEARTBEAT_WARMUP_TIMEOUT_MS
                    }
                    val port = snapshot.socksPort
                    if (port <= 0) continue

                    // Check tun2socks is alive before testing SOCKS5 connectivity.
                    // The SOCKS5 probe bypasses TUN entirely, so it passes even if tun2socks
                    // has crashed or its goroutines are deadlocked.
                    // Skip in proxy-only mode: tun2socks is intentionally not started.
                    if (tunModeActive && !core.isTunRunning()) {
                        log("warning", "tun2socks not running, reconnecting")
                        reconnectInternal()
                        break
                    }

                    // Detect gVisor connection table leak: if the number of active proxy
                    // goroutines is abnormally high the TCP state machine is accumulating
                    // stale entries (TIME_WAIT / CLOSE_WAIT). Reconnect to reset gVisor.
                    if (tunModeActive) {
                        val activeConns = core.activeConnections()
                        if (activeConns > TUN_CONN_LEAK_THRESHOLD) {
                            log("warning", "gVisor connection leak detected (activeConns=$activeConns), reconnecting")
                            reconnectInternal()
                            break
                        }
                    }

                    // Data reached the TUN within the last interval — the tunnel is
                    // demonstrably alive, no need to burn a radio round-trip on an
                    // active probe. Idle tunnels still get the full probe, except in
                    // passive mode: there are no active probes at all, drops are caught by
                    // the TUN stall watchdog and the tun2socks checks above.
                    if (heartbeatProbe != "passive" && !isTunRxFresh()) {
                        runProbe(port)
                    }
                    warmupDone = true
                    heartbeatFailures.set(0)
                    noInternetStreak = 0
                    successCount++
                    if (successCount % 5 == 0) {
                        val activeConns = if (tunModeActive) core.activeConnections() else 0L
                        log("info", "Heartbeat alive (${successCount} ok, tun=${core.isTunRunning()}, conns=$activeConns)")
                    }
                    // Log detailed tunnel stats every ~1 minute for diagnostics.
                    // getTunStatsLine() returns a Go string → log() routes it to
                    // vpn_log.txt + Flutter EventChannel (not only logcat).
                    if (tunModeActive && successCount % 4 == 0) {
                        val stats = core.statsLine()
                        if (stats.isNotEmpty()) {
                            val lastRx = core.lastRxActivityMs()
                            val lastRxSec = if (lastRx > 0) (System.currentTimeMillis() - lastRx) / 1000 else -1
                            log("debug", "tun stats: $stats lastRxSec=$lastRxSec")
                        }
                    }
                    // Detect TUN-layer stall: SOCKS5 heartbeat bypasses tun2socks entirely,
                    // so it passes even when proxy goroutines are alive but no data reaches
                    // the TUN interface (e.g. xray connections half-open, held by keepalives).
                    // getTunLastRxActivityMs() is updated on every TUN write in tun2socks.
                    if (tunModeActive) {
                        val lastRx = core.lastRxActivityMs()
                        if (lastRx > 0) {
                            val now = System.currentTimeMillis()
                            val idleSec = (now - lastRx) / 1000
                            val activeConns by lazy { core.activeConnections() }
                            when {
                                idleSec >= TUN_STALL_TIMEOUT_MS / 1000 && activeConns >= 2 -> {
                                    if (handleHeartbeatExhausted(
                                            heartbeatThreshold,
                                            "TUN stall: no data for ${idleSec}s (conns=$activeConns)")
                                    ) continue else break
                                }
                                idleSec >= 60 && activeConns >= 2 && now - lastStallWarnAt >= 60_000 -> {
                                    log("warning", "TUN rx idle for ${idleSec}s (conns=$activeConns)")
                                    lastStallWarnAt = now
                                }
                            }
                        }
                    }
                } catch (_: InterruptedException) {
                    break
                } catch (e: Exception) {
                    // If the physical network is down it's not xray's fault — skip failure
                    // count to prevent useless reconnect cycles during WiFi→LTE transitions.
                    // network_changed will trigger a reconnect once the new network is ready.
                    if (!hasDirectInternet()) {
                        noInternetStreak++
                        log("debug", "Heartbeat skipped: no direct internet (streak=$noInternetStreak)")
                        continue
                    }
                    // Network just returned after a long absence — the tunnel session is
                    // guaranteed stale (QUIC/TCP connection to the server was dead while we
                    // had no route). Skip the normal 3-failure wait and reconnect immediately.
                    if (noInternetStreak >= 3) {
                        val absenceSec = noInternetStreak * (HEARTBEAT_INTERVAL_MS / 1000)
                        noInternetStreak = 0
                        log("warning", "Tunnel stale after ${absenceSec}s network absence, reconnecting")
                        reconnectInternal()
                        break
                    }
                    noInternetStreak = 0
                    if (!warmupDone) {
                        if (warmupDeadline == 0L || System.currentTimeMillis() < warmupDeadline) {
                            log("debug", "Heartbeat warmup probe failed: ${e.message}")
                            continue
                        }
                        log("warning", "Heartbeat warmup timed out (30 s), reconnecting")
                        reconnectInternal()
                        break
                    }
                    val failures = heartbeatFailures.incrementAndGet()
                    log("warning", "Heartbeat failed ($failures): ${e.message}")
                    if (failures >= heartbeatThreshold) {
                        if (handleHeartbeatExhausted(failures, "Heartbeat failed")) continue else break
                    }
                    var immediateRetries = 0
                    while (immediateRetries < 2 && !Thread.currentThread().isInterrupted) {
                        try {
                            Thread.sleep(3000)
                            runProbe(snapshot.socksPort)
                            warmupDone = true
                            heartbeatFailures.set(0)
                            break
                        } catch (_: InterruptedException) {
                            break
                        } catch (_: Exception) {
                            immediateRetries++
                        }
                    }
                    if (heartbeatFailures.get() >= heartbeatThreshold) {
                        val n = heartbeatFailures.get()
                        if (handleHeartbeatExhausted(n, "Heartbeat retries exhausted")) continue else break
                    }
                }
            }
        }.also { it.isDaemon = true; it.start() }
    }

    // True when tun2socks wrote data to the TUN within the last heartbeat interval —
    // the tunnel is demonstrably passing traffic even if the probe itself fails.
    private fun isTunRxFresh(): Boolean {
        if (!tunModeActive) return false
        val lastRx = core.lastRxActivityMs()
        return lastRx > 0 && System.currentTimeMillis() - lastRx < HEARTBEAT_INTERVAL_MS
    }

    private fun stopHeartbeat() {
        if (heartbeatThread != null) log("info", "stopHeartbeat: interrupting heartbeat thread")
        heartbeatThread?.interrupt()
        heartbeatThread = null
        heartbeatFailures.set(0)
    }

    /// Active probe of the selected type. Throws on failure —
    /// the heartbeat loop counts it as a failure.
    private fun runProbe(port: Int) {
        when (heartbeatProbe) {
            "passive" -> return   // never reached: the loop doesn't call the probe at all
            "xrayDelay" -> {
                val ms = core.measureDelay(heartbeatUrl)
                if (ms < 0) throw Exception("xray delay probe returned $ms")
                log("debug", "Heartbeat OK (xray delay ${ms}ms)")
            }
            else -> checkTunnelConnectivity(port)
        }
    }

    private fun checkTunnelConnectivity(port: Int) {
        val target = SocksHttpProbe.parseUrl(heartbeatUrl)
        if (target.https) {
            // The probe itself speaks plain HTTP over SOCKS5 — it can't do TLS.
            // For an https URL it's more honest to measure via the core than to fake success.
            val ms = core.measureDelay(heartbeatUrl)
            if (ms < 0) throw Exception("xray delay probe returned $ms")
            log("debug", "Heartbeat OK (https url, measured in core: ${ms}ms)")
            return
        }
        val creds = snapshot
        try {
            SocksHttpProbe.check(port, creds.socksUser, creds.socksPassword, target)
        } catch (e: SocksHttpProbe.Failure) {
            log("warning", "Heartbeat check failed at [${e.stage}]: ${e.message}")
            throw e
        }
        heartbeatFailures.set(0)
        log("debug", "Heartbeat OK")
    }

    private fun unregisterNetworkCallback() {
        try {
            val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
            networkCallback?.let {
                cm.unregisterNetworkCallback(it)
                networkCallback = null
            }
        } catch (e: Exception) {
            // Ignore
        }
    }

    private fun pendingFlags() =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else
            PendingIntent.FLAG_UPDATE_CURRENT

    private fun buildConnectedNotification(uploadSpeed: Long, downloadSpeed: Long): Notification {
        val flags = pendingFlags()
        val stopIntent = PendingIntent.getService(this, 0,
            Intent(this, XrayVpnService::class.java).apply { action = ACTION_DISCONNECT }, flags)
        val openIntent = PendingIntent.getActivity(this, 0,
            packageManager.getLaunchIntentForPackage(packageName)
                ?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), flags)
        val speedText = "↑ ${formatSpeed(uploadSpeed)}  ↓ ${formatSpeed(downloadSpeed)}"
        return baseNotification(this, NOTIFICATION_CHANNEL_ID)
            .setContentText(speedText)
            .setContentIntent(openIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, appString(R.string.action_disconnect), stopIntent)
            .build()
    }

    private fun buildBlockedNotification(): Notification {
        val flags = pendingFlags()
        val connectIntent = PendingIntent.getService(this, 1,
            Intent(this, XrayVpnService::class.java).apply { action = ACTION_CONNECT_QUICK }, flags)
        val openIntent = PendingIntent.getActivity(this, 0,
            packageManager.getLaunchIntentForPackage(packageName)
                ?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), flags)
        return baseNotification(this, NOTIFICATION_CHANNEL_ID)
            .setContentText(appString(R.string.state_kill_switch))
            .setContentIntent(openIntent)
            .addAction(android.R.drawable.ic_media_play, appString(R.string.action_connect), connectIntent)
            .build()
    }

    private fun buildMinimalNotification(): Notification =
        baseNotification(this, NOTIFICATION_CHANNEL_MINIMAL_ID)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .build()

    /** Ensure the service is in foreground. Safe to call multiple times. */
    private fun ensureForeground(connecting: Boolean = true, override: Notification? = null) {
        ensureNotificationChannels(this, getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
        // Intermediate state right away: "Disconnected" during connecting was confusing.
        val notification = override
            ?: if (showNotification) buildIntermediateNotification(this, connecting) else buildMinimalNotification()
        lastIntermediate = if (showNotification && override == null) connecting else null
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            log("warning", "startForeground failed: ${e.message}")
        }
    }

    /** CONNECT_QUICK didn't start (no config or VPN permission): the tile and
     * the notification must not stay on "Connecting…"; the rest is up to the app.
     * After `reconnectInternal` the state is still `connected` and TUN is held as a sink: with the kill
     * switch we keep it as a block, without it we close it. */
    private fun abortQuickConnect(killSwitch: Boolean) {
        val blocked = killSwitch && tunInterface != null
        if (!blocked) closeTunSink()
        setState(if (blocked) SessionState.BLOCKED else SessionState.DISCONNECTED)
        if (blocked) showBlockedNotification()
        openApp()
    }

    /** The kill switch holds the TUN sink: the service stays, its notification offers to connect again. */
    private fun showBlockedNotification() {
        lastIntermediate = null
        if (!showNotification) return
        try {
            val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(NOTIFICATION_ID, buildBlockedNotification())
        } catch (_: Exception) {}
    }

    /**
     * Stops the service once the VPN is off and nothing is held ([serviceIdle]). On the main thread, like
     * onStartCommand: every command it has received is already in the queue, and `stopSelf(lastStartId)`
     * is ignored by the system if a newer intent is on its way.
     */
    private fun stopIfIdle() {
        // The queue first: a command finishing after this read is checked again by afterEach (after its reports were
        // posted); once it reads idle no new command can begin (they are queued here, on the main thread).
        if (sessionCommands.busy() || isRunning.get()) return
        if (!serviceIdle(snapshot.state, tunHeld = tunInterface != null, queueBusy = false)) return
        log("info", "VPN off: the service stops")
        stopSelf(lastStartId)
    }

    /** A state other than connected, tagged with [sessionAttempt]; [error] replaces the failure reason. */
    private fun setState(state: SessionState, error: String? = null) =
        publish { it.moved(state, sessionAttempt, error ?: it.error) }

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
        onStateNotification(this, published.state)
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
        connectedNetwork = lastUnderlyingNetwork
        publish { SessionSnapshot.connected(sessionAttempt, socksPort, socksUser, socksPassword, now) }
        // The "Disconnected"/intermediate notification bypasses the dedupe cache —
        // reset it so the connected layout is always posted.
        lastNotificationText = null
        lastIntermediate = null
        updateNotification(0, 0)
        // If notify() is dropped by the rate limit (tile → intermediate → connected within
        // a fraction of a second), a retry after 2 s guarantees the final look (issue #76).
        networkChangeHandler.postDelayed({
            if (snapshot.state == SessionState.CONNECTED) {
                lastNotificationText = null
                updateNotification(lastUploadSpeed, lastDownloadSpeed)
            }
        }, 2_000)
    }

    private fun updateNotification(uploadSpeed: Long, downloadSpeed: Long) {
        if (!showNotification) return
        // notify() is an IPC into system_server on every call — skip while the screen
        // is off (SCREEN_ON refreshes once) and when the rendered text hasn't changed.
        if (!screenOn) return
        val speedText = "↑ ${formatSpeed(uploadSpeed)}  ↓ ${formatSpeed(downloadSpeed)}"
        if (speedText == lastNotificationText) return
        // Every notify() wakes third-party NotificationListeners (watches, sync) —
        // at most once per 5 s; resetting the cache (null) updates right away.
        val now = android.os.SystemClock.elapsedRealtime()
        if (lastNotificationText != null && now - lastNotificationMs < NOTIFICATION_MIN_INTERVAL_MS) return
        lastNotificationText = speedText
        lastNotificationMs = now

        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildConnectedNotification(uploadSpeed, downloadSpeed))
    }

    private fun log(level: String, message: String) {
        if (!logsEnabled && level != "warning" && level != "error") return
        android.util.Log.i("TeapodVPN", "[$level] $message")
        appendLogLine(level, message)
        if (level != "debug" || BuildConfig.DEBUG) {
            VpnEventStreamHandler.sendLogEvent(level, message)
        }
    }

    private fun appendLogLine(level: String, message: String) {
        try {
            val line = "${System.currentTimeMillis()}|$level|${message.replace("\n", " ")}\n"
            synchronized(LOG_FILE_LOCK) {
                logBuffer.append(line)
                if (level == "warning" || level == "error"
                    || logBuffer.length >= LOG_FLUSH_SIZE_CHARS
                    || System.currentTimeMillis() - lastLogFlushMs >= LOG_FLUSH_INTERVAL_MS
                ) {
                    flushLogBufferLocked(filesDir)
                }
            }
        } catch (_: Exception) {}
    }

    // Rotate instead of wiping: the previous session's log survives one connect,
    // so a hang that forced the user to reconnect can still be diagnosed afterwards.
    private fun clearLogFile() {
        try {
            synchronized(LOG_FILE_LOCK) {
                flushLogBufferLocked(filesDir)
                val current = File(filesDir, LOG_FILE_NAME)
                val prev = File(filesDir, LOG_PREV_FILE_NAME)
                prev.delete()
                if (current.exists() && current.length() > 0) {
                    current.renameTo(prev)
                }
                current.writeText("")
            }
        } catch (_: Exception) {}
    }


}
