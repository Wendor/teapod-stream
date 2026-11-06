import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/cores/core_switch.dart';
import 'package:teapodstream/core/models/protocol_settings.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/protocols/xray/rust_config_builder.dart';
import 'package:teapodstream/protocols/xray/xray_config_builder.dart';
import 'package:teapodstream/protocols/xray/xray_go_backend.dart';

VpnConfig _cfg(VpnProtocol protocol, [ProtocolSettings? settings]) => VpnConfig(
      id: protocol.name, name: protocol.name, protocol: protocol, address: 'srv.example.com', port: 51820,
      uuid: '', security: VpnSecurity.none, transport: VpnTransport.tcp, createdAt: DateTime(2026),
      protocolSettings: settings,
    );

const _wg = WireGuardSettings(
  privateKey: 'priv', addresses: ['10.0.0.2/32', 'fd00::2/128'], peerPublicKey: 'pub', presharedKey: 'psk',
  mtu: 1280, reserved: [1, 2, 3], allowedIps: ['0.0.0.0/0'], keepalive: 25,
  amnezia: AmneziaParams(jc: 4, jmin: 40, jmax: 70, s1: 16, s4: 16, h1: '100-200', i1: '<r 16>',
      headerProtectionKey: 'hpk', contentPaddingAddition: '0-32', rekeyAfterTime: '120',
      rekeyTimeout: '5', rejectAfterTime: '180', keepaliveTimeout: '10', maxHandshakeAttempts: '20'),
);
const _ssh = SshSettings(user: 'root', password: 'pw', privateKey: 'PEM', privateKeyPassphrase: 'pp',
    hostKeys: ['ssh-ed25519 AAAA']);
const _naive = NaiveSettings(user: 'u', password: 'p', quic: true, extraHeaders: {'X-A': '1'});

void main() {
  test('settings survive VpnConfig JSON round-trip', () {
    for (final (protocol, settings) in [
      (VpnProtocol.wireguard, _wg as ProtocolSettings),
      (VpnProtocol.ssh, _ssh),
      (VpnProtocol.naive, _naive),
    ]) {
      final back = VpnConfig.fromJsonString(_cfg(protocol, settings).toJsonString());
      expect(back.protocol, protocol);
      expect(back.protocolSettings?.toJson(), settings.toJson(), reason: protocol.name);
    }
    final wg = VpnConfig.fromJsonString(_cfg(VpnProtocol.wireguard, _wg).toJsonString()).protocolSettings;
    expect(wg, isA<WireGuardSettings>());
    expect((wg as WireGuardSettings).amnezia?.jc, 4);
    expect(wg.addresses, ['10.0.0.2/32', 'fd00::2/128']);
  });

  test('copyWith keeps protocol settings', () {
    expect(_cfg(VpnProtocol.ssh, _ssh).copyWith(name: 'x').protocolSettings, same(_ssh));
  });

  test('old JSON without protocolSettings reads as before', () {
    final json = _cfg(VpnProtocol.vless).toJson()..remove('protocolSettings');
    expect(VpnConfig.fromJson(json).protocolSettings, isNull);
    expect(ProtocolSettings.fromJson(null), isNull);
  });

  test('new protocols require their settings', () {
    expect(_cfg(VpnProtocol.wireguard).validate(), 'Нет параметров протокола WireGuard');
    expect(_cfg(VpnProtocol.wireguard, _wg).validate(), isNull);
    expect(_cfg(VpnProtocol.naive, _ssh).validate(), 'Нет параметров протокола NaiveProxy');
  });

  test('Xray cores reject sing-box-only protocols', () {
    for (final (protocol, settings, name) in [
      (VpnProtocol.wireguard, _wg as ProtocolSettings, 'WireGuard'),
      (VpnProtocol.ssh, _ssh, 'SSH'),
      (VpnProtocol.naive, _naive, 'NaiveProxy'),
    ]) {
      final reason = 'Протокол $name поддерживается только ядром sing-box.';
      expect(XrayConfigBuilder.unsupportedReason(_cfg(protocol, settings)), reason);
      expect(RustConfigBuilder.unsupportedReason(_cfg(protocol, settings)), reason);
    }
    final vless = _cfg(VpnProtocol.vless).copyWith(name: 'v');
    expect(supportedCandidates([vless, _cfg(VpnProtocol.wireguard, _wg)], const XrayGoBackend()), [vless]);
  });
}
