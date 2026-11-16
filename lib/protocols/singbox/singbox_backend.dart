import '../../core/cores/core_backend.dart';
import '../../core/cores/options_sanitizer.dart';
import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/core_kind.dart';
import '../../core/models/heartbeat_settings.dart';
import '../../core/models/vpn_config.dart';
import '../../core/models/xray_tuning.dart';
import 'singbox_config_builder.dart';
import '../../l10n/l10n.dart';

/// sing-box behind tun2socks: unsupported profiles are disabled, Xray settings
/// that sing-box lacks are ignored with a warning.
class SingBoxBackend implements CoreBackend {
  const SingBoxBackend();

  static Map<CoreFeature, String> get _unsupported => {
    CoreFeature.noise: L10n.current.singboxNoNoise,
    CoreFeature.mux: L10n.current.singboxNoMux,
    CoreFeature.observatory: L10n.current.singboxNoObservatory,
    CoreFeature.rawConfig: L10n.current.singboxNoRawConfig,
  };

  @override
  CoreKind get kind => CoreKind.singBox;

  @override
  bool supports(CoreFeature feature) => !_unsupported.containsKey(feature);

  @override
  String? unavailableReason(CoreFeature feature) => _unsupported[feature];

  @override
  String? checkConfig(VpnConfig config) => SingBoxConfigBuilder.unsupportedReason(config);

  @override
  SettingsCheck checkOptions(VpnConfig config, VpnEngineOptions options) => (
        blocking: null,
        warnings: [
          ..._sanitize(options).warnings,
          // The ML-DSA signature is an extra certificate extension; the main Reality check is the same.
          if (config.postQuantumKey?.isNotEmpty ?? false)
            L10n.current.singboxNoPqv,
        ],
      );

  @override
  HeartbeatProbe effectiveHeartbeatProbe(HeartbeatProbe requested) => requested;

  /// tun2socks drops QUIC, as with the Go core: Vision rejects UDP/443.
  @override
  bool effectiveQuicBlock({required bool requested, required String? flow}) =>
      requested || (flow?.contains('vision') ?? false);

  @override
  String buildConfig(VpnConfig config, VpnEngineOptions options) =>
      SingBoxConfigBuilder.buildJson(config, _sanitize(options).options);

  @override
  String buildProbeConfig(VpnConfig config, VpnEngineOptions options) =>
      SingBoxConfigBuilder.buildProbeJson(config, _sanitize(options).options);

  ({VpnEngineOptions options, List<String> warnings}) _sanitize(VpnEngineOptions o) {
    final packets = o.fragment.packets.trim();
    return (OptionsSanitizer(o)
          ..drop(
            when: o.noise.enabled,
            warning: _unsupported[CoreFeature.noise]!,
            fix: (v) => v.copyWith(noise: v.noise.copyWith(enabled: false)),
          )
          ..drop(
            when: o.mux.enabled,
            warning: _unsupported[CoreFeature.mux]!,
            fix: (v) => v.copyWith(mux: const MuxSettings()),
          )
          ..drop(
            when: o.fragment.enabled && packets != 'tlshello',
            warning: L10n.current.singboxFragmentMode(packets),
            fix: (v) => v.copyWith(fragment: v.fragment.copyWith(enabled: false)),
          ))
        .result;
  }
}
