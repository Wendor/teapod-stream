import '../../core/cores/core_backend.dart';
import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/app_message.dart';
import '../../core/models/core_kind.dart';
import '../../core/models/heartbeat_settings.dart';
import '../../core/models/vpn_config.dart';
import 'xray_config_builder.dart';

/// xray-core (Go) + tun2socks: all features; profiles — except those removed in v26.
class XrayGoBackend implements CoreBackend {
  const XrayGoBackend();

  @override
  CoreKind get kind => CoreKind.xrayGo;

  @override
  bool supports(CoreFeature feature) => true;

  @override
  AppMessage? unavailableReason(CoreFeature feature) => null;

  @override
  AppMessage? checkConfig(VpnConfig config) => XrayConfigBuilder.unsupportedReason(config);

  @override
  SettingsCheck checkOptions(VpnConfig config, VpnEngineOptions options) =>
      (blocking: null, warnings: const <AppMessage>[]);

  @override
  HeartbeatProbe effectiveHeartbeatProbe(HeartbeatProbe requested) => requested;

  /// Vision rejects UDP/443: tun2socks answers with ICMP for any Vision flow.
  @override
  bool effectiveQuicBlock({required bool requested, required String? flow}) =>
      requested || (flow?.contains('vision') ?? false);

  @override
  String buildConfig(VpnConfig config, VpnEngineOptions options) => config.rawXrayConfig != null
      ? XrayConfigBuilder.mergeWithRaw(config.rawXrayConfig!, options)
      : XrayConfigBuilder.buildJson(config, options);

  /// Go strips the temporary instance's inbounds itself.
  @override
  String buildProbeConfig(VpnConfig config, VpnEngineOptions options) => buildConfig(config, options);
}
