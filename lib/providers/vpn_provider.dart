import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/interfaces/vpn_engine.dart';
import '../core/constants/app_constants.dart';
import '../core/models/vpn_stats.dart';
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

  const VpnState2({
    this.connectionState = VpnState.disconnected,
    this.stats = const VpnStats(),
    this.error,
    this.activeSocksPort = 0,
    this.activeSocksUser = '',
    this.activeSocksPassword = '',
  });

  bool get isConnected => connectionState == VpnState.connected;
  bool get isConnecting => connectionState == VpnState.connecting;
  bool get isDisconnecting => connectionState == VpnState.disconnecting;
  bool get isBusy => isConnecting || isDisconnecting;

  VpnState2 copyWith({
    VpnState? connectionState,
    VpnStats? stats,
    String? error,
    int? activeSocksPort,
    String? activeSocksUser,
    String? activeSocksPassword,
  }) {
    return VpnState2(
      connectionState: connectionState ?? this.connectionState,
      stats: stats ?? this.stats,
      error: error,
      activeSocksPort: activeSocksPort ?? this.activeSocksPort,
      activeSocksUser: activeSocksUser ?? this.activeSocksUser,
      activeSocksPassword: activeSocksPassword ?? this.activeSocksPassword,
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
  DateTime? _connectedAt;


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

    // Sync state on init (for case when VPN is already running from tile/notification)
    Future.microtask(() async {
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
        // Restore log history from persisted file
        final logEntries = await _engine.getLogs();
        if (logEntries.isNotEmpty) {
          ref.read(logServiceProvider.notifier).loadFromEntries(logEntries);
        }
        // ipInfoProvider is AsyncNotifier, needs refresh to rebuild
        // ignore: unused_result
        ref.refresh(ipInfoProvider);
        // Also fetch initial stats
        _startStatsPolling();
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

        // Also fetch stats history for chart
        final history = await _engine.getStatsHistory();
        if (history.isNotEmpty) {
          _handleStatsHistory({'history': history});
        }
      } catch (_) {}
    });
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
    }
  }

  VpnState _parseState(String? s) => switch (s) {
        'connecting' => VpnState.connecting,
        'reconnecting' => VpnState.connecting,
        'connected' => VpnState.connected,
        'disconnecting' => VpnState.disconnecting,
        'disconnected' => VpnState.disconnected,
        'error' => VpnState.error,
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
        nativeState == VpnState.error) {
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

    if (nativeState == VpnState.disconnected || nativeState == VpnState.error) {
      // Reset stats on disconnect/error
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
    final config = configState?.activeConfig;
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

    final socksCredentials = settings.randomCredentials
        ? XrayEngine.generateSocksCredentials()
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
      vpnMode: settings.vpnMode,
      proxyOnly: settings.proxyOnly,
      showNotification: settings.showNotification,
      killSwitch: settings.killSwitchEnabled,
      routing: settings.routing,
    );
    state = state.copyWith(
      activeSocksPort: actualSocksPort,
      activeSocksUser: socksCredentials.user,
      activeSocksPassword: socksCredentials.password,
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
  /// EventChannel replay on `onListen` handles most cases; this is a fallback.
  Future<void> syncNativeState() async {
    // We now handle timeouts inside _onNativeState, so it's safe to sync everything.

    try {
      const channel = MethodChannel(AppConstants.methodChannel);
      final nativeState = await channel.invokeMethod<String>('getState');
      if (nativeState == null) return;
      _onNativeState(_parseState(nativeState));
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

  Future<void> pingAllConfigs() async {
    final configState = ref.read(configProvider).maybeWhen(data: (d) => d, orElse: () => null);
    if (configState == null) return;
    // Ping in parallel, then update state sequentially to avoid race condition
    final pinged = await Future.wait(configState.configs.map((config) async {
      final ms = await _engine.pingConfig(config);
      return config.copyWith(latencyMs: ms);
    }));
    for (final updated in pinged) {
      await ref.read(configProvider.notifier).updateConfig(updated);
    }
  }

  Future<String?> getLogFilePath() => _engine.getLogFilePath();

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
