import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/interfaces/vpn_engine.dart';
import '../core/models/vpn_config.dart';
import '../core/constants/app_constants.dart';
import '../core/models/vpn_stats.dart';
import '../core/models/connection_fingerprint.dart';
import '../core/models/core_kind.dart';
import '../core/models/heartbeat_settings.dart';
import '../core/models/vpn_log_entry.dart';
import '../core/services/log_service.dart';
import '../core/models/app_settings.dart';
import '../core/services/tunnel_socks.dart';
import '../protocols/xray/xray_engine.dart';
import '../core/cores/core_resolver.dart';
import '../core/cores/engine_options.dart';
import '../core/cores/core_switch.dart';
import 'core_provider.dart';
import 'geo_provider.dart';
import 'settings_provider.dart';
import 'config_provider.dart';
import 'profile_provider.dart';
import 'vpn_session.dart';
import '../l10n/l10n.dart';

class VpnState2 {
  final VpnState connectionState;
  final VpnStats stats;
  final String? error;
  final int activeSocksPort;
  final String activeSocksUser;
  final String activeSocksPassword;

  /// Fingerprint of the settings the current connection was established with.
  /// null — no active connection or the fingerprint is unknown.
  final String? appliedFingerprint;

  const VpnState2({
    this.connectionState = VpnState.disconnected,
    this.stats = const VpnStats(),
    this.error,
    this.activeSocksPort = 0,
    this.activeSocksUser = '',
    this.activeSocksPassword = '',
    this.appliedFingerprint,
  });

  bool get isConnected => connectionState == VpnState.connected;
  bool get isConnecting => connectionState == VpnState.connecting;
  bool get isDisconnecting => connectionState == VpnState.disconnecting;
  bool get isBlocked => connectionState == VpnState.blocked;
  bool get isError => connectionState == VpnState.error;
  bool get isBusy => isConnecting || isDisconnecting;

  /// Tunnel SOCKS for the app's own downloads; null — VPN not connected.
  TunnelSocks? get tunnelSocks =>
      isConnected && activeSocksPort > 0 ? TunnelSocks(activeSocksPort, activeSocksUser, activeSocksPassword) : null;

  /// The stats and the fingerprint; the connection state and its reason come only from [VpnSession.view].
  VpnState2 copyWith({VpnStats? stats, String? appliedFingerprint}) {
    return VpnState2(
      connectionState: connectionState,
      stats: stats ?? this.stats,
      error: error,
      activeSocksPort: activeSocksPort,
      activeSocksUser: activeSocksUser,
      activeSocksPassword: activeSocksPassword,
      appliedFingerprint: appliedFingerprint ?? this.appliedFingerprint,
    );
  }
}

/// Tunnel SOCKS for own downloads (subscriptions, geo databases); null — VPN not connected.
/// [VpnNotifier] fills it rather than it watching [vpnProvider]: configProvider reads it, and
/// vpnProvider depends on configProvider through activeCoreProvider — a watch would close a cycle.
final tunnelSocksProvider = NotifierProvider<TunnelSocksNotifier, TunnelSocks?>(TunnelSocksNotifier.new);

class TunnelSocksNotifier extends Notifier<TunnelSocks?> {
  @override
  TunnelSocks? build() => null;

  /// Only a real change is written: the first call comes while vpnProvider is built inside a widget build, where
  /// notifying other providers isn't allowed.
  void set(TunnelSocks? socks) {
    final cur = state;
    if (cur?.port == socks?.port && cur?.user == socks?.user && cur?.password == socks?.password) return;
    state = socks;
  }
}

class VpnNotifier extends Notifier<VpnState2> {
  late final XrayEngine _engine;

  StreamSubscription<dynamic>? _eventSub;
  Timer? _statsPoller;
  bool _isPinging = false;
  bool _urltestRunning = false;
  DateTime? _connectedAt;

  /// true — the home tab is on screen; chart history is pulled only then.
  bool _chartVisible = true;

  /// Chart history: native returns only points after `_historySeq` of epoch
  /// `_historyEpoch`; any lag (background, hidden tab longer than the buffer, a new
  /// session) arrives in one response — the chart catches up immediately.
  static const _maxHistory = 300;
  int _historyEpoch = -1;
  int _historySeq = 0;
  bool _historyFetching = false;

  /// The last list set: if state holds a different one, it was reset (disconnect,
  /// timeout) — nothing to append to, the whole buffer is needed.
  List<SpeedPoint> _history = const [];

  /// The config the app started the tunnel with; null — unknown (VPN brought up
  /// by the tile/autostart or disconnected). The subscription's effective config may change
  /// after a ping while the tunnel keeps running on the previous one.
  VpnConfig? _connectedConfig;

  /// The tunnel already runs on [c]: same id and URI (editing the URI keeps the id), not
  /// mid-switch — the selection needs no reconnect.
  bool runsConfig(VpnConfig c) =>
      state.isConnected && _connectedConfig?.id == c.id && _connectedConfig?.rawUri == c.rawUri;

  @override
  VpnState2 build() {
    _engine = ref.read(xrayEngineProvider);
    listenSelf((_, next) => ref.read(tunnelSocksProvider.notifier).set(next.tunnelSocks));
    // The active profile's core changed (priority, disabling, pinning).
    ref.listen(activeCoreProvider, (prev, next) {
      if (prev != null && next != null && prev != next && !_profileSwitching) _onCoreChanged();
    });

    _eventSub = XrayEngine.events.listen(
      (dynamic event) {
        if (event is Map) {
          _handleEvent(Map<String, dynamic>.from(event));
        }
      },
      onError: (dynamic error) {
        ref.read(logServiceProvider.notifier).addError('Event channel error: $error');
      },
    );

    ref.onDispose(() {
      _eventSub?.cancel();
      _deadline?.cancel();
      _statsPoller?.cancel();
    });

    // Subscription auto-refresh: at startup (below in a microtask) and on every
    // resume (app.dart → refreshStaleSubscriptionsIfDue) — the hourly background
    // timer is gone, the staleness check decides itself whether it's time to refresh.

    // Sync state on init (for case when VPN is already running from tile/notification)
    Future.microtask(() async {
      try {
        await _syncOnStartup();
      } finally {
        // Only after syncing with native: otherwise tunnelSocks is still empty and the subscription
        // would bypass the tunnel when the VPN is already up (from the tile).
        if (ref.mounted) await refreshStaleSubscriptionsIfDue();
      }
    });

    return const VpnState2();
  }

  Future<void> _syncOnStartup() async {
    // Native persists logsEnabled in its own prefs — resync in case they
    // diverged (fresh install with restored Flutter prefs, etc.).
    final s0 = await ref.read(settingsProvider.future);
    await _engine.setLogsEnabled(s0.logsEnabled);

    // Restore log history (previous + current session files) even when
    // disconnected — needed to diagnose failures that ended the last session.
    final logEntries = await _engine.getLogs();
    if (logEntries.isNotEmpty) {
      ref.read(logServiceProvider.notifier).loadFromEntries(logEntries);
    }

    await syncNativeState();
  }

  void _startStatsPolling() {
    // Prevent duplicate polling
    if (_statsPoller?.isActive == true) return;

    _statsPoller = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (state.connectionState != VpnState.connected) {
        return;
      }
      try {
        final stats = await _engine.getStats();
        _handleStats(
          Map<String, dynamic>.from({
            'upload': stats.upload,
            'download': stats.download,
            'uploadSpeed': stats.uploadSpeed,
            'downloadSpeed': stats.downloadSpeed,
          }),
        );

        // History is needed only for the chart
        if (_chartVisible) await _pullHistory();
      } catch (_) {}
    });
    // Back from background / connected: history right away, not on the next tick.
    if (_chartVisible && state.isConnected) _pullHistory().ignore();
  }

  /// Called from app.dart on tab change: chart history is pulled
  /// only while home is visible; on return — an immediate catch-up.
  void setChartVisible(bool visible) {
    if (_chartVisible == visible) return;
    _chartVisible = visible;
    if (visible && state.isConnected) _pullHistory().ignore();
  }

  /// Subscription staleness check — called at startup and on resume.
  Future<void> refreshStaleSubscriptionsIfDue() async {
    final settings = ref.read(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null);
    if (settings?.subAutoRefresh != true) return;
    await ref.read(configProvider.notifier).refreshStaleSubscriptions(intervalHours: settings!.subAutoRefreshHours);
  }

  void _handleEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    switch (type) {
      case 'state':
        final session = NativeSession.parse(event);
        if (!_applyNative(session)) {
          ref
              .read(logServiceProvider.notifier)
              .addDebug('Ignored ${event['value']} of connect attempt ${session.attempt}');
        }
      case 'log':
        final level = event['level'] as String? ?? 'info';
        final msg = event['message'] as String? ?? '';
        ref
            .read(logServiceProvider.notifier)
            .add(
              VpnLogEntry(
                timestamp: DateTime.now(),
                level: LogLevel.values.firstWhere((e) => e.name == level, orElse: () => LogLevel.info),
                message: msg,
                source: 'xray',
              ),
            );
      case 'stats':
        break; // Ignore stats from EventChannel - we use poller instead
      case 'statsHistory':
        _applyHistory(event);
      case 'tunnel_dead':
        _runConfigSwitch((event['failures'] as num?)?.toInt() ?? 0);
    }
  }

  /// Native heartbeat ran out of attempts and the action is switching configs: measure
  /// candidates and reconnect to the fastest live one. If none is alive —
  /// do nothing, the service reconnects itself on its cooldown.
  Future<void> _runConfigSwitch(int failures) async {
    if (_urltestRunning) return;
    _urltestRunning = true;
    final log = ref.read(logServiceProvider.notifier);
    try {
      final settings = ref.read(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null) ?? const AppSettings();
      if (settings.heartbeat.failAction != HeartbeatFailAction.switchConfig) return;

      final configState = ref.read(configProvider).maybeWhen(data: (d) => d, orElse: () => null);
      if (configState == null) return;
      final current = _resolveEffectiveConfig(configState);
      await ref.read(availableCoresProvider.future);
      final candidates = supportedCandidates(
        _switchCandidates(configState, settings.heartbeat.switchSource, current),
        ref.read(coreResolverProvider),
      );
      if (candidates.isEmpty) {
        log.addError('urltest: no candidates to switch to (failures: $failures)');
        return;
      }

      log.addInfo('urltest: tunnel not responding, checking ${candidates.length} config(s)', source: 'urltest');
      // The measurement goes through a temporary xray instance with the candidate's config: a TCP ping
      // would say "alive" even for a server whose port is open while the protocol is silent.
      // The instance is temporary and Go strips inbounds itself — only fields
      // affecting the outbound matter.
      final options = VpnEngineOptions(
        socksPort: AppConstants.defaultSocksPort,
        socksUser: '',
        socksPassword: '',
        tlsFingerprint: settings.tlsFingerprint,
        fragment: settings.fragment,
        noise: settings.noise,
        mux: settings.mux,
      );
      final probed = await Future.wait(
        candidates.map((c) async {
          final ms = await _engine.measureOutbound(c.config, c.backend, options, settings.heartbeat.url);
          return (config: c.config, latency: ms);
        }),
      );
      final alive = probed.where((r) => r.latency != null).toList()..sort((a, b) => a.latency!.compareTo(b.latency!));
      if (alive.isEmpty) {
        log.addError('urltest: no live configs found, staying on the current one');
        return;
      }

      final best = alive.first;
      log.addInfo('urltest: switching to "${best.config.name}" (${best.latency} ms)', source: 'urltest');
      await ref.read(configProvider.notifier).setActiveConfig(best.config.id);
      // disconnect()+connect() didn't work here: connect() bailed on isBusy
      // (the state was still disconnecting), and the VPN stayed off.
      await reconnectWithNewConfig();
    } catch (e) {
      log.addError('urltest: switch error: $e');
    } finally {
      _urltestRunning = false;
    }
  }

  /// Switch candidates: the active config is excluded — it just failed the probe.
  List<VpnConfig> _switchCandidates(ConfigState configState, SwitchSource source, VpnConfig? current) {
    final all = configState.configs.where((c) => c.id != current?.id);
    return switch (source) {
      SwitchSource.subscription => all.where((c) => c.subscriptionId == current?.subscriptionId).toList(),
      SwitchSource.pinned => all.where(configState.isPinned).toList(),
      SwitchSource.all => all.toList(),
    };
  }

  /// The session: the last native snapshot, what Flutter waits for, a failure it found itself. The state the UI sees
  /// is its [VpnSession.view]; [_setSession] is the only writer of both.
  VpnSession _session = const VpnSession();

  /// The deadline of what Flutter waits for: 45 s for a connect, 10 s for a disconnect.
  Timer? _deadline;

  void _setSession(VpnSession next) {
    _session = next;
    if (next.pending == null) {
      _deadline?.cancel();
      _deadline = null;
    }
    final v = next.view;
    final n = next.native;
    final connected = v.state == VpnState.connected;
    final off = v.state == VpnState.disconnected || v.state == VpnState.error || v.state == VpnState.blocked;
    if (connected) {
      _connectedAt ??= n.connectedAtMs > 0 ? DateTime.fromMillisecondsSinceEpoch(n.connectedAtMs) : DateTime.now();
    } else if (off) {
      _connectedAt = null;
      _connectedConfig = null;
      _statsPoller?.cancel();
    }
    state = VpnState2(
      connectionState: v.state,
      error: v.error,
      stats: off ? const VpnStats() : state.stats,
      activeSocksPort: connected ? n.socksPort : 0,
      activeSocksUser: connected ? n.socksUser : '',
      activeSocksPassword: connected ? n.socksPassword : '',
      appliedFingerprint: off ? null : state.appliedFingerprint,
    );
    // Polling is the backup for when the EventChannel doesn't deliver (app in background).
    if (connected) _startStatsPolling();
  }

  /// Applies a native snapshot ([poll] — from `getState`); false — dropped ([VpnSession.onNative]).
  bool _applyNative(NativeSession s, {bool poll = false}) {
    final next = _session.onNative(s, poll: poll);
    if (next == null) {
      // A reconnect report may have dropped the deadline: the pending connect still ends.
      if (poll) _armConnectDeadline();
      return false;
    }
    if (next.pending is PendingConnect && s.reconnecting) {
      // A native restart of the pending session can outlast the deadline: the service ends it itself.
      _deadline?.cancel();
      _deadline = null;
    }
    _setSession(next);
    return true;
  }

  void _handleStats(Map<String, dynamic> event) {
    // A late response after a drop: copyWith would reset the error/blocked reason.
    if (!state.isConnected) return;
    // Handle both int and Long (from Kotlin)
    final upload = (event['upload'] as num?)?.toInt() ?? 0;
    final download = (event['download'] as num?)?.toInt() ?? 0;
    final uploadSpeed = (event['uploadSpeed'] as num?)?.toInt() ?? 0;
    final downloadSpeed = (event['downloadSpeed'] as num?)?.toInt() ?? 0;

    // Always update speed, even if bytes haven't changed (for re-connect)
    state = state.copyWith(
      stats: state.stats.copyWith(
        uploadBytes: upload,
        downloadBytes: download,
        uploadSpeedBps: uploadSpeed,
        downloadSpeedBps: downloadSpeed,
        connectedDuration: _connectedAt != null ? DateTime.now().difference(_connectedAt!) : Duration.zero,
      ),
    );
  }

  Future<void> _pullHistory() async {
    if (_historyFetching) return;
    _historyFetching = true;
    try {
      final r = await _engine.getStatsHistory(_historyEpoch, _historySeq);
      if (r != null) _applyHistory(r);
    } finally {
      _historyFetching = false;
    }
  }

  /// Native response: `full` replaces the history, otherwise points are appended — only if
  /// they continue the current one (`from == _historySeq`), so a late response doesn't duplicate them.
  /// Any mismatch — the next request asks for the whole buffer.
  void _applyHistory(Map<Object?, Object?> r) {
    if (!state.isConnected) return;
    final full = r['full'] == true;
    final epoch = (r['epoch'] as num?)?.toInt() ?? -1;
    final from = (r['from'] as num?)?.toInt() ?? 0;
    if (!full && (epoch != _historyEpoch || from != _historySeq || !identical(state.stats.speedHistory, _history))) {
      _historyEpoch = -1;
      return;
    }
    final points = (r['history'] as List? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map((m) => SpeedPoint.fromMap(Map<String, dynamic>.from(m)))
        .toList();
    _historyEpoch = epoch;
    _historySeq = (r['seq'] as num?)?.toInt() ?? 0;
    if (!full && points.isEmpty) return;
    final merged = full ? points : [..._history, ...points];
    _history = merged.length > _maxHistory ? merged.sublist(merged.length - _maxHistory) : merged;
    state = state.copyWith(stats: state.stats.copyWith(speedHistory: _history));
  }

  /// The latest connect attempt's id; a newer attempt or a disconnect replaces it. An attempt that is no longer the
  /// latest neither calls native nor writes state. Random and compared for equality only: native keeps the running
  /// session's id for the life of the process, and a notifier recreated with the UI must not reuse it.
  int _attempt = _newAttempt();

  static final _random = Random.secure();
  static int _newAttempt() => (_random.nextInt(1 << 32) << 20 | _random.nextInt(1 << 20)) + 1;

  /// If native never reports the pending connect's outcome, it fails after 45 s. Keeps a running deadline.
  void _armConnectDeadline() {
    _deadline ??= Timer(const Duration(seconds: 45), () {
      _deadline = null;
      final p = _session.pending;
      if (p is! PendingConnect) return;
      _attempt = _newAttempt(); // the timed-out attempt's late answer must not replace the timeout error
      _setSession(
        VpnSession(native: _session.native, failure: SessionFailure(L10n.current.vpnConnectTimeout, p.attempt)),
      );
      _engine.disconnect().ignore();
    });
  }

  /// [switching] — changing server/settings on a live tunnel: native rebuilds
  /// the session without closing TUN. A refusal before the native call keeps the old connection.
  Future<void> connect({bool switching = false}) async {
    // A switch also replaces a session native is still starting.
    if (state.isDisconnecting || ((state.isConnected || state.isConnecting) && !switching)) return;
    final attempt = _attempt = _newAttempt();
    bool superseded() => attempt != _attempt;
    void fail(String reason) {
      if (!superseded()) _failConnect(reason, attempt);
    }

    // The button reacts in the same frame as the tap.
    _deadline?.cancel();
    _deadline = null;
    _setSession(VpnSession(native: _session.native, pending: PendingConnect(attempt)));
    _armConnectDeadline();

    // Notification permission for foreground service (Android 13+) — best-effort
    await Permission.notification.request();
    if (superseded()) return;

    final configState = ref.read(configProvider).maybeWhen(data: (d) => d, orElse: () => null);
    final config = _resolveEffectiveConfig(configState);
    if (config == null) {
      return fail(L10n.current.vpnNoConfigSelected);
    }

    final validationError = config.validate();
    if (validationError != null) return fail(validationError);

    final settings = ref.read(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null) ?? const AppSettings();

    await ref.read(availableCoresProvider.future);
    // The resolver weighs a core's limits on the geosite rules.
    await _loadGeosite();
    if (superseded()) return;
    final resolver = ref.read(coreResolverProvider);
    final geosite = resolver.geosite;
    final resolution = resolver.resolve(config);
    final backend = resolution.backend;
    if (backend == null) return fail(resolution.reason!);
    _logCoreChoice(resolution);

    final credentials = _socksCredentials(settings);
    final options = buildEngineOptions(
      settings,
      config,
      backend,
      socksPort: _socksPort(settings),
      credentials: credentials,
      geosite: geosite,
    );
    final check = backend.checkOptions(config, options);
    if (check.blocking != null) return fail(check.blocking!);
    final missing = missingGeositeCodes(settings.routing, geosite);
    for (final w in [if (missing.isNotEmpty) L10n.current.geositeMissing(missing.join(', ')), ...check.warnings]) {
      ref.read(logServiceProvider.notifier).addWarning(w, source: 'core');
    }

    try {
      await _engine.connect(config, backend, options, attempt: attempt);
      if (superseded()) return;
      _connectedConfig = config;
      if (switching) _connectedAt = null;
      state = state.copyWith(appliedFingerprint: connectionFingerprint(settings, core: backend.kind));
    } on PlatformException catch (e) {
      fail(e.message ?? L10n.current.vpnConnectError);
    }
  }

  /// Waits for geosite.dat's index ([CoreResolver.geosite]); an unreadable file is logged and the rules
  /// go unchecked.
  Future<void> _loadGeosite() async {
    try {
      await ref.read(geositeIndexProvider.future);
    } catch (e) {
      ref.read(logServiceProvider.notifier).addError('geosite.dat: $e');
    }
  }

  /// The connection of [attempt] wasn't started; a running session (a switch) goes on ([VpnSession.view]).
  void _failConnect(String reason, int attempt) {
    ref.read(logServiceProvider.notifier).addError(reason);
    _setSession(VpnSession(native: _session.native, failure: SessionFailure(reason, attempt)));
  }

  /// In TUN mode SOCKS is internal: without a password any app could use it
  /// (an exit into the tunnel, the server IP), so empty manual credentials are replaced
  /// with random ones. In proxy-only an open SOCKS is the user's choice.
  static ({String user, String password}) _socksCredentials(AppSettings s) =>
      s.randomCredentials || (!s.proxyOnly && (s.socksUser.isEmpty || s.socksPassword.isEmpty))
      ? XrayEngine.generateSocksCredentials()
      : (user: s.socksUser, password: s.socksPassword);

  static int _socksPort(AppSettings s) => s.randomPort ? 10000 + Random().nextInt(50000) : s.socksPort;

  /// Log which core runs the profile and why the cores above were skipped.
  void _logCoreChoice(CoreResolution r) {
    final skipped = [
      for (final v in r.verdicts.takeWhile((v) => v.reason != null))
        if (v.reason != CoreResolver.disabledReason) '${v.kind.displayName}: ${v.reason}',
    ];
    ref
        .read(logServiceProvider.notifier)
        .addInfo(
          '${r.backend!.kind.displayName}${r.pinned ? ' (pinned)' : ''}'
          '${skipped.isEmpty ? '' : ' — skipped: ${skipped.join('; ')}'}',
          source: 'core',
        );
  }

  /// The active profile's core changed: disconnect if nothing runs the profile anymore,
  /// otherwise re-save/clear quick-reconnect.
  Future<void> _onCoreChanged() async {
    final settings = ref.read(settingsProvider).value;
    if (settings == null) return;
    final config = _resolveEffectiveConfig(ref.read(configProvider).maybeWhen(data: (d) => d, orElse: () => null));
    final resolution = config == null ? null : ref.read(coreResolverProvider).resolve(config);
    final backend = resolution?.backend;
    final unsupported = config == null ? L10n.current.vpnNoConfigSelected : resolution!.reason;
    try {
      switch (coreSwitchAction(state: state.connectionState, unsupported: unsupported)) {
        case CoreSwitchAction.none:
          break;
        case CoreSwitchAction.disconnect:
          final session = _session.native.attempt;
          await disconnect();
          ref.read(logServiceProvider.notifier).addError('Core: $unsupported');
          // Shown through the stop of that session.
          _setSession(
            VpnSession(
              native: _session.native,
              pending: _session.pending,
              failure: SessionFailure(unsupported!, session),
            ),
          );
        case CoreSwitchAction.saveQuickConnect:
          await _engine.saveQuickConnect(
            config!,
            backend!,
            buildEngineOptions(
              settings,
              config,
              backend,
              socksPort: _socksPort(settings),
              credentials: _socksCredentials(settings),
              geosite: ref.read(coreResolverProvider).geosite,
            ),
          );
        case CoreSwitchAction.clearQuickConnect:
          await _engine.clearQuickConnect();
      }
    } catch (e) {
      ref.read(logServiceProvider.notifier).addError('Core switch: $e');
    }
  }

  Future<void> disconnect() async {
    // A connect still in flight must not dispatch or write state after this — also when native already reported
    // `disconnected` while that connect waited.
    _attempt = _newAttempt();
    if (state.connectionState == VpnState.disconnected || state.isDisconnecting) return;

    _deadline?.cancel();
    _setSession(VpnSession(native: _session.native, pending: const PendingDisconnect()));
    _deadline = Timer(const Duration(seconds: 10), _forceOff);

    try {
      await _engine.disconnect();
    } on PlatformException catch (e) {
      ref.read(logServiceProvider.notifier).addError('Disconnect error: ${e.message}');
      _forceOff();
    }
  }

  /// Native didn't confirm a disconnect: the UI must not stay in `disconnecting`.
  void _forceOff() {
    _deadline?.cancel();
    _deadline = null;
    if (_session.pending is PendingDisconnect) _setSession(VpnSession(failure: _session.failure));
  }

  /// Takes native's state at startup and on resume; restarts the stats polling paused in the background. A session
  /// running without a Flutter connect (tile, boot, a UI restart) is taken as started with the current settings (the
  /// exact ones aren't known): they become `appliedFingerprint`, so the reconnect banner doesn't show falsely.
  Future<void> syncNativeState() async {
    try {
      final native = await _engine.getVpnState();
      if (!ref.mounted) return;
      _applyNative(native, poll: true);
      if (!state.isConnected || state.appliedFingerprint != null) return;
      final s = await ref.read(settingsProvider.future);
      await ref.read(configProvider.future);
      await ref.read(availableCoresProvider.future);
      if (!ref.mounted || !state.isConnected || state.appliedFingerprint != null) return;
      state = state.copyWith(appliedFingerprint: connectionFingerprint(s, core: ref.read(activeCoreProvider)?.kind));
    } catch (_) {}
  }

  Future<void> toggle() async {
    if (state.isBusy) return;
    if (state.isConnected) {
      await disconnect();
    } else {
      await connect();
    }
  }

  /// The user picked [config] (configs list, server picker): it becomes the active one, and a running or starting
  /// session switches to it unless it already runs it (not awaited: the caller only waits for the selection). Returns
  /// why no enabled core can run it (nothing changes then).
  Future<String?> selectConfig(VpnConfig config) async {
    final reason = ref.read(coreResolverProvider).resolve(config).reason;
    if (reason != null) return reason;
    await ref.read(configProvider.notifier).setActiveConfig(config.id);
    // Queued behind earlier selections' reconnects and decided against what runs then: overlapping selections end
    // on the last one saved.
    unawaited(_queued(_followSelection));
    return null;
  }

  /// Makes the tunnel run the active config: a connect in flight is redone, a live tunnel on another config switches,
  /// one on this config stays.
  Future<void> _followSelection() async {
    if (state.isBusy) return reconnectWithNewConfig();
    final config = ref.read(effectiveConfigProvider);
    if (state.isConnected && config != null && !runsConfig(config)) await reconnectWithNewConfig();
  }

  /// Native replaces a running or starting session with the new one; a live tunnel keeps TUN as a sink until the new
  /// one is up.
  Future<void> reconnectWithNewConfig() => connect(switching: state.isConnected || state.isConnecting);

  /// A profile switch changes the settings and the server one after the other: the core resolved
  /// in between belongs to neither profile and must not disconnect the tunnel.
  bool _profileSwitching = false;

  /// Profile switches and config selections run one at a time, each with its reconciliation: a later one can't
  /// start while the earlier one's connect is in flight.
  Future<void> _switches = Future.value();

  Future<void> _queued(Future<void> Function() body) {
    final run = _switches.then((_) => body());
    _switches = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// Runs a profile switch ([body] returns false — nothing switched), then makes the VPN follow the
  /// final state: a profile no core runs disconnects (as a core change does), a live tunnel is
  /// rebuilt if stale, a core change suppressed meanwhile is handled.
  /// Switches to profile [id]; the VPN follows once its settings and server are in place, also when restoring the
  /// server failed: the profile is already switched, and a retry can't — it is active.
  Future<void> switchProfile(String id) =>
      duringProfileSwitch(() => ref.read(profileProvider.notifier).switchProfile(id));

  Future<void> duringProfileSwitch(Future<bool> Function() body) => _queued(() => _profileSwitch(body));

  Future<void> _profileSwitch(Future<bool> Function() body) async {
    final coreBefore = ref.read(activeCoreProvider);
    _profileSwitching = true;
    var switched = true; // also on an error: the profile may be switched with its server not restored
    try {
      switched = await body();
    } finally {
      _profileSwitching = false;
      final core = ref.read(activeCoreProvider);
      final live = switched && (state.isConnected || state.isConnecting);
      if (live && core?.kind != null) {
        await reconnectIfStale();
      } else if (live || core != coreBefore) {
        await _onCoreChanged();
      }
    }
  }

  /// Rebuilds a live tunnel when what it runs differs from what would run now: another
  /// effective config or changed connection settings (a profile switch changes both).
  Future<void> reconnectIfStale() async {
    if (state.isConnecting) return reconnectWithNewConfig();
    if (!state.isConnected) return;
    final config = ref.read(effectiveConfigProvider);
    // Not pendingReconnectProvider: it watches this notifier.
    final stale = _settingsStale(state, ref.read(settingsProvider).value, ref.read(activeCoreProvider));
    if (config == null || (runsConfig(config) && !stale)) return;
    await reconnectWithNewConfig();
  }

  VpnConfig? _resolveEffectiveConfig(ConfigState? cs) => cs == null ? null : ref.read(effectiveConfigProvider);

  Future<void> pingAllConfigs() async {
    if (_isPinging) return;
    final configState = ref.read(configProvider).maybeWhen(data: (d) => d, orElse: () => null);
    if (configState == null) return;
    _isPinging = true;
    try {
      await _pingEndpoints(configState.configs);
    } finally {
      _isPinging = false;
    }
  }

  Future<void> pingStaleConfigs() async {
    if (_isPinging) return;
    final configState = ref.read(configProvider).maybeWhen(data: (d) => d, orElse: () => null);
    if (configState == null) return;
    final now = DateTime.now();
    final stale = configState.configs.where((c) {
      if (c.lastPingedAt == null) return true;
      return now.difference(c.lastPingedAt!) > const Duration(hours: 1);
    }).toList();
    if (stale.isEmpty) return;
    _isPinging = true;
    try {
      await _pingEndpoints(stale);
    } finally {
      _isPinging = false;
    }
  }

  Future<void> _pingEndpoints(List<VpnConfig> configs) async {
    final now = DateTime.now();
    // Prefer non-raw configs per endpoint so TCP probe works for shared servers
    final endpoints = <String, VpnConfig>{};
    for (final c in configs) {
      if (c.rawXrayConfig == null) {
        endpoints['${c.address}:${c.port}'] = c;
      }
    }
    for (final c in configs) {
      if (c.rawXrayConfig != null) {
        endpoints.putIfAbsent('${c.address}:${c.port}', () => c);
      }
    }

    final results = await Future.wait(
      endpoints.entries.map((e) async {
        final ms = await _engine.pingConfig(e.value);
        return MapEntry(e.key, ms);
      }),
    );
    final latencyMap = Map.fromEntries(results);

    // Single batch update — one storage write, one state update
    await ref.read(configProvider.notifier).batchUpdatePingResults(latencyMap, now);
  }

  /// Stops the per-second stats polling while the app is in the background —
  /// on return syncNativeState() restarts it.
  void pauseStatsPolling() {
    _statsPoller?.cancel();
    _statsPoller = null;
  }

  Future<void> setLogsEnabled(bool enabled) => _engine.setLogsEnabled(enabled);

  Future<String?> getLogFilePath() => _engine.getLogFilePath();

  /// Dumps a tun2socks diagnostics snapshot into the app log.
  Future<void> dumpTunnelDiag() async {
    final diag = await _engine.getTunnelDiag();
    ref
        .read(logServiceProvider.notifier)
        .addInfo(diag.isEmpty ? 'tunnel diag: not running' : 'tunnel diag: $diag', source: 'diag');
  }

  Future<void> clearNativeLogs() => _engine.clearLogs();

  VpnState get connectionState => state.connectionState;
}

final vpnProvider = NotifierProvider<VpnNotifier, VpnState2>(VpnNotifier.new);

// Convenience selector for connection state
final vpnConnectionStateProvider = Provider<VpnState>((ref) {
  return ref.watch(vpnProvider).connectionState;
});

// Convenience selector for stats
final vpnStatsProvider = Provider<VpnStats>((ref) {
  return ref.watch(vpnProvider).stats;
});

/// true — connection settings changed after connecting,
/// a reconnect is needed to apply them.
final pendingReconnectProvider = Provider<bool>(
  (ref) => _settingsStale(
    ref.watch(vpnProvider),
    ref.watch(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null),
    ref.watch(activeCoreProvider),
  ),
);

bool _settingsStale(VpnState2 vpn, AppSettings? s, ({CoreKind? kind})? core) {
  if (!vpn.isConnected || vpn.appliedFingerprint == null || s == null) return false;
  return connectionFingerprint(s, core: core?.kind) != vpn.appliedFingerprint;
}
