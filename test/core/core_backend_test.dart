import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/cores/core_backend.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/connection_fingerprint.dart';
import 'package:teapodstream/core/models/core_kind.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/protocols/xray/xray_config_builder.dart';
import 'package:teapodstream/protocols/xray/xray_go_backend.dart';

VpnConfig _vless() => VpnConfig(
      id: 'v', name: 'v', protocol: VpnProtocol.vless, address: '1.2.3.4', port: 443,
      uuid: '11111111-2222-4333-8444-555555555555', security: VpnSecurity.tls,
      transport: VpnTransport.tcp, createdAt: DateTime(2026),
    );

const _opts = VpnEngineOptions(socksPort: 10808, httpPort: 0, socksUser: 'u', socksPassword: 'p');

void main() {
  test('core order: defaults, json round trip, legacy single core goes first', () {
    expect(AppSettings.fromJson(const {}).coreOrder, CoreKind.defaultOrder);
    final s = const AppSettings().copyWith(
        coreOrder: [CoreKind.xrayRust, CoreKind.singBox, CoreKind.xrayGo], disabledCores: {CoreKind.xrayGo});
    final back = AppSettings.fromJson(s.toJson());
    expect(back.coreOrder, s.coreOrder);
    expect(back.disabledCores, {CoreKind.xrayGo});
    expect(AppSettings.fromJson(const {'core': 'singBox'}).coreOrder,
        [CoreKind.singBox, CoreKind.xrayGo, CoreKind.xrayRust]);
    expect(CoreKind.xrayGo.nativeId, 'go');
    expect(CoreKind.xrayRust.nativeId, 'rust');
  });

  test('parseOrder drops unknown names and appends missing cores', () {
    expect(CoreKind.parseOrder(['xrayRust', 'nope']), [CoreKind.xrayRust, CoreKind.xrayGo, CoreKind.singBox]);
    expect(CoreKind.parseOrder(['singBox'], first: 'xrayRust').first, CoreKind.singBox);
  });

  test('the running core is part of the connection fingerprint', () {
    const s = AppSettings();
    expect(connectionFingerprint(s, core: CoreKind.xrayGo),
        isNot(connectionFingerprint(s, core: CoreKind.xrayRust)));
  });

  group('XrayGoBackend', () {
    const CoreBackend go = XrayGoBackend();
    test('supports everything', () {
      for (final f in CoreFeature.values) {
        expect(go.supports(f), isTrue, reason: f.name);
        expect(go.unavailableReason(f), isNull);
      }
      expect(go.checkConfig(_vless()), isNull);
      final check = go.checkOptions(_vless(), _opts);
      expect(check.blocking, isNull);
      expect(check.warnings, isEmpty);
    });
    test('builds the same config as XrayConfigBuilder', () {
      expect(go.buildConfig(_vless(), _opts), XrayConfigBuilder.buildJson(_vless(), _opts));
    });
    test('uses mergeWithRaw for raw configs', () {
      final raw = _vless().copyWith(rawUri: 'x');
      final managed = VpnConfig.fromJson({...raw.toJson(), 'rawXrayConfig': '{"outbounds":[{"tag":"proxy","protocol":"freedom"}]}'});
      expect(go.buildConfig(managed, _opts), XrayConfigBuilder.mergeWithRaw(managed.rawXrayConfig!, _opts));
    });
  });
}
