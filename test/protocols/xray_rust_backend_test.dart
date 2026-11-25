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

  test('geosite over xray-rust limits comes trimmed, ad blocking goes first over the budget', () {
    // Real sizes: Loyalsoldier's category-ads-all is over 200k domains, runetfreedom's ru-blocked-all over
    // 32 MB; the copy xray-rust reads has their first 200k.
    const geosite = GeositeIndex({
      'category-ads-all': (domains: 203624, rustDomains: 200000),
      'win-spy': (domains: 327, rustDomains: 327),
      'ru-blocked-all': (domains: 1644170, rustDomains: 200000),
      'ru-blocked': (domains: 73607, rustDomains: 73607),
      'cn': (domains: 110258, rustDomains: 110258),
      'china-list': (domains: 109486, rustDomains: 109486),
    }, rustFile: GeositeIndex.rustFileName);
    VpnEngineOptions with_(RoutingSettings routing) =>
        VpnEngineOptions(socksPort: 1, socksUser: 'u', socksPassword: 'p', routing: routing, geosite: geosite);
    String rules(VpnEngineOptions o) => rust.buildConfig(_vless(), o);
    const blocked = RoutingSettings(
      direction: RoutingDirection.bypass,
      geositeEnabled: true,
      geositeCodes: ['ru-blocked-all'],
    );

    final trimmed = rust.checkOptions(_vless(), with_(blocked));
    expect(trimmed.blocking, isNull);
    expect(trimmed.warnings.single, allOf(contains('ru-blocked-all'), contains('first domains')));
    expect(rules(with_(blocked)), contains('ext:geosite-rust.dat:ru-blocked-all'));

    // 200k + 200k ads is over the 250k budget: ad blocking is dropped.
    final ads = rust.checkOptions(_vless(), with_(blocked.copyWith(adBlockEnabled: true)));
    expect(ads.blocking, isNull);
    // category-ads-all isn't used then, so it isn't reported as trimmed.
    expect(ads.warnings, [contains('ad blocking is not applied'), isNot(contains('category-ads-all'))]);
    // A code both in the rule and in ad blocking is reported once.
    const small = GeositeIndex({
      'category-ads-all': (domains: 203624, rustDomains: 100000),
      'win-spy': (domains: 327, rustDomains: 327),
    }, rustFile: GeositeIndex.rustFileName);
    final both = rust.checkOptions(
      _vless(),
      VpnEngineOptions(
        socksPort: 1,
        socksUser: 'u',
        socksPassword: 'p',
        routing: blocked.copyWith(geositeCodes: ['category-ads-all'], adBlockEnabled: true),
        geosite: small,
      ),
    );
    expect(both.warnings.single, startsWith('GeoSite category-ads-all:'));

    // Ad blocking alone fits, trimmed; the user's codes alone over the budget block the start.
    const adsOnly = RoutingSettings(adBlockEnabled: true);
    expect(rust.checkOptions(_vless(), with_(adsOnly)).warnings.single, contains('category-ads-all'));
    expect(rules(with_(adsOnly)), allOf(contains('category-ads-all'), contains('win-spy')));
    final tooMany = blocked.copyWith(geositeCodes: ['cn', 'china-list', 'ru-blocked']);
    expect(rust.checkOptions(_vless(), with_(tooMany)).blocking, contains('250k'));
    expect(rust.checkOptions(_vless(), with_(blocked.copyWith(geositeCodes: ['cn', 'china-list']))).blocking, isNull);
  });
}
