import '../../core/cores/core_backend.dart';
import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/core_kind.dart';
import '../../core/models/heartbeat_settings.dart';
import '../../core/models/vpn_config.dart';
import 'xray_config_builder.dart';

/// xray-core (Go) + tun2socks: поддерживает всё.
class XrayGoBackend implements CoreBackend {
  const XrayGoBackend();

  @override
  CoreKind get kind => CoreKind.xrayGo;

  @override
  bool supports(CoreFeature feature) => true;

  @override
  String? unavailableReason(CoreFeature feature) => null;

  @override
  String? checkConfig(VpnConfig config) => null;

  @override
  SettingsCheck checkOptions(VpnConfig config, VpnEngineOptions options) =>
      (blocking: null, warnings: const <String>[]);

  @override
  HeartbeatProbe effectiveHeartbeatProbe(HeartbeatProbe requested) => requested;

  /// Vision отвергает UDP/443: tun2socks отвечает ICMP на любой Vision-flow.
  @override
  bool effectiveQuicBlock({required bool requested, required String? flow}) =>
      requested || (flow?.contains('vision') ?? false);

  @override
  String buildConfig(VpnConfig config, VpnEngineOptions options) =>
      config.rawXrayConfig != null
          ? XrayConfigBuilder.mergeWithRaw(config.rawXrayConfig!, options)
          : XrayConfigBuilder.buildJson(config, options);

  /// Go вырезает inbounds временного инстанса сам.
  @override
  String buildProbeConfig(VpnConfig config, VpnEngineOptions options) =>
      buildConfig(config, options);
}
