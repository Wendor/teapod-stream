import '../../core/cores/core_backend.dart';
import '../../core/cores/options_sanitizer.dart';
import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/core_kind.dart';
import '../../core/models/heartbeat_settings.dart';
import '../../core/models/vpn_config.dart';
import '../../core/models/xray_tuning.dart';
import 'rust_config_builder.dart';

/// xray-rust: неподдерживаемые профили — disabled, неподдерживаемые настройки
/// игнорируются с предупреждением; proxy-only запрещает подключение.
class XrayRustBackend implements CoreBackend {
  const XrayRustBackend();

  static const _unsupported = <CoreFeature, String>{
    CoreFeature.proxyOnly: 'Режим «только прокси» недоступен в ядре xray-rust: оно работает только через TUN.',
    CoreFeature.icmpToggle: 'ICMP обрабатывается ядром xray-rust локально; настройка не применяется.',
    CoreFeature.customMtu: 'Ядро xray-rust работает с MTU 1500; другое значение не применяется.',
    CoreFeature.mux: 'Mux недоступен в ядре xray-rust и не применяется.',
    CoreFeature.observatory: 'Observatory и управляемые JSON-конфиги недоступны в ядре xray-rust.',
    CoreFeature.rawConfig: 'Полный JSON-конфиг недоступен в ядре xray-rust.',
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
    return (blocking: null, warnings: _sanitize(config, options).warnings);
  }

  /// Vision отвергает UDP/443. Для обычного Vision ядро само отвечает ICMP,
  /// правило blackhole нужно только для -udp443 или по переключателю.
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

  /// Опции, которые ядро не применит, заменяются допустимыми; каждая замена — предупреждение.
  ({VpnEngineOptions options, List<String> warnings}) _sanitize(VpnConfig config, VpnEngineOptions o) {
    final routing = o.routing;
    final domainRules = routing.geositeEnabled || routing.domainEnabled ||
        routing.sitesEnabled || routing.ruServicesEnabled;
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
        warning: 'Доменные правила в ядре xray-rust требуют определения доменов — оно включено для этого подключения.',
        fix: (v) => v.copyWith(sniffingEnabled: true),
      )
      ..drop(
        when: routing.adBlockEnabled && routing.isActive && routing.geositeEnabled &&
            routing.geositeCodes.any((c) => RustConfigBuilder.largeGeositeCodes.contains(c.trim().toLowerCase())),
        warning: 'Блокировка рекламы вместе с большой категорией GeoSite превышает лимит ядра xray-rust '
            'в 250 тыс. доменных правил — блокировка рекламы не применяется.',
        fix: (v) => v.copyWith(routing: v.routing.copyWith(adBlockEnabled: false)),
      );
    final fragmentError = _maskError(() => RustConfigBuilder.fragmentMask(config, o.fragment));
    s.drop(
      when: fragmentError != null,
      warning: 'Фрагментация не применяется: $fragmentError',
      fix: (v) => v.copyWith(fragment: v.fragment.copyWith(enabled: false)),
    );
    final noiseError = _maskError(() => RustConfigBuilder.noiseMask(config, o.noise));
    s.drop(
      when: noiseError != null,
      warning: 'Шумы не применяются: $noiseError',
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
