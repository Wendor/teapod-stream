import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/cores/core_switch.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/protocols/xray/xray_rust_backend.dart';

VpnConfig _cfg(String id, {String? raw}) => VpnConfig.fromJson({
      ...VpnConfig(
        id: id, name: id, protocol: VpnProtocol.vless, address: '1.2.3.4', port: 443,
        uuid: '11111111-2222-4333-8444-555555555555', security: VpnSecurity.tls,
        transport: VpnTransport.tcp, createdAt: DateTime(2026), encryption: 'none', sni: 's',
      ).toJson(),
      'rawXrayConfig': raw,
    });

void main() {
  group('coreSwitchAction', () {
    test('connected on an unsupported profile disconnects', () {
      expect(coreSwitchAction(state: VpnState.connected, unsupported: 'нет'), CoreSwitchAction.disconnect);
      expect(coreSwitchAction(state: VpnState.blocked, unsupported: 'нет'), CoreSwitchAction.disconnect);
    });
    test('connected on a supported profile only waits for reconnect', () {
      expect(coreSwitchAction(state: VpnState.connected, unsupported: null), CoreSwitchAction.none);
    });
    test('disconnected rewrites or clears the quick-connect config', () {
      expect(coreSwitchAction(state: VpnState.disconnected, unsupported: null), CoreSwitchAction.saveQuickConnect);
      expect(coreSwitchAction(state: VpnState.error, unsupported: 'нет'), CoreSwitchAction.clearQuickConnect);
    });
    test('transitions are left alone', () {
      expect(coreSwitchAction(state: VpnState.disconnecting, unsupported: null), CoreSwitchAction.none);
    });
  });

  test('switch candidates drop profiles the core cannot run', () {
    final ok = _cfg('ok');
    final raw = _cfg('raw', raw: '{"outbounds":[]}');
    expect(supportedCandidates([ok, raw], const XrayRustBackend()), [ok]);
    expect(supportedCandidates([raw], const XrayRustBackend()), isEmpty);
  });
}
