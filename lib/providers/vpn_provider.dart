import '../core/constants/core_features.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/interfaces/vpn_engine.dart';
import '../core/models/vpn_config.dart';
import '../core/constants/app_constants.dart';
import '../core/models/vpn_stats.dart';
import '../core/models/connection_fingerprint.dart';
import '../core/models/heartbeat_settings.dart';
import '../core/models/vpn_log_entry.dart';
import '../core/services/log_service.dart';
import '../core/services/settings_service.dart';
import 'ip_info_provider.dart';
import '../protocols/xray/xray_engine.dart';
import 'settings_provider.dart';
import 'config_provider.dart';

class VpnState2 {
  final VpnState connectionState;
  final VpnStats stats;
  final String? error;
  final int activeSocksPort;
  final String activeSocksUser;
  final String activeSocksPassword;

  /// Fingerprint настроек, с которыми установлено текущее соединение.
  /// null — соединение не активно или отпечаток неизвестен.
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
  bool get isBusy => isConnecting || isDisconnecting;

  VpnState2 copyWith({
    VpnState? connectionState,
    VpnStats? stats,
    String? error,
    int? activeSocksPort,
    String? activeSocksUser,
    String? activeSocksPassword,
    String? appliedFingerprint,
  }) {
    return VpnState2(
      connectionState: connectionState ?? this.connectionState,
      stats: stats ?? this.stats,
      error: error,
      activeSocksPort: activeSocksPort ?? this.activeSocksPort,
      activeSocksUser: activeSocksUser ?? this.activeSocksUser,
      activeSocksPassword: activeSocksPassword ?? this.activeSocksPassword,
      appliedFingerprint: appliedFingerprint ?? this.appliedFingerprint,
    );
  }
}

class VpnNotifier extends Notifier<VpnState2> {
  late final XrayEngine _engine;
  static const _eventChannel =
      EventChannel('${AppConstants.methodChannel}/events');

  StreamSubscription<dynamic>? _eventSub;
  Timer? _connectTimeout;
  Timer? _disconnectTimeout;
  Timer? _statsPoller;
  bool _isPinging = false;
  bool _urltestRunning = false;
  DateTime? _connectedAt;

  /// true — вкладка home на экране; история для графика тянется только тогда.
  bool _chartVisible = true;


  @override
  VpnState2 build() {
    _engine = XrayEngine();

    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          _handleEvent(Map<String, dynamic>.from(event));
        }
      },
      onError: (dynamic error) {
        ref
            .read(logServiceProvider.notifier)
            .addError('Event channel error: $error');
      },
    );

    ref.onDispose(() {
      _eventSub?.cancel();
      _connectTimeout?.cancel();
      _disconnectTimeout?.cancel();
      _statsPoller?.cancel();
    });

    // Авто-обновление подписок: при старте (ниже в microtask) и при каждом
    // resume (app.dart → refreshStaleSubscriptionsIfDue) — часовой фоновый
    // таймер убран, staleness-проверка сама решает, пора ли обновлять.

    // Sync state on init (for case when VPN is already running from tile/notification)
    Future.microtask(() async {
      // Auto-refresh stale subscriptions on startup
      await refreshStaleSubscriptionsIfDue();

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

      final vpnState = await _engine.getVpnState();
      if (vpnState.state == VpnState.connected && vpnState.socksPort > 0) {
        if (vpnState.connectedAtMs > 0) {
          _connectedAt = DateTime.fromMillisecondsSinceEpoch(vpnState.connectedAtMs);
        }
        state = VpnState2(
          connectionState: VpnState.connected,
          activeSocksPort: vpnState.socksPort,
          activeSocksUser: vpnState.socksUser,
          activeSocksPassword: vpnState.socksPassword,
        );
        // ipInfoProvider is AsyncNotifier, needs refresh to rebuild
        // ignore: unused_result
        ref.refresh(ipInfoProvider);
        // Also fetch initial stats
        _startStatsPolling();
        // VPN уже работал до старта приложения — считаем применёнными текущие
        // настройки (точный снапшот на момент connect недоступен).
        final s = await ref.read(settingsProvider.future);
        state = state.copyWith(appliedFingerprint: connectionFingerprint(s));
      }
    });

    return const VpnState2();
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
        _handleStats(Map<String, dynamic>.from({
          'upload': stats.upload,
          'download': stats.download,
          'uploadSpeed': stats.uploadSpeed,
          'downloadSpeed': stats.downloadSpeed,
        }));

        // История (300 записей через MethodChannel) нужна только графику
        if (_chartVisible) {
          final history = await _engine.getStatsHistory();
          if (history.isNotEmpty) {
            _handleStatsHistory({'history': history});
          }
        }
      } catch (_) {}
    });
  }

  /// Вызывается из app.dart при смене вкладки: история для графика тянется
  /// только когда home видим; при возврате — немедленная догрузка.
  void setChartVisible(bool visible) {
    if (_chartVisible == visible) return;
    _chartVisible = visible;
    if (visible && state.isConnected) {
      _engine.getStatsHistory().then((history) {
        if (history.isNotEmpty) _handleStatsHistory({'history': history});
      }).ignore();
    }
  }

  /// Проверка staleness подписок — вызывается при старте и resume.
  Future<void> refreshStaleSubscriptionsIfDue() async {
    final settings = ref.read(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null);
    if (settings?.subAutoRefresh != true) return;
    await ref.read(configProvider.notifier)
        .refreshStaleSubscriptions(intervalHours: settings!.subAutoRefreshHours);
  }

  void _handleEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    switch (type) {
      case 'state':
        final rawValue = event['value'] as String?;
        final isReconnect = rawValue == 'reconnecting';
        final newState = _parseState(rawValue);
        if (newState == VpnState.connected) {
          final port = event['socksPort'] as int?;
          if (port != null && port > 0) {
            final user = event['socksUser'] as String? ?? '';
            final pass = event['socksPassword'] as String? ?? '';
            final connectedAtMs = (event['connectedAtMs'] as num?)?.toInt() ?? 0;
            if (connectedAtMs > 0) {
              _connectedAt ??= DateTime.fromMillisecondsSinceEpoch(connectedAtMs);
            }
            state = state.copyWith(
              activeSocksPort: port,
              activeSocksUser: user,
              activeSocksPassword: pass,
            );
          }
        }
        _onNativeState(newState, isReconnect: isReconnect);
      case 'log':
        final level = event['level'] as String? ?? 'info';
        final msg = event['message'] as String? ?? '';
        ref.read(logServiceProvider.notifier).add(VpnLogEntry(
          timestamp: DateTime.now(),
          level: LogLevel.values.firstWhere(
            (e) => e.name == level,
            orElse: () => LogLevel.info,
          ),
          message: msg,
          source: 'xray',
        ));
      case 'stats':
        break; // Ignore stats from EventChannel - we use poller instead
      case 'statsHistory':
        _handleStatsHistory(event);
      case 'tunnel_dead':
        _runUrltestSwitch((event['failures'] as num?)?.toInt() ?? 0);
    }
  }

  /// Нативный heartbeat исчерпал попытки в режиме urltest: подбираем живой конфиг
  /// среди кандидатов и переподключаемся на самый быстрый. Если живых нет —
  /// ничего не делаем, сервис сам реконнектится по своему cooldown.
  Future<void> _runUrltestSwitch(int failures) async {
    if (_urltestRunning) return;
    _urltestRunning = true;
    final log = ref.read(logServiceProvider.notifier);
    try {
      final settings =
          ref.read(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null) ??
              const AppSettings();
      if (settings.heartbeat.action != HeartbeatAction.urltest) return;

      final configState =
          ref.read(configProvider).maybeWhen(data: (d) => d, orElse: () => null);
      if (configState == null) return;
      final current = _resolveEffectiveConfig(configState);
      final candidates = _urltestCandidates(configState, settings.heartbeat.source, current);
      if (candidates.isEmpty) {
        log.addError('urltest: нет кандидатов для переключения (провалов: $failures)');
        return;
      }

      log.addInfo('urltest: туннель не отвечает, проверяю ${candidates.length} конфиг(ов)',
          source: 'urltest');
      final probed = await Future.wait(candidates.map((c) async {
        final ms = await _engine.pingConfig(c);
        return (config: c, latency: ms);
      }));
      final alive = probed.where((r) => r.latency != null).toList()
        ..sort((a, b) => a.latency!.compareTo(b.latency!));
      if (alive.isEmpty) {
        log.addError('urltest: живых конфигов не найдено, остаёмся на текущем');
        return;
      }

      final best = alive.first;
      log.addInfo('urltest: переключение на "${best.config.name}" (${best.latency} мс)',
          source: 'urltest');
      await ref.read(configProvider.notifier).setActiveConfig(best.config.id);
      await disconnect();
      await connect();
    } catch (e) {
      log.addError('urltest: ошибка переключения: $e');
    } finally {
      _urltestRunning = false;
    }
  }

  /// Кандидаты для urltest: активный конфиг исключается — он только что не прошёл пробу.
  List<VpnConfig> _urltestCandidates(
    ConfigState configState,
    UrltestSource source,
    VpnConfig? current,
  ) {
    final all = configState.configs.where((c) => c.id != current?.id);
    return switch (source) {
      UrltestSource.subscription =>
        all.where((c) => c.subscriptionId == current?.subscriptionId).toList(),
      UrltestSource.pinned =>
        all.where((c) => configState.pins.any((p) => p.matches(c))).toList(),
      UrltestSource.all => all.toList(),
    };
  }

  VpnState _parseState(String? s) => switch (s) {
        'connecting' => VpnState.connecting,
        'reconnecting' => VpnState.connecting,
        'connected' => VpnState.connected,
        'disconnecting' => VpnState.disconnecting,
        'disconnected' => VpnState.disconnected,
        'error' => VpnState.error,
        'blocked' => VpnState.blocked,
        _ => VpnState.disconnected,
      };

  void _onNativeState(VpnState nativeState, {bool isReconnect = false}) {
    if (nativeState == VpnState.connected) {
      _connectedAt ??= DateTime.now();
      _connectTimeout?.cancel();
      _connectTimeout = null;
      // Start polling as backup for when EventChannel doesn't deliver (app in background)
      _startStatsPolling();
    } else if (nativeState == VpnState.disconnected ||
        nativeState == VpnState.error ||
        nativeState == VpnState.blocked) {
      _connectedAt = null;
      _connectTimeout?.cancel();
      _connectTimeout = null;
      _disconnectTimeout?.cancel();
      _disconnectTimeout = null;
    } else if (nativeState == VpnState.connecting) {
      if (isReconnect) {
        // Native-triggered reconnect: cancel Flutter-side timeout so it doesn't
        // force error while the service is mid-reconnect (cycle can exceed 45s).
        _connectTimeout?.cancel();
        _connectTimeout = null;
      } else {
        _connectTimeout ??= Timer(const Duration(seconds: 45), () {
          if (state.connectionState == VpnState.connecting) {
            state = state.copyWith(
                connectionState: VpnState.error, error: 'Connection timeout');
            _connectTimeout = null;
            _engine.disconnect().ignore();
          }
        });
      }
    } else if (nativeState == VpnState.disconnecting) {
      _disconnectTimeout ??= Timer(const Duration(seconds: 10), () {
        if (state.connectionState == VpnState.disconnecting) {
          state = VpnState2(connectionState: VpnState.disconnected);
          _disconnectTimeout = null;
        }
      });
    }

    if (state.connectionState == nativeState) return;

    if (nativeState == VpnState.disconnected ||
        nativeState == VpnState.error ||
        nativeState == VpnState.blocked) {
      // Reset stats on disconnect/error/blocked
      _statsPoller?.cancel();
      state = VpnState2(
        connectionState: nativeState,
        // Reset stats including speedHistory
        stats: const VpnStats(),
        error: nativeState == VpnState.error
            ? (state.error ?? 'Connection error')
            : null,
      );
    } else {
      state = state.copyWith(connectionState: nativeState);
    }
  }

  void _handleStats(Map<String, dynamic> event) {
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
        connectedDuration: _connectedAt != null
            ? DateTime.now().difference(_connectedAt!)
            : Duration.zero,
      ),
    );
  }

  void _handleStatsHistory(Map<String, dynamic> event) {
    final historyRaw = event['history'];
    if (historyRaw is! List) return;

    final history = historyRaw
        .whereType<Map<Object?, Object?>>()
        .map((m) => SpeedPoint.fromMap(Map<String, dynamic>.from(m)))
        .toList();

    if (history.isEmpty) return;

    // Native history is the source of truth
    state = state.copyWith(
      stats: state.stats.copyWith(speedHistory: history),
    );
  }

  Future<void> connect() async {
    if (state.isBusy || state.isConnected) return;

    // Update state synchronously — button turns yellow in the same frame as tap
    state = state.copyWith(connectionState: VpnState.connecting, error: null);

    // Safety timeout — if native never confirms, force error after 45s
    _connectTimeout?.cancel();
    _connectTimeout = Timer(const Duration(seconds: 45), () {
      if (state.connectionState == VpnState.connecting) {
        state = state.copyWith(
            connectionState: VpnState.error, error: 'Connection timeout');
        _connectTimeout = null;
        _engine.disconnect().ignore();
      }
    });

    // Notification permission for foreground service (Android 13+) — best-effort
    await Permission.notification.request();

    final configState =
        ref.read(configProvider).maybeWhen(data: (d) => d, orElse: () => null);
    final config = _resolveEffectiveConfig(configState);
    if (config == null) {
      ref.read(logServiceProvider.notifier).addError('No configuration selected');
      state = state.copyWith(connectionState: VpnState.error, error: 'No configuration selected');
      _connectTimeout?.cancel();
      _connectTimeout = null;
      return;
    }

    final validationError = config.validate();
    if (validationError != null) {
      ref.read(logServiceProvider.notifier).addError('Invalid config: $validationError');
      state = state.copyWith(connectionState: VpnState.error, error: validationError);
      _connectTimeout?.cancel();
      _connectTimeout = null;
      return;
    }

    final settings =
        ref.read(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null) ??
            const AppSettings();

    // Rust's loopback diagnostic proxy currently supports no-auth only.
    final socksCredentials = CoreFeatures.current.isRust
        ? (user: '', password: '')
        : settings.randomCredentials ? XrayEngine.generateSocksCredentials()
        : (user: settings.socksUser, password: settings.socksPassword);

    final actualSocksPort = settings.randomPort
        ? (10000 + Random().nextInt(50000))
        : settings.socksPort;

    final options = VpnEngineOptions(
      socksPort: actualSocksPort,
      httpPort: 0,
      socksUser: socksCredentials.user,
      socksPassword: socksCredentials.password,
      excludedPackages: settings.splitTunnelingEnabled
          ? (settings.vpnMode == VpnMode.allExcept
              ? settings.excludedPackages
              : <String>{})
          : {},
      includedPackages: settings.splitTunnelingEnabled
          ? (settings.vpnMode == VpnMode.onlySelected
              ? settings.includedPackages
              : <String>{})
          : {},
      logLevel: settings.logLevel,
      enableUdp: settings.enableUdp,
      allowIcmp: settings.allowIcmp,
      dnsMode: settings.dnsMode,
      dnsServer: settings.dnsServer,
      vpnMode: settings.splitTunnelingEnabled ? settings.vpnMode : VpnMode.allExcept,
      proxyOnly: settings.proxyOnly,
      showNotification: settings.showNotification,
      killSwitch: settings.killSwitchEnabled,
      routing: settings.routing,
      sniffingEnabled: settings.sniffingEnabled,
      mtu: settings.mtu,
      dnsQueryStrategy: settings.dnsQueryStrategy,
      // XTLS Vision rejects UDP/443 by design: QUIC can never pass, but browsers
      // keep retrying it (each retry costs a full outbound handshake) and stall
      // for ~30s before falling back to TCP. Force the ICMP fast-fail.
      blockQuic: settings.blockQuic || _usesVisionFlow(config),
      ipv6Enabled: settings.ipv6Enabled,
      obsProbeIntervalSec: settings.obsProbeIntervalSec,
      tlsFingerprint: settings.tlsFingerprint,
      fragment: settings.fragment,
      noise: settings.noise,
      mux: settings.mux,
      heartbeat: settings.heartbeat,
    );
    state = state.copyWith(
      activeSocksPort: actualSocksPort,
      activeSocksUser: socksCredentials.user,
      activeSocksPassword: socksCredentials.password,
      appliedFingerprint: connectionFingerprint(settings),
    );

    try {
      await _engine.connect(config, options);
      // Polling is now started in _onNativeState when connected
    } on PlatformException catch (e) {
      ref
          .read(logServiceProvider.notifier)
          .addError('Connection failed: ${e.message}');
      state = state.copyWith(
          connectionState: VpnState.error, error: e.message);
      _connectTimeout?.cancel();
      _connectTimeout = null;
    }
  }

  Future<void> disconnect() async {
    if (state.connectionState == VpnState.disconnected ||
        state.connectionState == VpnState.disconnecting) { return; }

    // Update state synchronously
    state = state.copyWith(connectionState: VpnState.disconnecting);

    // Safety timeout — if native never confirms, force disconnected after 10s
    _disconnectTimeout?.cancel();
    _disconnectTimeout = Timer(const Duration(seconds: 10), () {
      if (state.connectionState == VpnState.disconnecting) {
        state = VpnState2(connectionState: VpnState.disconnected);
        _disconnectTimeout = null;
      }
    });

    try {
      await _engine.disconnect();
    } on PlatformException catch (e) {
      ref
          .read(logServiceProvider.notifier)
          .addError('Disconnect error: ${e.message}');
      // Force disconnected so the UI doesn't get stuck
      state = VpnState2(connectionState: VpnState.disconnected);
      _disconnectTimeout?.cancel();
      _disconnectTimeout = null;
    }
  }

  /// Syncs Flutter state from native when the app resumes from background.
  /// Критично: перезапускает _statsPoller после pauseStatsPolling().
  /// Историческая ошибка: getState возвращает Map, а здесь читали String —
  /// TypeError глотался catch'ем и весь метод был тихим no-op.
  Future<void> syncNativeState() async {
    try {
      final native = await _engine.getVpnState();
      if (native.state == VpnState.connected && native.socksPort > 0) {
        if (native.connectedAtMs > 0) {
          _connectedAt ??=
              DateTime.fromMillisecondsSinceEpoch(native.connectedAtMs);
        }
        state = state.copyWith(
          activeSocksPort: native.socksPort,
          activeSocksUser: native.socksUser,
          activeSocksPassword: native.socksPassword,
        );
      }
      // Не знаем, юзерский это connecting или нативный реконнект — не ставим
      // 45-секундный таймаут, который мог бы форсировать error поверх живого
      // цикла реконнекта.
      _onNativeState(native.state,
          isReconnect: native.state == VpnState.connecting);
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

  Future<void> reconnectWithNewConfig() async {
    if (state.isConnected || state.isConnecting) {
      await disconnect();
      // _disconnectTimeout is 10s; wait up to 12s so the forced-disconnect fires first.
      for (int i = 0; i < 120; i++) {
        if (!state.isBusy && !state.isConnected) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    await connect();
  }

  VpnConfig? _resolveEffectiveConfig(ConfigState? cs) =>
      cs == null ? null : ref.read(effectiveConfigProvider);

  /// True when the config's outbound(s) use xtls-rprx-vision — such outbounds
  /// reject UDP/443, so QUIC must be fast-failed on the TUN side.
  static bool _usesVisionFlow(VpnConfig config) {
    if (config.flow?.contains('vision') ?? false) return true;
    final raw = config.rawXrayConfig;
    if (raw == null) return false;
    try {
      final cfg = jsonDecode(raw) as Map<String, dynamic>;
      final outbounds = cfg['outbounds'] as List<dynamic>? ?? [];
      for (final o in outbounds.whereType<Map<String, dynamic>>()) {
        if (o['protocol'] != 'vless') continue;
        final vnext = (o['settings'] as Map<String, dynamic>?)?['vnext'] as List<dynamic>? ?? [];
        for (final v in vnext.whereType<Map<String, dynamic>>()) {
          final users = v['users'] as List<dynamic>? ?? [];
          for (final u in users.whereType<Map<String, dynamic>>()) {
            if ((u['flow'] as String?)?.contains('vision') ?? false) return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

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

    final results = await Future.wait(endpoints.entries.map((e) async {
      final ms = await _engine.pingConfig(e.value);
      return MapEntry(e.key, ms);
    }));
    final latencyMap = Map.fromEntries(results);

    // Single batch update — one storage write, one state update
    await ref.read(configProvider.notifier).batchUpdatePingResults(latencyMap, now);
  }

  /// Останавливает посекундный опрос статистики, когда приложение в фоне —
  /// при возврате syncNativeState() → _onNativeState(connected) перезапустит его.
  void pauseStatsPolling() {
    _statsPoller?.cancel();
    _statsPoller = null;
  }

  Future<void> setLogsEnabled(bool enabled) => _engine.setLogsEnabled(enabled);

  Future<String?> getLogFilePath() => _engine.getLogFilePath();

  /// Dumps a tun2socks diagnostics snapshot into the app log.
  Future<void> dumpTunnelDiag() async {
    final diag = await _engine.getTunnelDiag();
    ref.read(logServiceProvider.notifier).addInfo(
        diag.isEmpty ? 'tunnel diag: not running' : 'tunnel diag: $diag',
        source: 'diag');
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

/// true — настройки соединения изменены после подключения,
/// для применения нужен reconnect.
final pendingReconnectProvider = Provider<bool>((ref) {
  final vpn = ref.watch(vpnProvider);
  if (!vpn.isConnected || vpn.appliedFingerprint == null) return false;
  final s = ref.watch(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null);
  if (s == null) return false;
  return connectionFingerprint(s) != vpn.appliedFingerprint;
});
