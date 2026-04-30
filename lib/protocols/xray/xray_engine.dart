import 'dart:math';
import 'package:flutter/services.dart';
import '../../core/constants/app_constants.dart';
import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/vpn_config.dart';
import 'xray_config_builder.dart';

/// XrayEngine is a thin MethodChannel client — it sends commands to the native
/// Android VPN service and nothing else. All state, stats, and log events are
/// delivered via EventChannel and processed directly by VpnNotifier.
class XrayEngine implements VpnEngine {
  static const _channel = MethodChannel(AppConstants.methodChannel);

  @override
  String get protocolName => 'xray';

  @override
  Future<void> connect(VpnConfig config, VpnEngineOptions options) async {
    final xrayConfig = XrayConfigBuilder.buildJson(config, options);
    await _channel.invokeMethod('connect', {
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
      if (config.ssPrefix != null) 'ssPrefix': config.ssPrefix,
    });
  }

  @override
  Future<void> disconnect() async {
    await _channel.invokeMethod('disconnect');
  }

  @override
  Future<int?> pingConfig(VpnConfig config) async {
    try {
      final result = await _channel.invokeMethod<int>('ping', {
        'address': config.address,
        'port': config.port,
      });
      return result;
    } catch (_) {
      return null;
    }
  }

  @override
  bool supportsConfig(VpnConfig config) => true;

  Future<Map<String, String>> getBinaryVersions() async {
    try {
      final result = await _channel.invokeMethod<Map>('getBinaryVersions');
      if (result != null) {
        return Map<String, String>.from(result);
      }
    } catch (_) {}
    return {'xray': '—', 'tun2socks': '—'};
  }

  /// Generate cryptographically random SOCKS credentials.
  static ({String user, String password}) generateSocksCredentials() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    String randomString(int len) =>
        List.generate(len, (_) => chars[rng.nextInt(chars.length)]).join();

    return (
      user: 'u${randomString(8)}',
      password: randomString(AppConstants.socksAuthPasswordLength),
    );
  }

  /// Get current VPN state with SOCKS credentials (for sync on app start).
  Future<({VpnState state, int socksPort, String socksUser, String socksPassword})>
      getVpnState() async {
    try {
      final result =
          await _channel.invokeMethod<Map<Object?, Object?>>('getState');
      if (result != null) {
        final stateStr = result['state'] as String? ?? 'disconnected';
        return (
          state: _parseState(stateStr),
          socksPort: result['socksPort'] as int? ?? 0,
          socksUser: result['socksUser'] as String? ?? '',
          socksPassword: result['socksPassword'] as String? ?? '',
        );
      }
    } catch (_) {}
    return (state: VpnState.disconnected, socksPort: 0, socksUser: '', socksPassword: '');
  }

  /// Get current stats (for background polling).
  Future<({int upload, int download, int uploadSpeed, int downloadSpeed})>
      getStats() async {
    try {
      final result =
          await _channel.invokeMethod<Map<Object?, Object?>>('getStats');
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

  /// Get stats history for chart.
  Future<List<Map<String, int>>> getStatsHistory() async {
    try {
      final result = await _channel.invokeMethod<List<Object?>>('getStatsHistory');
      if (result != null) {
        return result
            .whereType<Map<Object?, Object?>>()
            .map((m) => {
                  'uploadSpeed': (m['uploadSpeed'] as num?)?.toInt() ?? 0,
                  'downloadSpeed': (m['downloadSpeed'] as num?)?.toInt() ?? 0,
                })
            .toList();
      }
    } catch (_) {}
    return [];
  }

  VpnState _parseState(String s) => switch (s) {
        'connecting' => VpnState.connecting,
        'connected' => VpnState.connected,
        'disconnecting' => VpnState.disconnecting,
        'disconnected' => VpnState.disconnected,
        'error' => VpnState.error,
        _ => VpnState.disconnected,
      };
}
