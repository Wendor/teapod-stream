import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/interfaces/vpn_engine.dart';
import '../core/models/vpn_config.dart';
import '../core/models/connection_fingerprint.dart';
import '../core/models/core_kind.dart';
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
import '../core/models/app_message.dart';

class VpnState2 {
  final VpnState connectionState;
  final AppMessage? error;

  /// When the running session connected (native's `connectedAtMs`; reconnects keep it); null — not connected.
  final DateTime? connectedAt;
  final int activeSocksPort;
  final String activeSocksUser;
  final String activeSocksPassword;

  /// Fingerprint of the settings the current connection was established with.
  /// null — no active connection or the fingerprint is unknown.
  final String? appliedFingerprint;

  const VpnState2({
    this.connectionState = VpnState.disconnected,
    this.error,
    this.connectedAt,
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

  /// The fingerprint; the connection state and its reason come only from [VpnSession.view].
  VpnState2 copyWith({String? appliedFingerprint}) {
    return VpnState2(
      connectionState: connectionState,
      error: error,
      connectedAt: connectedAt,
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
  DateTime? _connectedAt;

  /// The startup sync with native is done (also when it failed).
  Future<void> get synced => _synced.future;
  final _synced = Completer<void>();

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
    listenSelf((prev, next) {
      ref.read(tunnelSocksProvider.notifier).set(next.tunnelSocks);
      // A session that ended may have run older settings than the current ones: the tile, boot and automation start
      // from the saved parameters, so they are saved again from what would run now.
      if (_idle(next.connectionState) && prev != null && !_idle(prev.connectionState)) _refreshQuickConnect();
    });
    // The active profile's core changed (priority, disabling, pinning).
    ref.listen(activeCoreProvider, (prev, next) {
      if (prev != null && next != null && prev != next && !_profileSwitching) _onCoreChanged();
    });
    // Connection settings changed while off: the saved quick-connect parameters follow them (a running session keeps
    // its own until it ends, above).
    ref.listen(settingsProvider, (prev, next) {
      final (a, b) = (prev?.value, next.value);
      if (a == null || b == null || _profileSwitching) return;
      // The core part is the core listener's.
      if (connectionFingerprint(a) != connectionFingerprint(b)) _refreshQuickConnect();
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
    });

    // Sync state on init (for case when VPN is already running from tile/notification)
    Future.microtask(() async {
      try {
        await syncNativeState();
      } finally {
        _synced.complete();
      }
    });

    return const VpnState2();
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
        // Native is off now and accepts the save: an earlier one may have been refused while it was stopping (a
        // timed-out connect shows `error` before native stops).
        if (_idle(session.state)) _refreshQuickConnect();
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
    }
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
    }
    state = VpnState2(
      connectionState: v.state,
      error: v.error,
      connectedAt: connected ? _connectedAt : null,
      activeSocksPort: connected ? n.socksPort : 0,
      activeSocksUser: connected ? n.socksUser : '',
      activeSocksPassword: connected ? n.socksPassword : '',
      appliedFingerprint: off ? null : state.appliedFingerprint,
    );
  }

  /// Applies a native snapshot ([poll] — from `getState`); false — not about the pending connect
  /// ([VpnSession.foreign]).
  bool _applyNative(NativeSession s, {bool poll = false}) {
    final foreign = _session.foreign(s, poll: poll);
    final next = _session.onNative(s, poll: poll);
    if (foreign) {
      // A reconnect report may have dropped the deadline: the pending connect still ends.
      if (poll) _armConnectDeadline();
    } else if (next.pending is PendingConnect) {
      // A native restart of the pending session can outlast the deadline (the service ends it itself); its start
      // (also after a switch's stop of the old session) has one again.
      if (s.reconnecting) {
        _deadline?.cancel();
        _deadline = null;
      } else if (s.state == VpnState.connecting) {
        _armConnectDeadline();
      }
    }
    _setSession(next);
    return !foreign;
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
        VpnSession(
          native: _session.native,
          failure: SessionFailure(const AppMessage(MessageCode.vpnConnectTimeout), p.attempt, stopping: true),
        ),
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
    void fail(AppMessage reason) {
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
      return fail(const AppMessage(MessageCode.vpnNoConfigSelected));
    }

    final validationError = config.validate();
    if (validationError != null) return fail(AppMessage.text(validationError));

    final settings = ref.read(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null) ?? const AppSettings();

    await ref.read(availableCoresProvider.future);
    // The resolver weighs a core's limits on the geosite rules.
    await _loadGeosite();
    if (superseded()) return;
    final resolver = ref.read(coreResolverProvider);
    final geosite = resolver.geosite;
    final resolution = resolver.resolve(config);
    final backend = resolution.backend;
    if (backend == null) return fail(AppMessage.text(resolution.reason!));
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
    if (check.blocking != null) return fail(AppMessage.text(check.blocking!));
    final missing = missingGeositeCodes(settings.routing, geosite);
    for (final w in [
      if (missing.isNotEmpty) '${AppMessage(MessageCode.geositeMissing, missing.join(', '))}',
      ...check.warnings,
    ]) {
      ref.read(logServiceProvider.notifier).addWarning(w, source: 'core');
    }

    try {
      await _engine.connect(config, backend, options, attempt: attempt);
      if (superseded()) return;
      _connectedConfig = config;
      if (switching) _connectedAt = null;
      state = state.copyWith(appliedFingerprint: connectionFingerprint(settings, core: backend.kind));
    } on PlatformException catch (e) {
      fail(e.message != null ? AppMessage.text(e.message!) : const AppMessage(MessageCode.vpnConnectError));
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
  void _failConnect(AppMessage reason, int attempt) {
    ref.read(logServiceProvider.notifier).addError('$reason');
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

  static bool _idle(VpnState s) => s == VpnState.disconnected || s == VpnState.error;

  /// While off, re-saves (or clears) the quick-connect parameters from the current settings and config.
  /// Runs after the notification that asked for it: providers aren't read while they rebuild.
  void _refreshQuickConnect() {
    // Several asks in one turn (native's off report and the transition it causes) save once.
    if (_refreshQueued) return;
    _refreshQueued = true;
    unawaited(
      Future(() async {
        _refreshQueued = false;
        if (ref.mounted && _idle(state.connectionState) && !_profileSwitching) await _onCoreChanged();
      }),
    );
  }

  bool _refreshQueued = false;

  /// The active profile's core changed: disconnect if nothing runs the profile anymore,
  /// otherwise re-save/clear quick-reconnect.
  Future<void> _onCoreChanged() async {
    // The saved parameters are built as a connect builds them: geosite codes missing from geosite.dat left out.
    await _loadGeosite();
    if (!ref.mounted) return;
    final settings = ref.read(settingsProvider).value;
    if (settings == null) return;
    final config = _resolveEffectiveConfig(ref.read(configProvider).maybeWhen(data: (d) => d, orElse: () => null));
    final resolution = config == null ? null : ref.read(coreResolverProvider).resolve(config);
    final backend = resolution?.backend;
    final reason = resolution?.reason;
    final unsupported = config == null
        ? const AppMessage(MessageCode.vpnNoConfigSelected)
        : reason == null
        ? null
        : AppMessage.text(reason);
    try {
      switch (coreSwitchAction(state: state.connectionState, unsupported: unsupported)) {
        case CoreSwitchAction.none:
          break;
        case CoreSwitchAction.disconnect:
          ref.read(logServiceProvider.notifier).addError('Core: $unsupported');
          await _disconnect(reason: unsupported);
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

  Future<void> disconnect() => _disconnect();

  /// [reason] — why Flutter stops the session: shown through the stop ([SessionFailure.stopping]).
  Future<void> _disconnect({AppMessage? reason}) async {
    // A connect still in flight must not dispatch or write state after this — also when native already reported
    // `disconnected` while that connect waited.
    _attempt = _newAttempt();
    if (state.connectionState == VpnState.disconnected || state.isDisconnecting) return;

    _deadline?.cancel();
    final n = _session.native;
    _setSession(
      VpnSession(
        native: n,
        pending: const PendingDisconnect(),
        failure: reason == null ? null : SessionFailure(reason, n.attempt, stopping: true),
      ),
    );
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
    // A late failure of an earlier disconnect: a newer command owns the deadline.
    if (_session.pending is! PendingDisconnect) return;
    _deadline?.cancel();
    _deadline = null;
    _setSession(VpnSession(failure: _session.failure));
  }

  /// Takes native's state at startup and on resume. A session
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
  /// one on this config stays, an idle VPN saves it for quick connect.
  Future<void> _followSelection() async {
    if (state.isBusy) return reconnectWithNewConfig();
    // Off: the tile, boot and automation start the selected config.
    if (_idle(state.connectionState)) return _onCoreChanged();
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
  /// rebuilt if stale, a core change suppressed meanwhile is handled, an idle VPN saves the quick-connect parameters.
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
      // Settings rebuild lazily: read here, the switch's change reaches the settings listener while it is skipped, and
      // the idle save below is the only one.
      ref.read(settingsProvider);
      _profileSwitching = false;
      final core = ref.read(activeCoreProvider);
      final live = switched && (state.isConnected || state.isConnecting);
      if (live && core?.kind != null) {
        await reconnectIfStale();
      } else if (live || core != coreBefore || _idle(state.connectionState)) {
        // Off: the profile's server and connection settings reach the saved quick-connect parameters (the settings
        // listener skips the switch).
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

  VpnState get connectionState => state.connectionState;
}

final vpnProvider = NotifierProvider<VpnNotifier, VpnState2>(VpnNotifier.new);

// Convenience selector for connection state
final vpnConnectionStateProvider = Provider<VpnState>((ref) {
  return ref.watch(vpnProvider).connectionState;
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
