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
import '../core/models/heartbeat_settings.dart';
import '../core/models/vpn_log_entry.dart';
import '../core/services/log_service.dart';
import '../core/services/settings_service.dart';
import '../core/services/tunnel_socks.dart';
import '../protocols/xray/xray_engine.dart';
import '../core/cores/core_resolver.dart';
import '../core/cores/engine_options.dart';
import '../core/cores/core_switch.dart';
import 'core_provider.dart';
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

  /// SOCKS туннеля для собственных загрузок приложения; null — VPN не подключён.
  TunnelSocks? get tunnelSocks => isConnected && activeSocksPort > 0
      ? TunnelSocks(activeSocksPort, activeSocksUser, activeSocksPassword)
      : null;

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

/// SOCKS туннеля для собственных загрузок (подписки, гео-базы); null — VPN не подключён.
final tunnelSocksProvider = Provider<TunnelSocks?>((ref) => ref.watch(vpnProvider).tunnelSocks);

class VpnNotifier extends Notifier<VpnState2> {
  late final XrayEngine _engine;

  StreamSubscription<dynamic>? _eventSub;
  Timer? _connectTimeout;
  Timer? _disconnectTimeout;
  Timer? _statsPoller;
  bool _isPinging = false;
  bool _urltestRunning = false;
  DateTime? _connectedAt;

  /// true — вкладка home на экране; история для графика тянется только тогда.
  bool _chartVisible = true;

  /// История графика: натив отдаёт только точки после `_historySeq` эпохи
  /// `_historyEpoch`; отставание (фон, скрытая вкладка дольше буфера, новая
  /// сессия) приходит одним ответом — график сразу встаёт в актуальное состояние.
  static const _maxHistory = 300;
  int _historyEpoch = -1;
  int _historySeq = 0;
  bool _historyFetching = false;
  /// Последний выставленный список: если в state другой, его сбросили (отключение,
  /// таймаут) — дописывать не к чему, нужен весь буфер.
  List<SpeedPoint> _history = const [];


  @override
  VpnState2 build() {
    _engine = XrayEngine();
    // Ядро активного профиля сменилось (приоритет, выключение, закрепление).
    ref.listen(activeCoreProvider, (prev, next) {
      if (prev != null && next != null && prev != next) _onCoreChanged();
    });

    _eventSub = XrayEngine.events.listen(
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
        // ipInfoProvider пересоберётся сам: он следит за vpnConnectionStateProvider.
        // ref.refresh отсюда — циклическая зависимость (в debug обрывал этот блок).
        _startStatsPolling();
        // VPN уже работал до старта приложения — считаем применёнными текущие
        // настройки (точный снапшот на момент connect недоступен).
        final s = await ref.read(settingsProvider.future);
        await ref.read(configProvider.future);
        await ref.read(availableCoresProvider.future);
        state = state.copyWith(
            appliedFingerprint: connectionFingerprint(s, core: ref.read(activeCoreProvider)?.kind));
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

        // История нужна только графику
        if (_chartVisible) await _pullHistory();
      } catch (_) {}
    });
    // Возврат из фона / подключение: история сразу, а не через тик.
    if (_chartVisible && state.isConnected) _pullHistory().ignore();
  }

  /// Вызывается из app.dart при смене вкладки: история для графика тянется
  /// только когда home видим; при возврате — немедленная догрузка.
  void setChartVisible(bool visible) {
    if (_chartVisible == visible) return;
    _chartVisible = visible;
    if (visible && state.isConnected) _pullHistory().ignore();
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
        _applyHistory(event);
      case 'tunnel_dead':
        _runConfigSwitch((event['failures'] as num?)?.toInt() ?? 0);
    }
  }

  /// Нативный heartbeat исчерпал попытки, а действие — смена конфига: меряем
  /// кандидатов и переподключаемся на самый быстрый живой. Если живых нет —
  /// ничего не делаем, сервис сам реконнектится по своему cooldown.
  Future<void> _runConfigSwitch(int failures) async {
    if (_urltestRunning) return;
    _urltestRunning = true;
    final log = ref.read(logServiceProvider.notifier);
    try {
      final settings =
          ref.read(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null) ??
              const AppSettings();
      if (settings.heartbeat.failAction != HeartbeatFailAction.switchConfig) return;

      final configState =
          ref.read(configProvider).maybeWhen(data: (d) => d, orElse: () => null);
      if (configState == null) return;
      final current = _resolveEffectiveConfig(configState);
      await ref.read(availableCoresProvider.future);
      final candidates = supportedCandidates(
          _switchCandidates(configState, settings.heartbeat.switchSource, current),
          ref.read(coreResolverProvider));
      if (candidates.isEmpty) {
        log.addError('urltest: нет кандидатов для переключения (провалов: $failures)');
        return;
      }

      log.addInfo('urltest: туннель не отвечает, проверяю ${candidates.length} конфиг(ов)',
          source: 'urltest');
      // Замер идёт через временный xray-инстанс с конфигом кандидата: TCP-пинг
      // сказал бы «жив» и про сервер, у которого порт открыт, а протокол молчит.
      // Инстанс временный, inbounds Go вырезает сам — важны только поля,
      // влияющие на outbound.
      final options = VpnEngineOptions(
        socksPort: AppConstants.defaultSocksPort,
        httpPort: 0,
        socksUser: '',
        socksPassword: '',
        tlsFingerprint: settings.tlsFingerprint,
        fragment: settings.fragment,
        noise: settings.noise,
        mux: settings.mux,
      );
      final probed = await Future.wait(candidates.map((c) async {
        final ms = await _engine.measureOutbound(c.config, c.backend, options, settings.heartbeat.url);
        return (config: c.config, latency: ms);
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
      // disconnect()+connect() здесь не работал: connect() выходил по isBusy
      // (состояние ещё disconnecting), и VPN оставался выключенным.
      await reconnectWithNewConfig();
    } catch (e) {
      log.addError('urltest: ошибка переключения: $e');
    } finally {
      _urltestRunning = false;
    }
  }

  /// Кандидаты для переключения: активный конфиг исключается — он только что не прошёл пробу.
  List<VpnConfig> _switchCandidates(
    ConfigState configState,
    SwitchSource source,
    VpnConfig? current,
  ) {
    final all = configState.configs.where((c) => c.id != current?.id);
    return switch (source) {
      SwitchSource.subscription =>
        all.where((c) => c.subscriptionId == current?.subscriptionId).toList(),
      SwitchSource.pinned =>
        all.where(configState.isPinned).toList(),
      SwitchSource.all => all.toList(),
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

  /// Ответ натива: `full` заменяет историю, иначе точки дописываются — только если
  /// продолжают текущую (`from == _historySeq`), чтобы опоздавший ответ не задвоил их.
  /// Любое несовпадение — следующий запрос за всем буфером.
  void _applyHistory(Map<Object?, Object?> r) {
    final full = r['full'] == true;
    final epoch = (r['epoch'] as num?)?.toInt() ?? -1;
    final from = (r['from'] as num?)?.toInt() ?? 0;
    if (!full &&
        (epoch != _historyEpoch ||
            from != _historySeq ||
            !identical(state.stats.speedHistory, _history))) {
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

  /// [switching] — смена сервера/настроек на живом туннеле: натив пересобирает
  /// сессию, не закрывая TUN. Отказ до вызова натива оставляет старое соединение.
  Future<void> connect({bool switching = false}) async {
    if (state.isBusy || (state.isConnected && !switching)) return;

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
      return _failConnect('No configuration selected', switching: switching);
    }

    final validationError = config.validate();
    if (validationError != null) return _failConnect(validationError, switching: switching);

    final settings =
        ref.read(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null) ??
            const AppSettings();

    await ref.read(availableCoresProvider.future);
    final resolution = ref.read(coreResolverProvider).resolve(config);
    final backend = resolution.backend;
    if (backend == null) return _failConnect(resolution.reason!, switching: switching);
    _engine.backend = backend;
    _logCoreChoice(resolution);

    final credentials = _socksCredentials(settings);
    final options = buildEngineOptions(settings, config, backend,
        socksPort: _socksPort(settings), credentials: credentials);
    final check = backend.checkOptions(config, options);
    if (check.blocking != null) return _failConnect(check.blocking!, switching: switching);
    for (final w in check.warnings) {
      ref.read(logServiceProvider.notifier).addWarning(w, source: 'core');
    }

    try {
      await _engine.connect(config, options);
      if (switching) _connectedAt = null;
      // Polling is started in _onNativeState when connected
      state = state.copyWith(
        activeSocksPort: options.socksPort,
        activeSocksUser: credentials.user,
        activeSocksPassword: credentials.password,
        appliedFingerprint: connectionFingerprint(settings, core: backend.kind),
      );
    } on PlatformException catch (e) {
      _failConnect(e.message ?? 'Connection failed', switching: switching);
    }
  }

  /// Подключение не начато. При [switching] натив продолжает прежнюю сессию.
  void _failConnect(String reason, {bool switching = false}) {
    ref.read(logServiceProvider.notifier).addError(reason);
    state = state.copyWith(
        connectionState: switching ? VpnState.connected : VpnState.error, error: reason);
    _connectTimeout?.cancel();
    _connectTimeout = null;
  }

  /// В TUN-режиме SOCKS внутренний: без пароля им пользовалось бы любое приложение
  /// (выход в туннель, IP сервера), поэтому пустые ручные креды заменяются
  /// случайными. В proxy-only открытый SOCKS — выбор пользователя.
  static ({String user, String password}) _socksCredentials(AppSettings s) =>
      s.randomCredentials ||
              (!s.proxyOnly && (s.socksUser.isEmpty || s.socksPassword.isEmpty))
          ? XrayEngine.generateSocksCredentials()
          : (user: s.socksUser, password: s.socksPassword);

  static int _socksPort(AppSettings s) =>
      s.randomPort ? 10000 + Random().nextInt(50000) : s.socksPort;

  /// В лог — каким ядром запущен профиль и почему пропущены ядра выше.
  void _logCoreChoice(CoreResolution r) {
    final skipped = [
      for (final v in r.verdicts.takeWhile((v) => v.reason != null))
        if (v.reason != CoreResolver.disabledReason) '${v.kind.displayName}: ${v.reason}',
    ];
    ref.read(logServiceProvider.notifier).addInfo(
        '${r.backend!.kind.displayName}${r.pinned ? ' (закреплено)' : ''}'
        '${skipped.isEmpty ? '' : ' — пропущены: ${skipped.join('; ')}'}',
        source: 'core');
  }

  /// Ядро активного профиля сменилось: отключить, если профиль больше ничем
  /// не запускается, иначе пересохранить/очистить quick-reconnect.
  Future<void> _onCoreChanged() async {
    final settings = ref.read(settingsProvider).value;
    if (settings == null) return;
    final config = _resolveEffectiveConfig(
        ref.read(configProvider).maybeWhen(data: (d) => d, orElse: () => null));
    final resolution = config == null ? null : ref.read(coreResolverProvider).resolve(config);
    final backend = resolution?.backend;
    final unsupported = config == null ? 'Конфигурация не выбрана' : resolution!.reason;
    try {
      switch (coreSwitchAction(state: state.connectionState, unsupported: unsupported)) {
        case CoreSwitchAction.none:
          break;
        case CoreSwitchAction.disconnect:
          await disconnect();
          ref.read(logServiceProvider.notifier).addError('Ядро: $unsupported');
          state = state.copyWith(error: unsupported);
        case CoreSwitchAction.saveQuickConnect:
          _engine.backend = backend!;
          await _engine.saveQuickConnect(
              config!,
              buildEngineOptions(settings, config, backend,
                  socksPort: _socksPort(settings), credentials: _socksCredentials(settings)));
        case CoreSwitchAction.clearQuickConnect:
          await _engine.clearQuickConnect();
      }
    } catch (e) {
      ref.read(logServiceProvider.notifier).addError('Смена ядра: $e');
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
    // Живой туннель переключается нативно: старый TUN держит трафик до нового.
    if (state.isConnected) return connect(switching: true);
    if (state.isConnecting) {
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
  return connectionFingerprint(s, core: ref.watch(activeCoreProvider)?.kind) != vpn.appliedFingerprint;
});
