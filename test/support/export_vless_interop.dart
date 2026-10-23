// Used by scripts/test-rust-transports.py for VLESS, Trojan, VMess,
// Shadowsocks 2022 and Hysteria2 cases, with the VPN config and its
// switchConfig probe variant; all keys and certificates are ephemeral.
// A case may carry app settings (`options`: fragment, noise, blockQuic,
// enableUdp) and, for VMess links, which have no pin field, the test
// certificate's `pin`.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/constants/core_features.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/xray_tuning.dart';
import 'package:teapodstream/protocols/xray/rust_config_builder.dart';
import 'package:teapodstream/protocols/xray/vless_parser.dart';

VpnEngineOptions _options(Map<String, dynamic> o, String? flow) {
  final fragment = o['fragment'] as Map<String, dynamic>?;
  final noise = o['noise'] as Map<String, dynamic>?;
  return VpnEngineOptions(
    socksPort: 10808,
    httpPort: 0,
    socksUser: '',
    socksPassword: '',
    enableUdp: o['enableUdp'] as bool? ?? true,
    blockQuic: CoreFeatures.rust.effectiveQuicBlock(
      requested: o['blockQuic'] as bool? ?? false,
      flow: flow,
    ),
    fragment: fragment == null
        ? const FragmentSettings()
        : FragmentSettings(
            enabled: true,
            packets: fragment['packets'] as String,
            length: fragment['length'] as String,
            interval: fragment['interval'] as String,
          ),
    noise: noise == null
        ? const NoiseSettings()
        : NoiseSettings(
            enabled: true,
            type: NoiseType.values.byName(noise['type'] as String),
            packet: noise['packet'] as String,
            delay: noise['delay'] as String,
          ),
  );
}

void main() {
  test('export production-generated configs for native interop', () {
    final file = File(Platform.environment['TEAPOD_INTEROP_INPUT']!);
    final input = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    for (final entry in input['cases'] as List) {
      final name = entry['name'] as String;
      var profile = VlessParser.parseUri(entry.remove('url') as String)!;
      final pin = entry.remove('pin') as String?;
      if (pin != null) profile = profile.copyWith(pinSHA256: pin);
      final options = _options(
        (entry.remove('options') as Map<String, dynamic>?) ?? const {},
        profile.flow,
      );
      final config = RustConfigBuilder.build(profile, options);
      // A setting the builder skipped would make the device case vacuous.
      final proxy = (config['outbounds'] as List).singleWhere(
        (dynamic o) => o['tag'] == 'proxy',
      );
      final mask = proxy['streamSettings']['finalmask'] as Map?;
      if (options.fragment.enabled) {
        expect(mask?['tcp'], [containsPair('type', 'fragment')], reason: name);
      }
      if (options.noise.enabled) {
        expect(mask?['udp'], contains(containsPair('type', 'noise')), reason: name);
      }
      final block = (config['routing']['rules'] as List).where(
        (dynamic r) => r['outboundTag'] == 'block',
      );
      expect(block, hasLength(options.blockQuic || !options.enableUdp ? 1 : 0),
          reason: name);
      entry['config'] = jsonEncode(config);
      // The switchConfig candidate variant (temporary core, no TUN).
      entry['probe'] = RustConfigBuilder.buildProbeJson(profile, options);
    }
    File(
      Platform.environment['TEAPOD_INTEROP_OUTPUT']!,
    ).writeAsStringSync(jsonEncode(input));
  });
}
