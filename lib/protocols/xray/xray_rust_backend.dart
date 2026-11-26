import '../../core/cores/core_backend.dart';
import '../../core/cores/options_sanitizer.dart';
import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/app_message.dart';
import '../../core/models/core_kind.dart';
import '../../core/models/heartbeat_settings.dart';
import '../../core/models/vpn_config.dart';
import '../../core/models/xray_tuning.dart';
import 'rust_config_builder.dart';

/// xray-rust: unsupported profiles are disabled, unsupported settings
/// are ignored with a warning; proxy-only blocks connecting.
class XrayRustBackend implements CoreBackend {
  const XrayRustBackend();

  static final Map<CoreFeature, AppMessage> _unsupported = {
    CoreFeature.proxyOnly: AppMessage.l10n((l) => l.rustNoProxyOnly),
    CoreFeature.icmpToggle: AppMessage.l10n((l) => l.rustIcmpLocal),
    CoreFeature.customMtu: AppMessage.l10n((l) => l.rustMtuIgnored),
    CoreFeature.mux: AppMessage.l10n((l) => l.rustMuxIgnored),
    CoreFeature.observatory: AppMessage.l10n((l) => l.rustNoObservatory),
    CoreFeature.rawConfig: AppMessage.l10n((l) => l.rustNoRawConfig),
  };

  @override
  CoreKind get kind => CoreKind.xrayRust;

  @override
  bool supports(CoreFeature feature) => !_unsupported.containsKey(feature);

  @override
  AppMessage? unavailableReason(CoreFeature feature) => _unsupported[feature];

  @override
  AppMessage? checkConfig(VpnConfig config) => switch (RustConfigBuilder.unsupportedReason(config)) {
    final r? => AppMessage.text(r),
    null => null,
  };

  @override
  SettingsCheck checkOptions(VpnConfig config, VpnEngineOptions options) {
    if (options.proxyOnly) {
      return (blocking: _unsupported[CoreFeature.proxyOnly], warnings: const <AppMessage>[]);
    }
    final sanitized = _sanitize(config, options);
    final overBudget = RustConfigBuilder.domainMatchers(sanitized.options) > RustConfigBuilder.maxDomainMatchers;
    return (blocking: overBudget ? AppMessage.l10n((l) => l.rustGeositeLimit) : null, warnings: sanitized.warnings);
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
  ({VpnEngineOptions options, List<AppMessage> warnings}) _sanitize(VpnConfig config, VpnEngineOptions o) {
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
        warning: AppMessage.l10n((l) => l.rustSniffingForced),
        fix: (v) => v.copyWith(sniffingEnabled: true),
      );
    // Over the matcher budget ad blocking goes first; entries over xray-rust's limits come trimmed.
    s.drop(
      when:
          s.result.options.routing.adBlockEnabled &&
          RustConfigBuilder.domainMatchers(s.result.options) > RustConfigBuilder.maxDomainMatchers,
      warning: AppMessage.l10n((l) => l.rustAdBlockDropped),
      fix: (v) => v.copyWith(routing: v.routing.copyWith(adBlockEnabled: false)),
    );
    final trimmed = RustConfigBuilder.trimmedGeosite(s.result.options);
    s.warn(when: trimmed.isNotEmpty, warning: AppMessage.l10n((l) => l.rustGeositeTrimmed(trimmed.join(', '))));
    final fragmentError = _maskError(() => RustConfigBuilder.fragmentMask(config, o.fragment));
    s.drop(
      when: fragmentError != null,
      warning: AppMessage.l10n((l) => l.rustFragmentDropped(fragmentError ?? '')),
      fix: (v) => v.copyWith(fragment: v.fragment.copyWith(enabled: false)),
    );
    final noiseError = _maskError(() => RustConfigBuilder.noiseMask(config, o.noise));
    s.drop(
      when: noiseError != null,
      warning: AppMessage.l10n((l) => l.rustNoiseDropped(noiseError ?? '')),
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
