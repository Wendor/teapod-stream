import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/app_message.dart';
import '../core/models/profile_bundle.dart';
import '../core/models/vpn_config.dart';
import '../core/services/log_service.dart';
import 'config_provider.dart';
import 'core_provider.dart';
import 'profile_provider.dart';
import 'quick_connect_reconciler.dart';
import 'vpn_provider.dart';

/// A profile switch is running: it changes the settings and the server one after the other, and what would run in
/// between belongs to neither profile — the reconciler leaves it alone until the switch's end. Written only by
/// [VpnSwitcher]; a provider of its own so the reconciler reads it without depending on the switcher.
class ProfileSwitching extends Notifier<bool> {
  @override
  bool build() => false;

  void _set(bool running) => state = running;
}

final profileSwitchingProvider = NotifierProvider<ProfileSwitching, bool>(ProfileSwitching.new);

/// What the user or the dead-tunnel check switches to — a config, a profile — made to reach the session: one at a
/// time through one queue, each decided against what runs when its turn comes. It goes through [VpnNotifier]'s API
/// (`connect` via `reconnectWithNewConfig`, `reconnectIfStale`) and the reconciler's; neither reads it.
class VpnSwitcher extends Notifier<void> {
  @override
  void build() {}

  VpnNotifier get _vpn => ref.read(vpnProvider.notifier);
  VpnStatus get _state => ref.read(vpnProvider);

  /// Profile switches, config selections and dead-tunnel switches run one at a time, each with its reconciliation: a
  /// later one can't start while the earlier one's connect is in flight. An error doesn't stop the queue.
  Future<void> _switches = Future.value();

  Future<void> _queued(Future<void> Function() body) {
    final run = _switches.then((_) => body());
    _switches = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// The user picked [config] (configs list, server picker): it becomes the active one, and a running or starting
  /// session switches to it unless it already runs it (not awaited: the caller only waits for the selection). Returns
  /// why no enabled core can run it (nothing changes then).
  Future<AppMessage?> selectConfig(VpnConfig config) async {
    final reason = ref.read(coreResolverProvider).resolve(config).reason;
    if (reason != null) return reason;
    await ref.read(configProvider.notifier).setActiveConfig(config.id);
    // Queued behind earlier selections' reconnects and decided against what runs then: overlapping selections end
    // on the last one saved.
    unawaited(_queued(_followSelection));
    return null;
  }

  /// A dead-tunnel switch (`autoSwitchProvider`) from [dead] — the [VpnNotifier.runningConfig] that stopped answering — to [to],
  /// the fastest live candidate, queued like a selection and dropped when by its turn the session runs another config
  /// (a selection or a profile switch came first). [measured] — urltest's latency by config id (null — no answer).
  /// In auto mode with [to] in the auto subscription, auto mode stays: the subscription's ping results become this
  /// measurement — a config it didn't answer or didn't probe (the dead one, another switch source) has none — so its
  /// best is [to] (or a candidate as fast). Otherwise [to] becomes the active config, as a selection makes it. A live
  /// session is then rebuilt.
  Future<void> switchDeadTunnel({
    required VpnConfig dead,
    required VpnConfig to,
    required Map<String, int?> measured,
  }) => _queued(() async {
    if (_vpn.runningConfig?.id != dead.id) {
      ref
          .read(logServiceProvider.notifier)
          .addInfo('urltest: the server changed meanwhile, no switch', source: 'urltest');
      return;
    }
    final configs = ref.read(configProvider.notifier);
    final cs = ref.read(configProvider).value;
    final auto = cs?.activeSubscriptionId;
    if (cs != null && auto != null && to.subscriptionId == auto) {
      await configs.setLatencies({
        for (final c in cs.configs)
          if (c.subscriptionId == auto) c.id: measured[c.id],
      }, DateTime.now());
    } else {
      await configs.setActiveConfig(to.id);
    }
    // Off meanwhile: the selection reaches quick connect through the source listener.
    if (_state.isConnected || _state.isConnecting) await _vpn.reconnectWithNewConfig();
  });

  /// Makes the tunnel run the active config: a connect in flight is redone, a live tunnel on another config switches,
  /// one on this config stays. An idle VPN saves it for quick connect through the source listener.
  Future<void> _followSelection() async {
    if (_state.isBusy) return _vpn.reconnectWithNewConfig();
    final config = ref.read(effectiveConfigProvider);
    if (_state.isConnected && config != null && !_vpn.runsConfig(config)) await _vpn.reconnectWithNewConfig();
  }

  /// Switches to profile [id]; the VPN follows once its settings and server are in place, also when restoring the
  /// server failed: the profile is already switched, and a retry can't — it is active.
  Future<void> switchProfile(String id) =>
      duringProfileSwitch(() => ref.read(profileProvider.notifier).switchProfile(id));

  /// Adds [bundle]'s profile and its connections (`ProfileNotifier.importBundle`), then switches to it when
  /// [switchTo]; returns its id.
  Future<String?> importProfile(
    ProfileBundle bundle, {
    bool makeReadonly = false,
    String? sourceUrl,
    bool switchTo = true,
  }) async {
    final id = await ref
        .read(profileProvider.notifier)
        .importBundle(bundle, makeReadonly: makeReadonly, sourceUrl: sourceUrl);
    if (switchTo && id != null) await switchProfile(id);
    return id;
  }

  /// Runs a profile switch ([body] returns false — nothing switched), then makes the VPN follow the
  /// final state: a profile no core runs disconnects (as a core change does), a live tunnel is
  /// rebuilt if stale, a core change suppressed meanwhile is handled, an idle VPN saves the quick-connect parameters.
  @visibleForTesting
  Future<void> duringProfileSwitch(Future<bool> Function() body) => _queued(() => _profileSwitch(body));

  Future<void> _profileSwitch(Future<bool> Function() body) async {
    final coreBefore = ref.read(activeCoreProvider);
    final switching = ref.read(profileSwitchingProvider.notifier).._set(true);
    var switched = true; // also on an error: the profile may be switched with its server not restored
    try {
      switched = await body();
    } finally {
      // Providers rebuild lazily: read here, the switch's change reaches the source listener while it is skipped, and
      // the reconciliation below is the only one.
      ref.read(quickConnectReconcilerProvider.notifier).absorbPendingChange();
      switching._set(false);
      final core = ref.read(activeCoreProvider);
      final live = switched && (_state.isConnected || _state.isConnecting);
      if (live && core?.kind != null) {
        await _vpn.reconnectIfStale();
      } else if (live || core != coreBefore || _state.isIdle) {
        // Off: the profile's server and connection settings reach the saved quick-connect parameters (the settings
        // listener skips the switch).
        await ref.read(quickConnectReconcilerProvider.notifier).reconcileNow();
      }
    }
  }
}

final vpnSwitcherProvider = NotifierProvider<VpnSwitcher, void>(VpnSwitcher.new);
