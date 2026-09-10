// Used by scripts/test-rust-transports.py; all keys and certificates are ephemeral.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/constants/core_features.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/protocols/xray/rust_config_builder.dart';
import 'package:teapodstream/protocols/xray/vless_parser.dart';

void main() {
  test('export production-generated VLESS configs for native interop', () {
    final file = File(Platform.environment['TEAPOD_INTEROP_INPUT']!);
    final input = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    for (final entry in input['cases'] as List) {
      final profile = VlessParser.parseUri(entry.remove('url') as String)!;
      final options = VpnEngineOptions(
        socksPort: 10808,
        httpPort: 0,
        socksUser: '',
        socksPassword: '',
        blockQuic: CoreFeatures.rust.effectiveQuicBlock(
          requested: false,
          usesVision: profile.flow?.contains('vision') ?? false,
        ),
      );
      entry['config'] = RustConfigBuilder.buildJson(profile, options);
    }
    File(
      Platform.environment['TEAPOD_INTEROP_OUTPUT']!,
    ).writeAsStringSync(jsonEncode(input));
  });
}
