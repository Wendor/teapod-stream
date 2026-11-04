import '../interfaces/vpn_engine.dart';
import '../models/vpn_config.dart';
import 'core_backend.dart';

enum CoreSwitchAction { none, disconnect, saveQuickConnect, clearQuickConnect }

/// Что сделать после смены ядра. [unsupported] — причина, по которой активный
/// профиль (или настройки) не запустятся на новом ядре; null — запустятся.
/// Подключённый VPN на поддерживаемом профиле ждёт переподключения (баннер).
CoreSwitchAction coreSwitchAction({required VpnState state, required String? unsupported}) =>
    switch (state) {
      VpnState.connected || VpnState.connecting || VpnState.blocked =>
        unsupported != null ? CoreSwitchAction.disconnect : CoreSwitchAction.none,
      VpnState.disconnected || VpnState.error =>
        unsupported == null ? CoreSwitchAction.saveQuickConnect : CoreSwitchAction.clearQuickConnect,
      VpnState.disconnecting => CoreSwitchAction.none,
    };

/// Кандидаты автопереключения, которые [backend] может запустить.
List<VpnConfig> supportedCandidates(Iterable<VpnConfig> configs, CoreBackend backend) =>
    configs.where((c) => backend.checkConfig(c) == null).toList();
