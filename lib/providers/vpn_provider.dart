import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/interfaces/vpn_engine.dart';

import '../core/models/vpn_stats.dart';
import '../core/services/log_service.dart';
import '../core/services/settings_service.dart';
import '../protocols/xray/xray_engine.dart';
import 'settings_provider.dart';
import 'config_provider.dart';

class VpnState2 {
  final VpnState connectionState;
  final VpnStats stats;
  final String? error;

  const VpnState2({
    this.connectionState = VpnState.disconnected,
    this.stats = const VpnStats(),
    this.error,
  });

  bool get isConnected => connectionState == VpnState.connected;
  bool get isConnecting => connectionState == VpnState.connecting;
  bool get isDisconnecting => connectionState == VpnState.disconnecting;
  bool get isBusy => isConnecting || isDisconnecting;

  VpnState2 copyWith({
    VpnState? connectionState,
    VpnStats? stats,
    String? error,
  }) {
    return VpnState2(
      connectionState: connectionState ?? this.connectionState,
      stats: stats ?? this.stats,
      error: error,
    );
  }
}

class VpnNotifier extends Notifier<VpnState2> {
  late final XrayEngine _engine;
  StreamSubscription<VpnState>? _stateSub;
  StreamSubscription<VpnStats>? _statsSub;
  StreamSubscription<dynamic>? _logSub;
  ({String user, String password})? _socksCredentials;

  @override
  VpnState2 build() {
    _engine = XrayEngine();

    _stateSub = _engine.stateStream.listen((s) {
      if (state.connectionState != s) {
        state = state.copyWith(connectionState: s);
      }
    });

    _statsSub = _engine.statsStream.listen((newStats) {
      // Only update if stats significantly changed to reduce UI pressure
      if (state.stats.uploadBytes != newStats.uploadBytes || 
          state.stats.downloadBytes != newStats.downloadBytes) {
        state = state.copyWith(stats: newStats);
      }
    });

    _logSub = _engine.logStream.listen((entry) {
      ref.read(logServiceProvider.notifier).add(entry);
    });

    ref.onDispose(() {
      _stateSub?.cancel();
      _statsSub?.cancel();
      _logSub?.cancel();
      _engine.dispose();
    });

    return const VpnState2();
  }

  Future<void> connect() async {
    // Request notification permission for foreground service (Android 13+)
    await Permission.notification.request();

    final configState = ref.read(configProvider).maybeWhen(data: (d) => d, orElse: () => null);
    final config = configState?.activeConfig;
    if (config == null) {
      ref.read(logServiceProvider.notifier).addError('No configuration selected');
      return;
    }

    final settings = ref.read(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null) ?? const AppSettings();

    // Generate credentials
    if (settings.randomCredentials) {
      _socksCredentials = XrayEngine.generateSocksCredentials();
    } else {
      _socksCredentials = (user: '', password: '');
    }

    // Use random port or configured port
    final actualSocksPort = settings.randomPort
        ? (10000 + DateTime.now().millisecondsSinceEpoch % 50000)
        : settings.socksPort;

    final options = VpnEngineOptions(
      socksPort: actualSocksPort,
      httpPort: 0,
      socksUser: _socksCredentials!.user,
      socksPassword: _socksCredentials!.password,
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
    );

    await _engine.connect(config, options);
  }

  Future<void> disconnect() async {
    await _engine.disconnect();
  }

  /// Syncs the Flutter VPN state with the native service state.
  /// Called when the app resumes from background.
  Future<void> syncNativeState() async {
    try {
      const channel = MethodChannel('com.teapodstream/vpn');
      final nativeState = await channel.invokeMethod<String>('getState');
      if (nativeState == null) return;

      final VpnState mappedState;
      switch (nativeState) {
        case 'connected':
          mappedState = VpnState.connected;
          break;
        case 'connecting':
          mappedState = VpnState.connecting;
          break;
        case 'error':
          mappedState = VpnState.error;
          break;
        default:
          mappedState = VpnState.disconnected;
      }

      if (state.connectionState != mappedState) {
        state = state.copyWith(connectionState: mappedState);
      }

      // If native says we're connected but stats aren't flowing,
      // restart the engine's internal polling
      if (mappedState == VpnState.connected) {
        await _engine.reconnectStreams();
      }
    } catch (_) {
      // If sync fails, leave the state as-is
    }
  }

  Future<void> toggle() async {
    if (state.isConnected || state.isConnecting) {
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
