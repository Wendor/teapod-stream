import '../../core/cores/core_backend.dart';
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
    CoreFeature.proxyOnly: 'Режим «только прокси» недоступен в ядре Xray (Rust): оно работает только через TUN.',
    CoreFeature.icmpToggle: 'ICMP обрабатывается ядром Xray (Rust) локально; настройка не применяется.',
    CoreFeature.customMtu: 'Ядро Xray (Rust) работает с MTU 1500; другое значение не применяется.',
    CoreFeature.mux: 'Mux недоступен в ядре Xray (Rust) и не применяется.',
    CoreFeature.observatory: 'Observatory и управляемые JSON-конфиги недоступны в ядре Xray (Rust).',
    CoreFeature.rawConfig: 'Полный JSON-конфиг недоступен в ядре Xray (Rust).',
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
    final warnings = <String>[];
    var mux = o.mux;
    var mtu = o.mtu;
    var routing = o.routing;
    var fragment = o.fragment;
    var noise = o.noise;
    var sniffing = o.sniffingEnabled;
    if (mux.enabled && config.protocol != VpnProtocol.hysteria2) {
      warnings.add(_unsupported[CoreFeature.mux]!);
      mux = const MuxSettings();
    }
    if (mtu != 1500) {
      warnings.add(_unsupported[CoreFeature.customMtu]!);
      mtu = 1500;
    }
    if (o.allowIcmp) warnings.add(_unsupported[CoreFeature.icmpToggle]!);
    final domainRules = routing.geositeEnabled || routing.domainEnabled ||
        routing.sitesEnabled || routing.ruServicesEnabled;
    if (routing.isActive && !sniffing && domainRules) {
      warnings.add('Доменные правила в ядре Xray (Rust) требуют определения доменов — оно включено для этого подключения.');
      sniffing = true;
    }
    if (routing.adBlockEnabled && routing.isActive && routing.geositeEnabled &&
        routing.geositeCodes.any((c) => RustConfigBuilder.largeGeositeCodes.contains(c.trim().toLowerCase()))) {
      warnings.add('Блокировка рекламы вместе с большой категорией GeoSite превышает лимит ядра Xray (Rust) '
          'в 250 тыс. доменных правил — блокировка рекламы не применяется.');
      routing = routing.copyWith(adBlockEnabled: false);
    }
    try {
      RustConfigBuilder.fragmentMask(config, fragment);
    } on FormatException catch (e) {
      warnings.add('Фрагментация не применяется: ${e.message}');
      fragment = fragment.copyWith(enabled: false);
    }
    try {
      RustConfigBuilder.noiseMask(config, noise);
    } on FormatException catch (e) {
      warnings.add('Шумы не применяются: ${e.message}');
      noise = noise.copyWith(enabled: false);
    }
    return (
      options: o.copyWith(mux: mux, mtu: mtu, routing: routing, fragment: fragment, noise: noise, sniffingEnabled: sniffing),
      warnings: warnings,
    );
  }
}
