import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/interfaces/vpn_engine.dart';
import '../core/constants/app_constants.dart';
import '../core/models/vpn_stats.dart';
import '../core/models/vpn_log_entry.dart';
import '../core/services/log_service.dart';
import '../core/services/settings_service.dart';
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
  DateTime? _connectedAt;

  Timer? _heartbeatTimer;
  int _heartbeatFailures = 0;
  int _heartbeatSocksPort = 0;
  String _heartbeatUser = '';
  String _heartbeatPassword = '';
  bool _heartbeatProxyOnly = false;

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
      _heartbeatTimer?.cancel();
    });

    return const VpnState2();
  }

  void _handleEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    switch (type) {
      case 'state':
        final newState = _parseState(event['value'] as String?);
        _onNativeState(newState);
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
        _handleStats(event);
    }
  }

  VpnState _parseState(String? s) => switch (s) {
        'connecting' => VpnState.connecting,
        'connected' => VpnState.connected,
        'disconnecting' => VpnState.disconnecting,
        'disconnected' => VpnState.disconnected,
        'error' => VpnState.error,
        _ => VpnState.disconnected,
      };

  void _onNativeState(VpnState nativeState) {
    if (nativeState == VpnState.connected) {
      _connectedAt ??= DateTime.now();
      _connectTimeout?.cancel();
      _connectTimeout = null;
      if (!_heartbeatProxyOnly) {
        _startHeartbeat();
      }
    } else if (nativeState == VpnState.disconnected ||
        nativeState == VpnState.error) {
      _connectedAt = null;
      _connectTimeout?.cancel();
      _connectTimeout = null;
      _disconnectTimeout?.cancel();
      _disconnectTimeout = null;
      _stopHeartbeat();
    } else if (nativeState == VpnState.connecting) {
      if (_connectTimeout == null) {
        _connectTimeout = Timer(const Duration(seconds: 30), () {
          if (state.connectionState == VpnState.connecting) {
            state = state.copyWith(
                connectionState: VpnState.error, error: 'Connection timeout');
            _connectTimeout = null;
            _engine.disconnect().ignore();
          }
        });
      }
    } else if (nativeState == VpnState.disconnecting) {
      if (_disconnectTimeout == null) {
        _disconnectTimeout = Timer(const Duration(seconds: 10), () {
          if (state.connectionState == VpnState.disconnecting) {
            state = VpnState2(connectionState: VpnState.disconnected);
            _disconnectTimeout = null;
          }
        });
      }
    }

    if (state.connectionState == nativeState) return;

    if (nativeState == VpnState.disconnected || nativeState == VpnState.error) {
      // Reset stats on disconnect/error
      state = VpnState2(
        connectionState: nativeState,
        error: nativeState == VpnState.error
            ? (state.error ?? 'Connection error')
            : null,
      );
    } else {
      state = state.copyWith(connectionState: nativeState);
    }
  }

  void _handleStats(Map<String, dynamic> event) {
    final upload = event['upload'] as int? ?? 0;
    final download = event['download'] as int? ?? 0;
    final uploadSpeed = event['uploadSpeed'] as int? ?? 0;
    final downloadSpeed = event['downloadSpeed'] as int? ?? 0;

    if (state.stats.uploadBytes == upload &&
        state.stats.downloadBytes == download) return;

    final duration = _connectedAt != null
        ? DateTime.now().difference(_connectedAt!)
        : Duration.zero;

    state = state.copyWith(
      stats: VpnStats(
        uploadBytes: upload,
        downloadBytes: download,
        uploadSpeedBps: uploadSpeed,
        downloadSpeedBps: downloadSpeed,
        connectedDuration: duration,
      ),
    );
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatFailures = 0;
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _probeProxy();
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatFailures = 0;
  }

  Future<void> _probeProxy() async {
    if (!state.isConnected || _heartbeatSocksPort == 0) return;
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _heartbeatSocksPort,
        timeout: const Duration(seconds: 5),
      );
      socket.setOption(SocketOption.tcpNoDelay, true);

      final completer = Completer<bool>();
      var phase = 0;

      socket.listen(
        (data) {
          if (completer.isCompleted) return;
          if (phase == 0) {
            if (data.length >= 2 && data[0] == 0x05) {
              if (data[1] == 0x00) {
                // No auth required
                phase = 2; // skip auth phase
                socket!.add([0x05, 0x01, 0x00, 0x01, 1, 1, 1, 1, 0, 53]);
              } else if (data[1] == 0x02) {
                // Username/Password auth required
                phase = 1;
                final userBytes = _heartbeatUser.codeUnits;
                final passBytes = _heartbeatPassword.codeUnits;
                socket!.add([
                  0x01, // Auth version
                  userBytes.length,
                  ...userBytes,
                  passBytes.length,
                  ...passBytes,
                ]);
              } else {
                completer.complete(false); // Unsupported auth
              }
            } else {
              completer.complete(false);
            }
          } else if (phase == 1) {
             // Auth response
             if (data.length >= 2 && data[0] == 0x01 && data[1] == 0x00) {
                 phase = 2;
                 socket!.add([0x05, 0x01, 0x00, 0x01, 1, 1, 1, 1, 0, 53]);
             } else {
                 completer.complete(false); // Auth failed
             }
          } else if (phase == 2) {
            completer.complete(
                data.length >= 2 && data[0] == 0x05 && data[1] == 0x00);
          }
        },
        onError: (e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(false);
        },
        cancelOnError: true,
      );

      // Send SOCKS5 greeting: version=5, 2 auth methods (no-auth, user/pass)
      socket.add([0x05, 0x02, 0x00, 0x02]);

      final ok = await completer.future.timeout(const Duration(seconds: 8));
      if (ok) {
        _heartbeatFailures = 0;
        ref.read(logServiceProvider.notifier).add(VpnLogEntry(
          timestamp: DateTime.now(),
          level: LogLevel.debug,
          message: 'Heartbeat check passed (SOCKS5 connect 1.1.1.1:53 OK)',
          source: 'vpn',
        ));
        return;
      }
      throw Exception('SOCKS5 probe failed');
    } catch (_) {
      _heartbeatFailures++;
      if (_heartbeatFailures >= 3 && state.isConnected) {
        final failures = _heartbeatFailures;
        _stopHeartbeat();
        ref.read(logServiceProvider.notifier).add(VpnLogEntry(
          timestamp: DateTime.now(),
          level: LogLevel.warning,
          message: 'Heartbeat failed $failures times, reconnecting',
          source: 'vpn',
        ));
        await _reconnect();
      }
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  Future<void> _reconnect() async {
    await disconnect();
    
    // Wait until fully disconnected (up to 15 seconds)
    for (int i = 0; i < 150; i++) {
        if (!state.isBusy && !state.isConnected) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    
    await connect();
  }

  Future<void> connect() async {
    if (state.isBusy || state.isConnected) return;

    // Update state synchronously — button turns yellow in the same frame as tap
    state = state.copyWith(connectionState: VpnState.connecting, error: null);

    // Safety timeout — if native never confirms, force error after 30s
    _connectTimeout?.cancel();
    _connectTimeout = Timer(const Duration(seconds: 30), () {
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
      ref
          .read(logServiceProvider.notifier)
          .addError('No configuration selected');
      state = state.copyWith(
          connectionState: VpnState.error, error: 'No configuration selected');
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
        ? (10000 + DateTime.now().millisecondsSinceEpoch % 50000)
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
      dnsMode: settings.dnsMode,
      dnsServer: settings.dnsServer,
      vpnMode: settings.vpnMode,
      proxyOnly: settings.proxyOnly,
      showNotification: settings.showNotification,
      killSwitch: settings.killSwitchEnabled,
      routing: settings.routing,
    );
    _heartbeatSocksPort = actualSocksPort;
    _heartbeatUser = socksCredentials.user;
    _heartbeatPassword = socksCredentials.password;
    _heartbeatProxyOnly = settings.proxyOnly;
    state = state.copyWith(
      activeSocksPort: actualSocksPort,
      activeSocksUser: socksCredentials.user,
      activeSocksPassword: socksCredentials.password,
    );

    try {
      await _engine.connect(config, options);
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
        state.connectionState == VpnState.disconnecting) return;

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
