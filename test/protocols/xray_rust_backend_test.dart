import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/cores/core_backend.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/heartbeat_settings.dart';
import 'package:teapodstream/core/models/routing_settings.dart';
import 'package:teapodstream/core/services/geosite_index.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/models/xray_tuning.dart';
import 'package:teapodstream/protocols/xray/xray_rust_backend.dart';

VpnConfig _vless() => VpnConfig(
  id: 'v',
  name: 'v',
  protocol: VpnProtocol.vless,
  address: '1.2.3.4',
  port: 443,
  uuid: '11111111-2222-4333-8444-555555555555',
  security: VpnSecurity.tls,
  transport: VpnTransport.tcp,
  createdAt: DateTime(2026),
  encryption: 'none',
  sni: 's',
);

VpnEngineOptions _opts({bool proxyOnly = false, int mtu = 1500, MuxSettings mux = const MuxSettings()}) =>
    VpnEngineOptions(socksPort: 10808, socksUser: 'u', socksPassword: 'p', proxyOnly: proxyOnly, mtu: mtu, mux: mux);

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

  test('geosite over xray-rust limits is left out, ad blocking goes first over the budget', () {
    // Loyalsoldier's category-ads-all is over 200k domains; runetfreedom's ru-blocked-all is over 32 MB.
    const geosite = GeositeIndex({
      'category-ads-all': (bytes: 5290196, domains: 203624),
      'win-spy': (bytes: 10482, domains: 327),
      'ru-blocked-all': (bytes: 39659498, domains: 1644170),
      'ru-blocked': (bytes: 1525392, domains: 73607),
      'cn': (bytes: 1948703, domains: 110258),
      'china-list': (bytes: 1931563, domains: 109486),
    });
    VpnEngineOptions with_(RoutingSettings routing) =>
        VpnEngineOptions(socksPort: 1, socksUser: 'u', socksPassword: 'p', routing: routing, geosite: geosite);
    String rules(VpnEngineOptions o) => rust.buildConfig(_vless(), o);

    final oversized = with_(
      const RoutingSettings(
        direction: RoutingDirection.bypass,
        geositeEnabled: true,
        geositeCodes: ['ru-blocked-all', 'ru-blocked'],
        adBlockEnabled: true,
      ),
    );
    final check = rust.checkOptions(_vless(), oversized);
    expect(check.blocking, isNull);
    expect(check.warnings.single, allOf(contains('ru-blocked-all'), contains('category-ads-all')));
    final json = rules(oversized);
    expect(json, allOf(contains('geosite:ru-blocked"'), contains('geosite:win-spy')));
    expect(json, isNot(anyOf(contains('ru-blocked-all'), contains('category-ads-all'))));

    // Over xray-rust's 250k budget: ad blocking is dropped first; codes alone over it block the start.
    const cn = RoutingSettings(direction: RoutingDirection.bypass, geositeEnabled: true, geositeCodes: ['cn']);
    const fitting = GeositeIndex({
      'category-ads-all': (bytes: 4888150, domains: 187598),
      'win-spy': (bytes: 10482, domains: 327),
      'cn': (bytes: 1948703, domains: 110258),
      'china-list': (bytes: 1931563, domains: 109486),
      'ru-blocked': (bytes: 1525392, domains: 73607),
    });
    VpnEngineOptions fit(RoutingSettings routing) =>
        VpnEngineOptions(socksPort: 1, socksUser: 'u', socksPassword: 'p', routing: routing, geosite: fitting);
    final adsAndCn = rust.checkOptions(_vless(), fit(cn.copyWith(adBlockEnabled: true)));
    expect(adsAndCn.blocking, isNull);
    expect(adsAndCn.warnings.single, contains('ad blocking is not applied'));
    expect(rules(fit(cn.copyWith(adBlockEnabled: true))), isNot(contains('category-ads-all')));
    expect(rust.checkOptions(_vless(), fit(cn)).warnings, isEmpty);
    final tooMany = cn.copyWith(geositeCodes: ['cn', 'china-list', 'ru-blocked']);
    expect(rust.checkOptions(_vless(), fit(tooMany)).blocking, contains('250k'));
  });
}
