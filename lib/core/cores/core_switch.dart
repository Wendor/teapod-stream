import '../interfaces/vpn_engine.dart';
import '../models/vpn_config.dart';
import 'core_backend.dart';
import 'core_resolver.dart';

enum CoreSwitchAction { none, disconnect, saveQuickConnect, clearQuickConnect }

/// What to do after a core change. [unsupported] — why the active
/// profile (or settings) won't start on the new core; null — they will.
/// A connected VPN on a supported profile waits for a reconnect (banner).
CoreSwitchAction coreSwitchAction({required VpnState state, required String? unsupported}) =>
    switch (state) {
      VpnState.connected || VpnState.connecting || VpnState.blocked =>
        unsupported != null ? CoreSwitchAction.disconnect : CoreSwitchAction.none,
      VpnState.disconnected || VpnState.error =>
        unsupported == null ? CoreSwitchAction.saveQuickConnect : CoreSwitchAction.clearQuickConnect,
      VpnState.disconnecting => CoreSwitchAction.none,
    };

/// Auto-switch candidates that at least one core runs — with that core.
List<({VpnConfig config, CoreBackend backend})> supportedCandidates(
        Iterable<VpnConfig> configs, CoreResolver resolver) =>
    [
      for (final c in configs)
        if (resolver.resolve(c).backend case final backend?) (config: c, backend: backend),
    ];
