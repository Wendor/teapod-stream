import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/interfaces/vpn_engine.dart';
import '../core/models/vpn_config.dart';
import '../protocols/xray/xray_engine.dart';
import 'config_provider.dart';
import 'settings_provider.dart';
import 'vpn_provider.dart';

/// Pings the configs' servers directly, not through the tunnel: each `address:port` once ([XrayEngine.pingConfig]:
/// ICMP, then TCP), the results stored in one batch. The state: a ping is running (one at a time).
///
/// The app is excluded from the tunnel, so a ping always goes outside it and shows the network every server of the
/// list. While the VPN is up (connecting, connected, the kill switch holding traffic) nothing is pinged unless the user
/// allowed it ([AppSettings.pingWhileConnected]). A ping through the tunnel's SOCKS would measure nothing: the core
/// answers a SOCKS CONNECT before it reaches the server.
class PingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Every config (the configs screen's button). False when the VPN is up and pings while connected are off.
  Future<bool> pingAll() => _ping(stale: false);

  /// Configs never pinged or pinged more than an hour ago (on start, after configs are added).
  Future<void> pingStale() => _ping(stale: true);

  /// A ping may go out now: the VPN is down, or the user allowed pings while it is up.
  bool get allowed {
    final vpn = ref.read(vpnProvider).connectionState;
    if (vpn == VpnState.disconnected || vpn == VpnState.error) return true;
    return ref.read(settingsProvider).value?.pingWhileConnected ?? false;
  }

  Future<bool> _ping({required bool stale}) async {
    if (!allowed) return false;
    if (state) return true;
    final configState = ref.read(configProvider).maybeWhen(data: (d) => d, orElse: () => null);
    if (configState == null) return true;
    final now = DateTime.now();
    final configs = stale
        ? configState.configs
              .where((c) => c.lastPingedAt == null || now.difference(c.lastPingedAt!) > const Duration(hours: 1))
              .toList()
        : configState.configs;
    if (stale && configs.isEmpty) return true;
    state = true;
    try {
      await _pingEndpoints(configs);
    } finally {
      if (ref.mounted) state = false;
    }
    return true;
  }

  Future<void> _pingEndpoints(List<VpnConfig> configs) async {
    final now = DateTime.now();
    // Prefer non-raw configs per endpoint so TCP probe works for shared servers
    final endpoints = <String, VpnConfig>{};
    for (final c in configs) {
      if (c.rawXrayConfig == null) {
        endpoints[c.endpoint] = c;
      }
    }
    for (final c in configs) {
      if (c.rawXrayConfig != null) {
        endpoints.putIfAbsent(c.endpoint, () => c);
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
