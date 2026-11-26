import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/cores/core_switch.dart';
import '../core/cores/engine_options.dart';
import '../core/models/app_settings.dart';
import '../core/models/heartbeat_settings.dart';
import '../core/models/vpn_config.dart';
import '../core/services/log_service.dart';
import '../protocols/xray/xray_engine.dart';
import 'config_provider.dart';
import 'core_provider.dart';
import 'settings_provider.dart';
import 'vpn_provider.dart';

/// Switches the config on a dead tunnel (urltest): the native heartbeat ran out of attempts and sent `tunnel_dead`.
/// Lives as long as the app shell reads it.
class AutoSwitch {
  AutoSwitch(this._ref) {
    _sub = XrayEngine.events.listen((dynamic event) {
      if (event is Map && event['type'] == 'tunnel_dead') _run((event['failures'] as num?)?.toInt() ?? 0).ignore();
    });
  }

  final Ref _ref;
  late final StreamSubscription<dynamic> _sub;
  bool _running = false;

  void _dispose() => _sub.cancel();

  /// With `heartbeat.failAction = switchConfig`: measure the candidates and reconnect to the fastest live one. If none
  /// is alive — do nothing, the service reconnects itself on its cooldown.
  Future<void> _run(int failures) async {
    if (_running) return;
    _running = true;
    final log = _ref.read(logServiceProvider.notifier);
    try {
      final settings = _ref.read(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null) ?? const AppSettings();
      if (settings.heartbeat.failAction != HeartbeatFailAction.switchConfig) return;

      final configState = _ref.read(configProvider).maybeWhen(data: (d) => d, orElse: () => null);
      if (configState == null) return;
      // The config that failed is the one the session runs: in auto mode a ping may have moved the effective one.
      final current = _ref.read(vpnProvider.notifier).runningConfig;
      if (current == null) return;
      await _ref.read(availableCoresProvider.future);
      final candidates = supportedCandidates(
        _candidates(configState, settings.heartbeat.switchSource, current),
        _ref.read(coreResolverProvider),
      );
      if (candidates.isEmpty) {
        log.addError('urltest: no candidates to switch to (failures: $failures)');
        return;
      }

      log.addInfo('urltest: tunnel not responding, checking ${candidates.length} config(s)', source: 'urltest');
      // The measurement goes through a temporary core instance with the candidate's config: a TCP ping would say
      // "alive" even for a server whose port is open while the protocol is silent. The probe keeps only what affects
      // the outbound.
      final engine = _ref.read(xrayEngineProvider);
      final geosite = _ref.read(coreResolverProvider).geosite;
      final probed = await Future.wait(
        candidates.map((c) async {
          final options = buildEngineOptions(settings, c.config, c.backend, geosite: geosite);
          final ms = await engine.measureOutbound(c.config, c.backend, options, settings.heartbeat.url);
          return (config: c.config, latency: ms);
        }),
      );
      final alive = probed.where((r) => r.latency != null).toList()..sort((a, b) => a.latency!.compareTo(b.latency!));
      if (alive.isEmpty) {
        log.addError('urltest: no live configs found, staying on the current one');
        return;
      }

      final best = alive.first;
      log.addInfo('urltest: switching to "${best.config.name}" (${best.latency} ms)', source: 'urltest');
      await _ref
          .read(vpnProvider.notifier)
          .switchDeadTunnel(
            dead: current,
            to: best.config,
            measured: {
              '${current.address}:${current.port}': null,
              for (final r in probed) '${r.config.address}:${r.config.port}': r.latency,
            },
          );
    } catch (e) {
      log.addError('urltest: switch error: $e');
    } finally {
      _running = false;
    }
  }

  /// Switch candidates: the active config is excluded — it just failed the probe.
  List<VpnConfig> _candidates(ConfigState configState, SwitchSource source, VpnConfig current) {
    final all = configState.configs.where((c) => c.id != current.id);
    return switch (source) {
      SwitchSource.subscription => all.where((c) => c.subscriptionId == current.subscriptionId).toList(),
      SwitchSource.pinned => all.where(configState.isPinned).toList(),
      SwitchSource.all => all.toList(),
    };
  }
}

final autoSwitchProvider = Provider<AutoSwitch>((ref) {
  final s = AutoSwitch(ref);
  ref.onDispose(s._dispose);
  return s;
});
