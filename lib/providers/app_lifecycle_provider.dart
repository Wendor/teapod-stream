import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auto_switch_provider.dart';
import 'config_provider.dart';
import 'quick_connect_reconciler.dart';
import 'geo_provider.dart';
import 'native_logs_provider.dart';
import 'ping_provider.dart';
import 'settings_provider.dart';
import 'update_provider.dart';
import 'vpn_provider.dart';
import 'vpn_stats_provider.dart';

/// Active tab index. A provider so screens (e.g. Home with an empty config list) can switch tabs.
class TabIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void set(int index) => state = index;
}

final tabIndexProvider = NotifierProvider<TabIndexNotifier, int>(TabIndexNotifier.new);

/// The app's startup and resume steps and their order. The app shell calls [start] after its first frame, and
/// [resumed] / [paused] from its lifecycle observer; what follows a provider (new configs are pinged, the chart is
/// pulled only on the home tab) is listened to here from the moment the shell reads it.
class AppLifecycleNotifier extends Notifier<void> {
  static const updateCheckDelay = Duration(seconds: 5);

  var _started = false;
  Timer? _updateCheck;

  @override
  void build() {
    ref.onDispose(() => _updateCheck?.cancel());
    // Kept listened, not just read: Riverpod pauses an unlistened provider's own listeners. It keeps the saved
    // quick-connect parameters following what would run from the app's start.
    ref.listen(quickConnectReconcilerProvider, (_, _) {});
    // Configs that were added (an import, a subscription) are pinged like the stale ones at startup.
    ref.listen<AsyncValue<ConfigState>>(configProvider, (prev, next) {
      final prevIds = prev?.maybeWhen(data: (d) => d.configs.map((c) => c.id).toSet(), orElse: () => null);
      final nextIds = next.maybeWhen(data: (d) => d.configs.map((c) => c.id).toSet(), orElse: () => null);
      if (prevIds == null || nextIds == null) return;
      if (nextIds.difference(prevIds).isNotEmpty) ref.read(pingProvider.notifier).pingStale();
    });
    // Chart history is pulled only while the home tab is visible.
    ref.listen(tabIndexProvider, (_, next) => ref.read(vpnStatsProvider.notifier).setChartVisible(next == 0));
  }

  /// Startup, once; later calls do nothing. Returns when the steps that wait for something (the subscription
  /// refresh, auto-connect) are done; the update check runs [updateCheckDelay] later.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    // A failed restore still lets the refresh run.
    final restored = ref.read(nativeLogsProvider).restore().then((_) {}, onError: (Object _) {});
    ref.read(autoSwitchProvider);
    ref.read(pingProvider.notifier).pingStale();
    // Only after the VPN state sync: otherwise tunnelSocks is still empty and a subscription would bypass the
    // tunnel when the VPN is already up (from the tile). And after the log restore, which replaces the in-app log:
    // the refresh's errors must stay in it.
    final configs = ref.read(configProvider.notifier);
    final refreshed = Future.wait([restored, ref.read(vpnProvider.notifier).synced]).then((_) {
      if (ref.mounted) return configs.refreshStaleIfDue();
    });
    ref.read(geoProvider.notifier).check();
    _updateCheck = Timer(updateCheckDelay, () {
      if (ref.read(updateProvider) is UpdateIdle) ref.read(updateProvider.notifier).checkForUpdate();
    });
    await Future.wait([refreshed, _autoConnect()]);
  }

  /// Back in the foreground. The subscription staleness is checked here (there is no background timer), after the
  /// sync: the refresh must see the tunnel's current SOCKS.
  Future<void> resumed() async {
    final configs = ref.read(configProvider.notifier);
    ref.read(vpnStatsProvider.notifier).resume();
    await ref.read(vpnProvider.notifier).syncNativeState();
    if (ref.mounted) await configs.refreshStaleIfDue();
  }

  /// In the background: no per-second stats polling over the platform channel until [resumed].
  void paused() => ref.read(vpnStatsProvider.notifier).pause();

  /// With `autoConnect` on and a config to run, connects unless the VPN is already up or coming up.
  Future<void> _autoConnect() async {
    final settings = await ref.read(settingsProvider.future);
    if (!ref.mounted || !settings.autoConnect) return;
    await ref.read(configProvider.future);
    if (!ref.mounted || ref.read(effectiveConfigProvider) == null) return;
    final vpn = ref.read(vpnProvider);
    if (!vpn.isConnected && !vpn.isConnecting) await ref.read(vpnProvider.notifier).connect();
  }
}

final appLifecycleProvider = NotifierProvider<AppLifecycleNotifier, void>(AppLifecycleNotifier.new);
