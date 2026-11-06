import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/models/xray_tuning.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/protocols/singbox/singbox_config_builder.dart';
import 'package:teapodstream/protocols/singbox/singbox_outbound.dart';

VpnConfig _cfg(
  VpnProtocol protocol, {
  VpnSecurity security = VpnSecurity.tls,
  VpnTransport transport = VpnTransport.tcp,
  String? sni = 'sni.example.com',
  String? flow,
  String? encryption,
  String? password,
  String? method,
  String? wsPath,
  String? wsHost,
  String? grpcServiceName,
  String? fingerprint,
  String? publicKey,
  String? shortId,
  String? postQuantumKey,
  String? obfsPassword,
  String? hopPorts,
  bool allowInsecure = false,
  String? pinSHA256,
  String? alpn,
  String? ech,
  String? rawUri,
  String? rawXrayConfig,
  Map<String, dynamic>? finalmask,
}) =>
    VpnConfig(
      id: 'id', name: 'n', protocol: protocol, address: 'srv.example.com', port: 443,
      uuid: '11111111-2222-4333-8444-555555555555', security: security, transport: transport,
      createdAt: DateTime(2026), sni: sni, flow: flow, encryption: encryption, password: password,
      method: method, wsPath: wsPath, wsHost: wsHost, grpcServiceName: grpcServiceName,
      fingerprint: fingerprint, publicKey: publicKey, shortId: shortId, postQuantumKey: postQuantumKey,
      obfsPassword: obfsPassword, hopPorts: hopPorts, allowInsecure: allowInsecure, pinSHA256: pinSHA256,
      alpn: alpn, ech: ech, rawUri: rawUri, rawXrayConfig: rawXrayConfig, finalmask: finalmask,
    );

const _opts = VpnEngineOptions(socksPort: 10808, httpPort: 0, socksUser: 'u', socksPassword: 'p');

Map<String, dynamic> _tls(Map<String, dynamic> out) => out['tls'] as Map<String, dynamic>;

void main() {
  group('outbounds', () {
    test('VLESS Reality + Vision', () {
      final out = SingBoxOutbound.build(
        _cfg(VpnProtocol.vless, security: VpnSecurity.reality, flow: 'xtls-rprx-vision', encryption: 'none',
            publicKey: 'PK', shortId: 'ab'),
        _opts,
      );
      expect(out, containsPair('type', 'vless'));
      expect(out, containsPair('tag', 'proxy'));
      expect(out, containsPair('server', 'srv.example.com'));
      expect(out, containsPair('server_port', 443));
      expect(out, containsPair('uuid', '11111111-2222-4333-8444-555555555555'));
      expect(out, containsPair('flow', 'xtls-rprx-vision'));
      expect(out, containsPair('packet_encoding', 'xudp'));
      final tls = _tls(out);
      expect(tls['enabled'], isTrue);
      expect(tls['server_name'], 'sni.example.com');
      expect(tls['utls'], {'enabled': true, 'fingerprint': 'chrome'});
      expect(tls['reality'], {'enabled': true, 'public_key': 'PK', 'short_id': 'ab'});
      expect(SingBoxOutbound.isEndpoint(_cfg(VpnProtocol.vless)), isFalse);
    });

    test('fingerprint: global override, then profile, then chrome', () {
      final cfg = _cfg(VpnProtocol.vless, fingerprint: 'firefox');
      expect(_tls(SingBoxOutbound.build(cfg, _opts))['utls'], {'enabled': true, 'fingerprint': 'firefox'});
      const safari = VpnEngineOptions(socksPort: 1, httpPort: 0, socksUser: '', socksPassword: '',
          tlsFingerprint: TlsFingerprint.safari);
      expect(_tls(SingBoxOutbound.build(cfg, safari))['utls'], {'enabled': true, 'fingerprint': 'safari'});
    });

    test('VMess WS with early data in path', () {
      final out = SingBoxOutbound.build(
        _cfg(VpnProtocol.vmess, transport: VpnTransport.ws, wsPath: '/p?ed=2048', wsHost: 'h.example.com'),
        _opts,
      );
      expect(out['type'], 'vmess');
      expect(out['security'], 'auto');
      expect(out['alter_id'], 0);
      expect(out['transport'], {
        'type': 'ws',
        'path': '/p',
        'headers': {'Host': 'h.example.com'},
        'max_early_data': 2048,
        'early_data_header_name': 'Sec-WebSocket-Protocol',
      });
    });

    test('Trojan transports: gRPC, HTTP/2, HTTPUpgrade', () {
      Map<String, dynamic> transport(VpnTransport t) => SingBoxOutbound.build(
            _cfg(VpnProtocol.trojan, transport: t, password: 'pw', wsPath: '/x', wsHost: 'h', grpcServiceName: 'svc'),
            _opts,
          )['transport'] as Map<String, dynamic>;
      expect(transport(VpnTransport.grpc), {'type': 'grpc', 'service_name': 'svc'});
      expect(transport(VpnTransport.http2), {'type': 'http', 'host': ['h'], 'path': '/x'});
      expect(transport(VpnTransport.httpupgrade), {'type': 'httpupgrade', 'host': 'h', 'path': '/x'});
      final out = SingBoxOutbound.build(_cfg(VpnProtocol.trojan, password: 'pw'), _opts);
      expect(out['password'], 'pw');
      expect(out.containsKey('transport'), isFalse);
    });

    test('Shadowsocks 2022', () {
      final out = SingBoxOutbound.build(
        _cfg(VpnProtocol.shadowsocks, security: VpnSecurity.none, method: '2022-blake3-aes-128-gcm', password: 'k'),
        _opts,
      );
      expect(out, {
        'type': 'shadowsocks', 'tag': 'proxy', 'server': 'srv.example.com', 'server_port': 443,
        'method': '2022-blake3-aes-128-gcm', 'password': 'k',
      });
    });

    test('Hysteria2 with salamander and port hopping', () {
      final out = SingBoxOutbound.build(
        _cfg(VpnProtocol.hysteria2, password: 'pw', obfsPassword: 'ob', hopPorts: '20000-30000,443'),
        _opts,
      );
      expect(out['type'], 'hysteria2');
      expect(out['password'], 'pw');
      expect(out['server_ports'], ['20000:30000', '443:443']);
      expect(out.containsKey('server_port'), isFalse);
      expect(out['obfs'], {'type': 'salamander', 'password': 'ob'});
      expect(_tls(out)['enabled'], isTrue);
    });

    test('Hysteria2 never gets uTLS (QUIC needs the standard TLS stack)', () {
      const safari = VpnEngineOptions(socksPort: 1, httpPort: 0, socksUser: '', socksPassword: '',
          tlsFingerprint: TlsFingerprint.safari);
      final tls = _tls(SingBoxOutbound.build(_cfg(VpnProtocol.hysteria2, password: 'pw', fingerprint: 'chrome'), safari));
      expect(tls.containsKey('utls'), isFalse);
    });

    test('ECH from DNS (xray domain+server form) queries the HTTPS record', () {
      Map<String, dynamic> ech(String v) => _tls(SingBoxOutbound.build(_cfg(VpnProtocol.vless, ech: v), _opts))['ech']
          as Map<String, dynamic>;
      expect(ech('cloudflare-ech.com+https://1.1.1.1/dns-query'), {'enabled': true, 'query_server_name': 'cloudflare-ech.com'});
      expect(ech('https://1.1.1.1/dns-query'), {'enabled': true});
    });

    test('TLS options: insecure, ALPN, ECH, ClientHello fragmentation', () {
      const fragment = VpnEngineOptions(socksPort: 1, httpPort: 0, socksUser: '', socksPassword: '',
          fragment: FragmentSettings(enabled: true));
      final tls = _tls(SingBoxOutbound.build(
        _cfg(VpnProtocol.vless, allowInsecure: true, alpn: 'h2, http/1.1', ech: 'RUNI'),
        fragment,
      ));
      expect(tls['insecure'], isTrue);
      expect(tls['alpn'], ['h2', 'http/1.1']);
      expect(tls['ech'], {
        'enabled': true,
        'config': ['-----BEGIN ECH CONFIGS-----', 'RUNI', '-----END ECH CONFIGS-----'],
      });
      expect(tls['fragment'], isTrue);
      expect(_tls(SingBoxOutbound.build(_cfg(VpnProtocol.vless), _opts)).containsKey('fragment'), isFalse);
    });
  });

  group('unsupportedReason', () {
    String? reason(VpnConfig c) => SingBoxConfigBuilder.unsupportedReason(c);

    test('supported profile', () {
      expect(reason(_cfg(VpnProtocol.vless, flow: 'xtls-rprx-vision', encryption: 'none')), isNull);
    });

    test('Xray-only features', () {
      expect(reason(_cfg(VpnProtocol.vless, transport: VpnTransport.xhttp)), 'Транспорт XHTTP недоступен в ядре sing-box.');
      expect(reason(_cfg(VpnProtocol.vless, transport: VpnTransport.splithttp)), 'Транспорт XHTTP недоступен в ядре sing-box.');
      expect(reason(_cfg(VpnProtocol.vless, rawUri: 'vless://u@h:1?type=tcp&headerType=http#n')),
          'TCP с HTTP-обфускацией недоступен в ядре sing-box.');
      expect(reason(_cfg(VpnProtocol.vless, encryption: 'mlkem768x25519plus.native.0rtt.x')),
          'VLESS Encryption недоступен в ядре sing-box.');
      expect(reason(_cfg(VpnProtocol.vless, flow: 'xtls-rprx-vision-udp443')),
          'Flow «xtls-rprx-vision-udp443» недоступен в ядре sing-box.');
      expect(reason(_cfg(VpnProtocol.vless, rawXrayConfig: '{}')), 'Полный JSON-конфиг Xray недоступен в ядре sing-box.');
      expect(reason(_cfg(VpnProtocol.vless, finalmask: {'udp': []})),
          'Расширенные настройки Xray (finalmask/extra) недоступны в ядре sing-box.');
    });

    test('Shadowsocks plugin and method', () {
      expect(reason(_cfg(VpnProtocol.shadowsocks, method: 'aes-128-gcm', rawUri: 'ss://x@h:1?plugin=obfs-local#n')),
          'Плагины Shadowsocks недоступны в ядре sing-box.');
      expect(reason(_cfg(VpnProtocol.shadowsocks, method: 'rc4')), 'Метод Shadowsocks «rc4» недоступен в ядре sing-box.');
    });

    test('certificate pin is never dropped silently', () {
      expect(reason(_cfg(VpnProtocol.vless, pinSHA256: 'abcd')),
          'Pin сертификата не поддерживается ядром sing-box: оно проверяет только хеш открытого ключа.');
    });
  });
}
