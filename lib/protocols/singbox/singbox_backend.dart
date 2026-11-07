import '../../core/cores/core_backend.dart';
import '../../core/cores/options_sanitizer.dart';
import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/core_kind.dart';
import '../../core/models/heartbeat_settings.dart';
import '../../core/models/vpn_config.dart';
import '../../core/models/xray_tuning.dart';
import 'singbox_config_builder.dart';

/// sing-box за tun2socks: неподдерживаемые профили — disabled, настройки Xray,
/// которых нет в sing-box, игнорируются с предупреждением.
class SingBoxBackend implements CoreBackend {
  const SingBoxBackend();

  static const _unsupported = <CoreFeature, String>{
    CoreFeature.noise: 'Шумы недоступны в ядре sing-box и не применяются.',
    CoreFeature.mux: 'Mux Xray несовместим с ядром sing-box и не применяется.',
    CoreFeature.observatory: 'Observatory и управляемые JSON-конфиги Xray недоступны в ядре sing-box.',
    CoreFeature.rawConfig: 'Полный JSON-конфиг Xray недоступен в ядре sing-box.',
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
          // Подпись ML-DSA — лишнее расширение сертификата; основная проверка Reality та же.
          if (config.postQuantumKey?.isNotEmpty ?? false)
            'Reality: ядро sing-box не проверяет подпись ML-DSA (pqv) — сервер проверяется только по ключу Reality.',
        ],
      );

  @override
  HeartbeatProbe effectiveHeartbeatProbe(HeartbeatProbe requested) => requested;

  /// QUIC режет tun2socks, как у Go-ядра: Vision отвергает UDP/443.
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
            warning: 'Фрагментация в ядре sing-box — только TLS ClientHello; режим «$packets» не применяется.',
            fix: (v) => v.copyWith(fragment: v.fragment.copyWith(enabled: false)),
          ))
        .result;
  }
}
