import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/constants/app_constants.dart';
import 'package:teapodstream/core/constants/core_features.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/heartbeat_settings.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/models/xray_tuning.dart';
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

  test('heartbeat probe and tethering reach native in both cores', () async {
    Map<dynamic, dynamic>? sent;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getEngine') {
            return CoreFeatures.current.isRust ? 'rust' : 'go';
          }
          if (call.method == 'connect') sent = call.arguments as Map;
          return null;
        });
    const custom = 'https://probe.example/generate_204';
    for (final probe in HeartbeatProbe.values) {
      await XrayEngine().connect(
        config,
        VpnEngineOptions(
          socksPort: 10808,
          httpPort: 0,
          socksUser: '',
          socksPassword: '',
          allowTethering: true,
          heartbeat: HeartbeatSettings(
            probe: probe,
            failAction: HeartbeatFailAction.switchConfig,
            target: HeartbeatTarget.custom,
            customUrl: custom,
          ),
        ),
      );
      // Rust measures XRAYDELAY with probeOutboundUrl and checks flow owners
      // with TUN admission; PASSIVE uses its TUN counters.
      expect(sent!['heartbeatProbe'], probe.name);
      expect(sent!['allowTethering'], isTrue);
      // Rust's SOCKS probe supports HTTPS targets and switchConfig too.
      expect(sent!['heartbeatUrl'], custom);
      expect(sent!['heartbeatAction'], 'switchConfig');
    }
  });

  test('candidate measurement uses a temporary core of the selected engine', () async {
    final calls = <String>[];
    Map<dynamic, dynamic>? measured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'measureOutbound') {
            measured = call.arguments as Map;
            return 42;
          }
          return null;
        });
    const url = 'http://cp.cloudflare.com/generate_204';
    final latency = await XrayEngine().measureOutbound(config, options, url);
    expect(latency, 42);
    expect(calls, ['measureOutbound']);
    expect(measured!['url'], url);
    final json = jsonDecode(measured!['config'] as String) as Map;
    final inbounds = json['inbounds'] as List;
    expect(inbounds.any((dynamic i) => i['protocol'] == 'tun'), isFalse);
    if (CoreFeatures.current.isRust) {
      // xray-rust starts only with an inbound: an ephemeral loopback SOCKS that
      // cannot collide with the running VPN's SOCKS port.
      expect(inbounds.single['port'], 0);
      expect(inbounds.single['listen'], '127.0.0.1');
      expect((json['outbounds'] as List).map((dynamic o) => o['tag']), ['proxy']);
    }
  });

  test('a candidate the Rust builder refuses is not measured', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return 42;
        });
    // Mux is gated in Rust: the candidate could not connect with these settings.
    const muxOptions = VpnEngineOptions(
      socksPort: 10808,
      httpPort: 0,
      socksUser: '',
      socksPassword: '',
      mux: MuxSettings(enabled: true),
    );
    final latency = await XrayEngine().measureOutbound(
      config,
      muxOptions,
      'http://cp.cloudflare.com/generate_204',
    );
    expect(latency, CoreFeatures.current.isRust ? isNull : 42);
    expect(calls, CoreFeatures.current.isRust ? isEmpty : ['measureOutbound']);
  });

  test('switch candidates are limited to profiles the selected core runs', () {
    final vmess = VpnConfig(
      id: 'vmess',
      name: 'vmess',
      protocol: VpnProtocol.vmess,
      address: 'server.example',
      port: 443,
      uuid: '11111111-2222-4333-8444-555555555555',
      security: VpnSecurity.tls,
      // VMess over the legacy QUIC carrier: Go runs it, xray-rust has no QUIC
      // carrier and refuses the profile.
      transport: VpnTransport.quic,
      createdAt: DateTime(2026),
    );
    expect(XrayEngine().supportsConfig(config), isTrue);
    expect(XrayEngine().supportsConfig(vmess), !CoreFeatures.current.isRust);
  });

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
