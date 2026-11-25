import 'dart:math';
import 'package:flutter/services.dart';
import '../../core/constants/app_constants.dart';
import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/vpn_config.dart';
import '../../core/models/vpn_log_entry.dart';
import '../../core/cores/core_backend.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// XrayEngine is a thin MethodChannel client — it sends commands to the native
/// Android VPN service and nothing else. All state, stats, and log events are
/// delivered via EventChannel and processed directly by VpnNotifier.
class XrayEngine {
  static const _channel = MethodChannel(AppConstants.methodChannel);

  /// The single subscription to native events. A second `receiveBroadcastStream()`
  /// on the same name would overwrite the first one's handler (`setMessageHandler`) — all
  /// listeners (VpnNotifier, deeplinks) attach to this broadcast stream.
  static final Stream<dynamic> events = const EventChannel(
    '${AppConstants.methodChannel}/events',
  ).receiveBroadcastStream();

  /// Starts [config] on [backend]'s core. [attempt] — the caller's connect attempt; state events of the session it
  /// starts carry it back (`attempt` field), 0 — untagged.
  Future<void> connect(VpnConfig config, CoreBackend backend, VpnEngineOptions options, {int attempt = 0}) async {
    final String xrayConfig;
    try {
      xrayConfig = backend.buildConfig(config, options);
    } on FormatException catch (e) {
      throw PlatformException(code: 'UNSUPPORTED_CONFIG', message: e.message);
    } on StateError catch (e) {
      throw PlatformException(code: 'UNSUPPORTED_CONFIG', message: e.message);
    }
    await _channel.invokeMethod('connect', {..._connectArgs(xrayConfig, config, backend, options), 'attempt': attempt});
  }

  /// Quick-reconnect config (tile, autostart) for the current core without connecting.
  Future<void> saveQuickConnect(VpnConfig config, CoreBackend backend, VpnEngineOptions options) async {
    await _channel.invokeMethod(
      'saveQuickConnect',
      _connectArgs(backend.buildConfig(config, options), config, backend, options),
    );
  }

  Future<void> clearQuickConnect() => _channel.invokeMethod('clearQuickConnect');

  Map<String, Object?> _connectArgs(
    String xrayConfig,
    VpnConfig config,
    CoreBackend backend,
    VpnEngineOptions options,
  ) => {
    'engine': backend.kind.nativeId,
    'configName': config.name,
    'xrayConfig': xrayConfig,
    'socksPort': options.socksPort,
    'socksUser': options.socksUser,
    'socksPassword': options.socksPassword,
    'excludedPackages': options.excludedPackages.toList(),
    'includedPackages': options.includedPackages.toList(),
    'vpnMode': options.vpnMode.name,
    'proxyOnly': options.proxyOnly,
    'showNotification': options.showNotification,
    'killSwitch': options.killSwitch,
    'allowIcmp': options.allowIcmp,
    'blockQuic': options.blockQuic,
    'ipv6Enabled': options.ipv6Enabled,
    'allowTethering': options.allowTethering,
    'mtu': options.mtu,
    'heartbeatProbe': backend.effectiveHeartbeatProbe(options.heartbeat.probe).name,
    'heartbeatAction': options.heartbeat.failAction.name,
    'heartbeatThreshold': options.heartbeat.failureThreshold,
    'heartbeatUrl': options.heartbeat.url,
    if (config.ssPrefix != null) 'ssPrefix': config.ssPrefix,
  };

  Future<void> disconnect() async {
    await _channel.invokeMethod('disconnect');
  }

  /// Latency measurement through a candidate: a temporary xray instance with its config
  /// (`Teapodcore.measureOutboundDelay`). null — the server didn't answer.
  Future<int?> measureOutbound(VpnConfig config, CoreBackend backend, VpnEngineOptions options, String url) async {
    try {
      final xrayConfig = backend.buildProbeConfig(config, options);
      return await _channel.invokeMethod<int>('measureOutbound', {
        'engine': backend.kind.nativeId,
        'config': xrayConfig,
        'url': url,
      });
    } catch (_) {
      return null;
    }
  }

  Future<int?> pingConfig(VpnConfig config) async {
    if (config.address.isEmpty || config.address == 'managed') return null;
    try {
      final result = await _channel.invokeMethod<int>('ping', {'address': config.address, 'port': config.port});
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Generate cryptographically random SOCKS credentials.
  static ({String user, String password}) generateSocksCredentials() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    String randomString(int len) => List.generate(len, (_) => chars[rng.nextInt(chars.length)]).join();

    return (user: 'u${randomString(8)}', password: randomString(AppConstants.socksAuthPasswordLength));
  }

  /// The native session (for sync on app start and resume); [NativeSession.disconnected] when the call fails.
  Future<NativeSession> getVpnState() async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>('getState');
      if (result != null) return NativeSession.parse(result);
    } catch (_) {}
    return NativeSession.disconnected;
  }

  /// JSON snapshot of tun2socks state (counters, per-connection activity).
  /// Empty string when the tunnel is not running.
  Future<String> getTunnelDiag() async {
    try {
      return await _channel.invokeMethod<String>('getTunnelDiag') ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Returns the absolute path to the native log file (filesDir/vpn_log.txt).
  Future<String?> getLogFilePath() async {
    try {
      return await _channel.invokeMethod<String>('getLogFilePath');
    } catch (_) {
      return null;
    }
  }

  /// Read persisted log file from native filesDir.
  Future<List<VpnLogEntry>> getLogs() async {
    try {
      final lines = await _channel.invokeMethod<List<Object?>>('getLogs');
      if (lines == null) return [];
      return lines
          .whereType<String>()
          .map((line) {
            final idx1 = line.indexOf('|');
            final idx2 = line.indexOf('|', idx1 + 1);
            if (idx1 < 0 || idx2 < 0) return null;
            final ts = int.tryParse(line.substring(0, idx1));
            if (ts == null) return null;
            final levelStr = line.substring(idx1 + 1, idx2);
            final message = line.substring(idx2 + 1);
            final level = LogLevel.values.firstWhere((e) => e.name == levelStr, orElse: () => LogLevel.info);
            return VpnLogEntry(
              timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
              level: level,
              message: message,
              source: 'xray',
            );
          })
          .whereType<VpnLogEntry>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Clear the persisted log file on native side.
  Future<void> clearLogs() async {
    try {
      await _channel.invokeMethod<void>('clearLogs');
    } catch (_) {}
  }

  /// Toggle native logging (persisted in native prefs; off = warning/error only).
  Future<void> setLogsEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setLogsEnabled', {'enabled': enabled});
    } catch (_) {}
  }

  /// Get current stats (for background polling).
  Future<({int upload, int download, int uploadSpeed, int downloadSpeed})> getStats() async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>('getStats');
      if (result != null) {
        return (
          upload: (result['upload'] as num?)?.toInt() ?? 0,
          download: (result['download'] as num?)?.toInt() ?? 0,
          uploadSpeed: (result['uploadSpeed'] as num?)?.toInt() ?? 0,
          downloadSpeed: (result['downloadSpeed'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (_) {}
    return (upload: 0, download: 0, uploadSpeed: 0, downloadSpeed: 0);
  }

  /// Speed history for the chart after point [since] of epoch [epoch]
  /// (`{epoch, seq, from, full, history}`, see XrayVpnService.getStatsHistory).
  Future<Map<Object?, Object?>?> getStatsHistory(int epoch, int since) async {
    try {
      return await _channel.invokeMethod<Map<Object?, Object?>>('getStatsHistory', {'epoch': epoch, 'since': since});
    } catch (_) {
      return null;
    }
  }
}

/// The native session as the `state` event and `getState` carry it (`SessionSnapshot.toMap` in Kotlin): one parser
/// for both. [attempt] — the Flutter connect attempt that started the session (0 — started natively); the SOCKS login
/// and [connectedAtMs] only while connected; [error] — why the session failed (error, blocked).
class NativeSession {
  const NativeSession({
    required this.state,
    this.reconnecting = false,
    this.attempt = 0,
    this.socksPort = 0,
    this.socksUser = '',
    this.socksPassword = '',
    this.connectedAtMs = 0,
    this.error,
  });

  static const disconnected = NativeSession(state: VpnState.disconnected);

  factory NativeSession.parse(Map<Object?, Object?> m) {
    final value = m['value'] as String?;
    return NativeSession(
      state: switch (value) {
        'connecting' || 'reconnecting' => VpnState.connecting,
        'connected' => VpnState.connected,
        'disconnecting' => VpnState.disconnecting,
        'error' => VpnState.error,
        'blocked' => VpnState.blocked,
        _ => VpnState.disconnected,
      },
      reconnecting: value == 'reconnecting',
      attempt: (m['attempt'] as num?)?.toInt() ?? 0,
      socksPort: (m['socksPort'] as num?)?.toInt() ?? 0,
      socksUser: m['socksUser'] as String? ?? '',
      socksPassword: m['socksPassword'] as String? ?? '',
      connectedAtMs: (m['connectedAtMs'] as num?)?.toInt() ?? 0,
      error: m['error'] as String?,
    );
  }

  final VpnState state;

  /// A native restart of the session (`reconnecting`): [state] is [VpnState.connecting].
  final bool reconnecting;
  final int attempt;
  final int socksPort;
  final String socksUser;
  final String socksPassword;
  final int connectedAtMs;
  final String? error;

  @override
  bool operator ==(Object other) =>
      other is NativeSession &&
      other.state == state &&
      other.reconnecting == reconnecting &&
      other.attempt == attempt &&
      other.socksPort == socksPort &&
      other.socksUser == socksUser &&
      other.socksPassword == socksPassword &&
      other.connectedAtMs == connectedAtMs &&
      other.error == error;

  @override
  int get hashCode =>
      Object.hash(state, reconnecting, attempt, socksPort, socksUser, socksPassword, connectedAtMs, error);
}

/// The engine [VpnNotifier] and the other providers talk to; tests override it.
final xrayEngineProvider = Provider<XrayEngine>((ref) => XrayEngine());
