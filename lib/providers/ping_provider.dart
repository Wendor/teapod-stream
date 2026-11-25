import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/vpn_config.dart';
import '../protocols/xray/xray_engine.dart';
import 'config_provider.dart';

/// Pings the configs' servers directly, not through the tunnel: each `address:port` once ([XrayEngine.pingConfig]:
/// ICMP, then TCP), the results stored in one batch. The state: a ping is running (one at a time).
class PingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Every config (the configs screen's button).
  Future<void> pingAll() => _ping(stale: false);

  /// Configs never pinged or pinged more than an hour ago (on start, after configs are added).
  Future<void> pingStale() => _ping(stale: true);

  Future<void> _ping({required bool stale}) async {
    if (state) return;
    final configState = ref.read(configProvider).maybeWhen(data: (d) => d, orElse: () => null);
    if (configState == null) return;
    final now = DateTime.now();
    final configs = stale
        ? configState.configs
              .where((c) => c.lastPingedAt == null || now.difference(c.lastPingedAt!) > const Duration(hours: 1))
              .toList()
        : configState.configs;
    if (stale && configs.isEmpty) return;
    state = true;
    try {
      await _pingEndpoints(configs);
    } finally {
      if (ref.mounted) state = false;
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

    final engine = ref.read(xrayEngineProvider);
    final results = await Future.wait(
      endpoints.entries.map((e) async {
        final ms = await engine.pingConfig(e.value);
        return MapEntry(e.key, ms);
      }),
    );
    final latencyMap = Map.fromEntries(results);
    if (!ref.mounted) return;

    // Single batch update — one storage write, one state update
    await ref.read(configProvider.notifier).batchUpdatePingResults(latencyMap, now);
  }
}

final pingProvider = NotifierProvider<PingNotifier, bool>(PingNotifier.new);
