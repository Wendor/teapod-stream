import '../interfaces/vpn_engine.dart';
import '../models/app_message.dart';
import '../models/core_kind.dart';
import '../models/heartbeat_settings.dart';
import '../models/vpn_config.dart';

/// Features a core may not support.
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

/// [blocking] — connecting is forbidden (the reason); [warnings] — settings
/// the core will ignore.
typedef SettingsCheck = ({AppMessage? blocking, List<AppMessage> warnings});

/// A core on the Dart side: features and config building.
abstract interface class CoreBackend {
  CoreKind get kind;

  bool supports(CoreFeature feature);

  /// null if [feature] is supported.
  AppMessage? unavailableReason(CoreFeature feature);

  /// null — the profile is supported; otherwise the reason (the profile is disabled).
  AppMessage? checkConfig(VpnConfig config);

  /// Global settings for connecting to [config].
  SettingsCheck checkOptions(VpnConfig config, VpnEngineOptions options);

  HeartbeatProbe effectiveHeartbeatProbe(HeartbeatProbe requested);

  /// Whether to block QUIC in TUN: by the switch or because of a Vision [flow].
  bool effectiveQuicBlock({required bool requested, required String? flow});

  String buildConfig(VpnConfig config, VpnEngineOptions options);

  /// Temporary instance config for measuring a candidate's latency.
  String buildProbeConfig(VpnConfig config, VpnEngineOptions options);
}
