import '../interfaces/vpn_engine.dart';
import '../models/core_kind.dart';
import '../models/heartbeat_settings.dart';
import '../models/vpn_config.dart';

/// Возможности, которые ядро может не поддерживать.
enum CoreFeature {
  socksAuthentication,
  proxyOnly,
  udpToggle,
  icmpToggle,
  quicBlocking,
  customMtu,
  fragmentation,
  noise,
  mux,
  directDns,
  adBlocking,
  observatory,
  rawConfig,
  geoip,
  geosite,
  appRouting,
  coreDelayProbe,
  passiveHeartbeat,
  tetheringControl,
  outboundDelayProbe,
}

/// [blocking] — подключение запрещено (причина); [warnings] — настройки,
/// которые ядро проигнорирует.
typedef SettingsCheck = ({String? blocking, List<String> warnings});

/// Ядро со стороны Dart: возможности и построение конфига.
abstract interface class CoreBackend {
  CoreKind get kind;

  bool supports(CoreFeature feature);

  /// null, если [feature] поддерживается.
  String? unavailableReason(CoreFeature feature);

  /// null — профиль поддерживается; иначе причина (профиль disabled).
  String? checkConfig(VpnConfig config);

  /// Глобальные настройки для подключения к [config].
  SettingsCheck checkOptions(VpnConfig config, VpnEngineOptions options);

  HeartbeatProbe effectiveHeartbeatProbe(HeartbeatProbe requested);

  /// Блокировать ли QUIC в TUN: по переключателю или из-за Vision-[flow].
  bool effectiveQuicBlock({required bool requested, required String? flow});

  String buildConfig(VpnConfig config, VpnEngineOptions options);

  /// Конфиг временного инстанса для замера задержки кандидата.
  String buildProbeConfig(VpnConfig config, VpnEngineOptions options);
}
