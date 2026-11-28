import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/cores/core_switch.dart';
import '../core/interfaces/vpn_engine.dart';
import '../core/models/app_message.dart';
import '../core/models/connection_fingerprint.dart';
import '../core/services/log_service.dart';
import '../protocols/xray/xray_engine.dart';
import 'config_provider.dart';
import 'core_provider.dart';
import 'settings_provider.dart';
import 'vpn_provider.dart';
import 'vpn_switcher.dart';

/// Keeps native following what would run now ([coreSwitchAction]): while off, the quick-connect parameters the tile,
/// boot and automation start from are saved again — or cleared when no core runs the effective config or it fails
/// validation; a live session no core runs anymore is stopped; a live session a core still runs is left to the
/// reconnect banner. It runs when what would run changes and when a session ends (it may have run older settings),
/// never during a profile switch, whose end reconciles ([reconcileNow]). It goes through [VpnNotifier]'s API only;
/// [VpnNotifier] doesn't read it (Riverpod refuses a provider reading one that listens to it), so it is kept alive by
/// a listener of the app's lifecycle provider (a provider that is only read is paused with its listeners).
class QuickConnectReconciler extends Notifier<void> {
  @override
  void build() {
    ref.listen(vpnProvider, (prev, next) {
      if (next.isIdle && prev != null && !prev.isIdle) reconcileSoon();
    });
    ref.listen(_quickConnectSourceProvider, (prev, next) {
      if (prev != null && next != null && prev != next && !_profileSwitching) reconcileSoon();
    });
    // Native reports it is off — also when the published state doesn't change: it accepts the save now, and an
    // earlier one may have been refused while it was stopping (a timed-out connect shows `error` before native stops).
    final events = XrayEngine.events.listen((dynamic event) {
      if (event is Map && event['type'] == 'state') {
        final s = NativeSession.parse(event).state;
        if (s == VpnState.disconnected || s == VpnState.error) reconcileSoon();
      }
    }, onError: (Object _) {});
    ref.onDispose(events.cancel);
  }

  bool get _profileSwitching => ref.read(profileSwitchingProvider);

  VpnNotifier get _vpn => ref.read(vpnProvider.notifier);

  /// Reads what would run now, so a change made while the listener was skipped (a profile switch) doesn't trigger a
  /// second reconciliation after the one its end runs (providers rebuild lazily).
  void absorbPendingChange() => ref.read(_quickConnectSourceProvider);

  /// Runs [reconcileNow] after the notification that asked for it: providers aren't read while they rebuild. Several
  /// asks in one turn (native's off report and the transition it causes) run it once.
  void reconcileSoon() {
    if (_queued) return;
    _queued = true;
    unawaited(
      Future(() async {
        _queued = false;
        if (ref.mounted && !_profileSwitching) await reconcileNow();
      }),
    );
  }

  bool _queued = false;

  Future<void> reconcileNow() async {
    final vpn = _vpn;
    // The saved parameters are built as a connect builds them: geosite codes missing from geosite.dat left out.
    await vpn.loadGeosite();
    // A profile switch begun meanwhile has its settings without its server yet; its end reconciles.
    if (!ref.mounted || _profileSwitching) return;
    final settings = ref.read(settingsProvider).value;
    if (settings == null) return;
    final config = ref.read(effectiveConfigProvider);
    final resolution = config == null ? null : ref.read(coreResolverProvider).resolve(config);
    final backend = resolution?.backend;
    final unsupported = config == null ? const AppMessage(MessageCode.vpnNoConfigSelected) : resolution?.reason;
    final engine = ref.read(xrayEngineProvider);
    try {
      switch (coreSwitchAction(state: ref.read(vpnProvider).connectionState, unsupported: unsupported)) {
        case CoreSwitchAction.none:
          break;
        case CoreSwitchAction.disconnect:
          ref.read(logServiceProvider.notifier).addError('Core: $unsupported');
          await vpn.disconnect(reason: unsupported);
        // A config connect() refuses ([VpnConfig.validate]) isn't saved either; a live session on it stays.
        case CoreSwitchAction.saveQuickConnect when config!.validate() != null:
          await engine.clearQuickConnect();
        case CoreSwitchAction.saveQuickConnect:
          await engine.saveQuickConnect(config!, backend!, vpn.engineOptionsFor(settings, config, backend));
        case CoreSwitchAction.clearQuickConnect:
          await engine.clearQuickConnect();
      }
    } catch (e) {
      ref.read(logServiceProvider.notifier).addError('Core switch: $e');
    }
  }
}

final quickConnectReconcilerProvider = NotifierProvider<QuickConnectReconciler, void>(QuickConnectReconciler.new);

/// What the saved quick-connect parameters are built from: the effective config (its ping results aside) and the
/// connection settings with the core that runs them. null — settings or configs aren't loaded yet.
final _quickConnectSourceProvider = Provider<Object?>((ref) {
  final core = ref.watch(activeCoreProvider);
  final settings = ref.watch(settingsProvider).value;
  if (core == null || settings == null) return null;
  final c = ref.watch(effectiveConfigProvider);
  return (
    config: c == null
        ? null
        : jsonEncode(
            c.toJson()
              ..remove('latencyMs')
              ..remove('lastPingedAt'),
          ),
    connection: connectionFingerprint(settings, core: core.kind),
  );
});
