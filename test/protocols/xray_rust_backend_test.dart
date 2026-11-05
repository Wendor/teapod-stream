import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/cores/core_backend.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/heartbeat_settings.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/models/xray_tuning.dart';
import 'package:teapodstream/protocols/xray/xray_rust_backend.dart';

VpnConfig _vless() => VpnConfig(
      id: 'v', name: 'v', protocol: VpnProtocol.vless, address: '1.2.3.4', port: 443,
      uuid: '11111111-2222-4333-8444-555555555555', security: VpnSecurity.tls,
      transport: VpnTransport.tcp, createdAt: DateTime(2026), encryption: 'none', sni: 's',
    );

VpnEngineOptions _opts({bool proxyOnly = false, int mtu = 1500, MuxSettings mux = const MuxSettings()}) =>
    VpnEngineOptions(
      socksPort: 10808, httpPort: 0, socksUser: 'u', socksPassword: 'p',
      proxyOnly: proxyOnly, mtu: mtu, mux: mux,
    );

Map<String, dynamic> _proxy(Map<String, dynamic> json) =>
    (json['outbounds'] as List).cast<Map<String, dynamic>>().firstWhere((o) => o['tag'] == 'proxy');

void main() {
  const CoreBackend rust = XrayRustBackend();

  test('SOCKS inbound requires the session credentials', () {
    final json = jsonDecode(rust.buildConfig(_vless(), _opts())) as Map<String, dynamic>;
    final socks = (json['inbounds'] as List).cast<Map<String, dynamic>>().firstWhere((i) => i['protocol'] == 'socks');
    expect(socks['settings']['auth'], 'password');
    expect(socks['settings']['accounts'], [
      {'user': 'u', 'pass': 'p'},
    ]);
  });

  test('proxy-only blocks the connection', () {
    expect(rust.checkOptions(_vless(), _opts(proxyOnly: true)).blocking, isNotNull);
  });

  test('custom MTU is a warning and the config still builds', () {
    final check = rust.checkOptions(_vless(), _opts(mtu: 1400));
    expect(check.blocking, isNull);
    expect(check.warnings, isNotEmpty);
    expect(() => rust.buildConfig(_vless(), _opts(mtu: 1400)), returnsNormally);
  });

  test('Mux is a warning, ignored in the config', () {
    final opts = _opts(mux: const MuxSettings(enabled: true));
    expect(rust.checkOptions(_vless(), opts).warnings, isNotEmpty);
    final json = jsonDecode(rust.buildConfig(_vless(), opts)) as Map<String, dynamic>;
    expect(_proxy(json).containsKey('mux'), isFalse);
  });

  test('raw JSON profiles are disabled with a reason, without throwing', () {
    final raw = VpnConfig.fromJson({..._vless().toJson(), 'rawXrayConfig': '{"outbounds":[]}'});
    expect(rust.checkConfig(raw), isNotNull);
    expect(rust.checkConfig(_vless()), isNull);
  });

  test('unsupported features have reasons, supported do not', () {
    for (final f in [CoreFeature.proxyOnly, CoreFeature.mux, CoreFeature.customMtu, CoreFeature.rawConfig]) {
      expect(rust.supports(f), isFalse, reason: f.name);
      expect(rust.unavailableReason(f), isNotNull);
    }
    expect(rust.supports(CoreFeature.socksAuthentication), isTrue);
    expect(rust.unavailableReason(CoreFeature.geosite), isNull);
  });

  test('QUIC is blocked for -udp443 Vision only, or on request', () {
    const r = XrayRustBackend();
    expect(r.effectiveQuicBlock(requested: false, flow: 'xtls-rprx-vision'), isFalse);
    expect(r.effectiveQuicBlock(requested: false, flow: 'xtls-rprx-vision-udp443'), isTrue);
    expect(r.effectiveQuicBlock(requested: true, flow: null), isTrue);
    expect(rust.effectiveHeartbeatProbe(HeartbeatProbe.passive), HeartbeatProbe.passive);
  });
}
