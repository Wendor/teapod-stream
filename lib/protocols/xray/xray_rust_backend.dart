import '../../core/cores/core_backend.dart';
import '../../core/cores/options_sanitizer.dart';
import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/core_kind.dart';
import '../../core/models/heartbeat_settings.dart';
import '../../core/models/vpn_config.dart';
import '../../core/models/xray_tuning.dart';
import 'rust_config_builder.dart';
import '../../l10n/l10n.dart';

/// xray-rust: unsupported profiles are disabled, unsupported settings
/// are ignored with a warning; proxy-only blocks connecting.
class XrayRustBackend implements CoreBackend {
  const XrayRustBackend();

  static Map<CoreFeature, String> get _unsupported => {
    CoreFeature.proxyOnly: L10n.current.rustNoProxyOnly,
    CoreFeature.icmpToggle: L10n.current.rustIcmpLocal,
    CoreFeature.customMtu: L10n.current.rustMtuIgnored,
    CoreFeature.mux: L10n.current.rustMuxIgnored,
    CoreFeature.observatory: L10n.current.rustNoObservatory,
    CoreFeature.rawConfig: L10n.current.rustNoRawConfig,
  };

  @override
  CoreKind get kind => CoreKind.xrayRust;

  @override
  bool supports(CoreFeature feature) => !_unsupported.containsKey(feature);

  @override
  String? unavailableReason(CoreFeature feature) => _unsupported[feature];

  @override
  String? checkConfig(VpnConfig config) => RustConfigBuilder.unsupportedReason(config);

  @override
  SettingsCheck checkOptions(VpnConfig config, VpnEngineOptions options) {
    if (options.proxyOnly) {
      return (blocking: _unsupported[CoreFeature.proxyOnly], warnings: const <String>[]);
    }
    final sanitized = _sanitize(config, options);
    final overBudget = RustConfigBuilder.geositeDomains(sanitized.options) > RustConfigBuilder.maxDomainMatchers;
    return (blocking: overBudget ? L10n.current.rustGeositeLimit : null, warnings: sanitized.warnings);
  }

  /// Vision rejects UDP/443. For plain Vision the core answers with ICMP itself,
  /// the blackhole rule is needed only for -udp443 or by the switch.
  @override
  bool effectiveQuicBlock({required bool requested, required String? flow}) =>
      requested || flow == 'xtls-rprx-vision-udp443';

  @override
  HeartbeatProbe effectiveHeartbeatProbe(HeartbeatProbe requested) => requested;

  @override
  String buildConfig(VpnConfig config, VpnEngineOptions options) =>
      RustConfigBuilder.buildJson(config, _sanitize(config, options).options);

  @override
  String buildProbeConfig(VpnConfig config, VpnEngineOptions options) =>
      RustConfigBuilder.buildProbeJson(config, _sanitize(config, options).options);

  /// Options the core won't apply are replaced with allowed ones; each replacement is a warning.
  ({VpnEngineOptions options, List<String> warnings}) _sanitize(VpnConfig config, VpnEngineOptions o) {
    final routing = o.routing;
    final domainRules =
        routing.geositeEnabled || routing.domainEnabled || routing.sitesEnabled || routing.ruServicesEnabled;
    final s = OptionsSanitizer(o)
      ..drop(
        when: o.mux.enabled && config.protocol != VpnProtocol.hysteria2,
        warning: _unsupported[CoreFeature.mux]!,
        fix: (v) => v.copyWith(mux: const MuxSettings()),
      )
      ..drop(when: o.mtu != 1500, warning: _unsupported[CoreFeature.customMtu]!, fix: (v) => v.copyWith(mtu: 1500))
      ..warn(when: o.allowIcmp, warning: _unsupported[CoreFeature.icmpToggle]!)
      ..drop(
        when: routing.isActive && !o.sniffingEnabled && domainRules,
        warning: L10n.current.rustSniffingForced,
        fix: (v) => v.copyWith(sniffingEnabled: true),
      );
    // Entries over xray-rust's limits come trimmed; ad blocking goes first when the rest is over the budget.
    final trimmed = RustConfigBuilder.trimmedGeosite(o);
    s.warn(when: trimmed.isNotEmpty, warning: L10n.current.rustGeositeTrimmed(trimmed.join(', ')));
    s.drop(
      when:
          s.result.options.routing.adBlockEnabled &&
          RustConfigBuilder.geositeDomains(s.result.options) > RustConfigBuilder.maxDomainMatchers,
      warning: L10n.current.rustAdBlockDropped,
      fix: (v) => v.copyWith(routing: v.routing.copyWith(adBlockEnabled: false)),
    );
    final fragmentError = _maskError(() => RustConfigBuilder.fragmentMask(config, o.fragment));
    s.drop(
      when: fragmentError != null,
      warning: L10n.current.rustFragmentDropped(fragmentError ?? ''),
      fix: (v) => v.copyWith(fragment: v.fragment.copyWith(enabled: false)),
    );
    final noiseError = _maskError(() => RustConfigBuilder.noiseMask(config, o.noise));
    s.drop(
      when: noiseError != null,
      warning: L10n.current.rustNoiseDropped(noiseError ?? ''),
      fix: (v) => v.copyWith(noise: v.noise.copyWith(enabled: false)),
    );
    return s.result;
  }

  static String? _maskError(void Function() build) {
    try {
      build();
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }
}
