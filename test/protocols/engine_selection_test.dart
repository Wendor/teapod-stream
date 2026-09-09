import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/constants/app_constants.dart';
import 'package:teapodstream/core/constants/core_features.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/protocols/xray/xray_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(AppConstants.methodChannel);
  const options = VpnEngineOptions(
    socksPort: 10808,
    httpPort: 0,
    socksUser: 'user',
    socksPassword: 'pass',
  );
  final config = VpnConfig(
    id: 'test',
    name: 'test',
    protocol: VpnProtocol.vless,
    address: 'server.example',
    port: 443,
    uuid: '11111111-2222-4333-8444-555555555555',
    security: VpnSecurity.reality,
    transport: VpnTransport.xhttp,
    fingerprint: 'firefox',
    publicKey: base64Url.encode(List.filled(32, 7)).replaceAll('=', ''),
    shortId: '1234',
    sni: 'cover.example',
    encryption: 'none',
    createdAt: DateTime(2026),
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test(
    'the selected native core receives its compatible config and credentials',
    () async {
      Map<dynamic, dynamic>? sent;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getEngine') {
              return CoreFeatures.current.isRust ? 'rust' : 'go';
            }
            if (call.method == 'connect') sent = call.arguments as Map;
            return null;
          });
      await XrayEngine().connect(config, options);
      final json = jsonDecode(sent!['xrayConfig'] as String) as Map;
      final inbounds = json['inbounds'] as List;
      expect(
        inbounds.any((dynamic i) => i['protocol'] == 'tun'),
        CoreFeatures.current.isRust,
      );
      expect(sent!['socksUser'], CoreFeatures.current.isRust ? '' : 'user');
      expect(sent!['socksPassword'], CoreFeatures.current.isRust ? '' : 'pass');
    },
  );

  test('a mismatched native core never receives a connect command', () async {
    var connected = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getEngine') {
            return CoreFeatures.current.isRust ? 'go' : 'rust';
          }
          if (call.method == 'connect') connected = true;
          return null;
        });
    await expectLater(
      XrayEngine().connect(config, options),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'ENGINE_MISMATCH',
        ),
      ),
    );
    expect(connected, isFalse);
  });
}
