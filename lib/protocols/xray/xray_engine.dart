import 'dart:math';
import 'package:flutter/services.dart';
import '../../core/constants/app_constants.dart';
import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/vpn_config.dart';
import '../../core/models/vpn_log_entry.dart';
import 'xray_config_builder.dart';

/// XrayEngine is a thin MethodChannel client — it sends commands to the native
/// Android VPN service and nothing else. All state, stats, and log events are
/// delivered via EventChannel and processed directly by VpnNotifier.
class XrayEngine implements VpnEngine {
  static const _channel = MethodChannel(AppConstants.methodChannel);

  @override
  String get protocolName => 'xray';

  /// Собирает JSON для xray: готовый конфиг подписки или сгенерированный.
  static String buildConfigJson(VpnConfig config, VpnEngineOptions options) =>
      config.rawXrayConfig != null
          ? XrayConfigBuilder.mergeWithRaw(config.rawXrayConfig!, options)
          : XrayConfigBuilder.buildJson(config, options);

  /// Текущий физический транспорт: `wifi`, `cellular` или `other`.
  /// null — native не ответил.
  Future<String?> getActiveTransport() async {
    try {
      return await _channel.invokeMethod<String>('getActiveTransport');
    } catch (_) {
      return null;
    }
  }

  /// Перезаписывает конфиги сетевых правил на диске без разрыва туннеля —
  /// новые правила применятся при ближайшей смене сети или реконнекте.
  Future<void> updateNetworkProfiles({String? wifi, String? cellular}) async {
    try {
      await _channel.invokeMethod('updateNetworkProfiles', {
        'xrayConfigWifi': wifi,
        'xrayConfigCellular': cellular,
      });
    } catch (_) {
      // Non-critical: профили перезапишутся при следующем connect().
    }
  }

  @override
  Future<void> connect(
    VpnConfig config,
    VpnEngineOptions options, {
    String? xrayConfigWifi,
    String? xrayConfigCellular,
    bool suspendNetworkRule = false,
  }) async {
    final xrayConfig = buildConfigJson(config, options);

    await _channel.invokeMethod('connect', {
      'xrayConfig': xrayConfig,
      'xrayConfigWifi': xrayConfigWifi,
      'xrayConfigCellular': xrayConfigCellular,
      'suspendNetworkRule': suspendNetworkRule,
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
      'mtu': options.mtu,
      'heartbeatProbe': options.heartbeat.probe.name,
      'heartbeatAction': options.heartbeat.failAction.name,
      'heartbeatThreshold': options.heartbeat.failureThreshold,
      'heartbeatUrl': options.heartbeat.url,
      if (config.ssPrefix != null) 'ssPrefix': config.ssPrefix,
    });
  }


  @override
  Future<void> disconnect() async {
    await _channel.invokeMethod('disconnect');
  }

  /// Замер задержки через кандидата: временный xray-инстанс с его конфигом
  /// (`Teapodcore.measureOutboundDelay`). null — сервер не ответил.
  Future<int?> measureOutbound(VpnConfig config, VpnEngineOptions options, String url) async {
    try {
      final xrayConfig = config.rawXrayConfig != null
          ? XrayConfigBuilder.mergeWithRaw(config.rawXrayConfig!, options)
          : XrayConfigBuilder.buildJson(config, options);
      return await _channel.invokeMethod<int>('measureOutbound', {
        'config': xrayConfig,
        'url': url,
      });
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int?> pingConfig(VpnConfig config) async {
    if (config.address.isEmpty || config.address == 'managed') return null;
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
  Future<({VpnState state, int socksPort, String socksUser, String socksPassword, int connectedAtMs, String networkProfile, String networkTransport})>
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
          connectedAtMs: (result['connectedAtMs'] as num?)?.toInt() ?? 0,
          networkProfile: result['networkProfile'] as String? ?? '',
          networkTransport: result['networkTransport'] as String? ?? '',
        );
      }
    } catch (_) {}
    return (state: VpnState.disconnected, socksPort: 0, socksUser: '', socksPassword: '', connectedAtMs: 0, networkProfile: '', networkTransport: '');
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
      return lines.whereType<String>().map((line) {
        final idx1 = line.indexOf('|');
        final idx2 = line.indexOf('|', idx1 + 1);
        if (idx1 < 0 || idx2 < 0) return null;
        final ts = int.tryParse(line.substring(0, idx1));
        if (ts == null) return null;
        final levelStr = line.substring(idx1 + 1, idx2);
        final message = line.substring(idx2 + 1);
        final level = LogLevel.values.firstWhere(
          (e) => e.name == levelStr,
          orElse: () => LogLevel.info,
        );
        return VpnLogEntry(
          timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
          level: level,
          message: message,
          source: 'xray',
        );
      }).whereType<VpnLogEntry>().toList();
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
        'reconnecting' => VpnState.connecting,
        'connected' => VpnState.connected,
        'disconnecting' => VpnState.disconnecting,
        'disconnected' => VpnState.disconnected,
        'error' => VpnState.error,
        'blocked' => VpnState.blocked,
        _ => VpnState.disconnected,
      };
}
