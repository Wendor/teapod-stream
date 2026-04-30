import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/protocols/xray/vless_parser.dart';
import 'package:teapodstream/core/models/vpn_config.dart';

void main() {
  group('VlessParser.parseUri', () {
    group('VLESS', () {
      test('valid URI parses correctly', () {
        const uri =
            'vless://550e8400-e29b-41d4-a716-446655440000@example.com:443'
            '?security=reality&type=tcp&pbk=abc123&sid=abc&sni=example.com#My Server';
        final config = VlessParser.parseUri(uri);
        expect(config, isNotNull);
        expect(config!.protocol, VpnProtocol.vless);
        expect(config.uuid, '550e8400-e29b-41d4-a716-446655440000');
        expect(config.address, 'example.com');
        expect(config.port, 443);
        expect(config.name, 'My Server');
        expect(config.security, VpnSecurity.reality);
      });

      test('missing @ returns null', () {
        const uri = 'vless://uuid-without-at-sign:443?security=none';
        expect(VlessParser.parseUri(uri), isNull);
      });

      test('defaults port to 443 when not specified', () {
        const uri = 'vless://uuid@host?security=none';
        final config = VlessParser.parseUri(uri);
        expect(config?.port, 443);
      });

      test('percent-encoded name is decoded', () {
        const uri = 'vless://uuid@host:443#My%20Server';
        final config = VlessParser.parseUri(uri);
        expect(config?.name, 'My Server');
      });
    });

    group('VMess', () {
      String makeVmessUri(Map<String, dynamic> json) {
        final encoded = base64Encode(utf8.encode(jsonEncode(json)));
        return 'vmess://$encoded';
      }

      test('valid JSON parses correctly', () {
        final uri = makeVmessUri({
          'ps': 'VMess Test', 'add': '1.2.3.4', 'port': '8388',
          'id': 'test-uuid', 'aid': '0', 'net': 'tcp', 'tls': '',
        });
        final config = VlessParser.parseUri(uri);
        expect(config, isNotNull);
        expect(config!.protocol, VpnProtocol.vmess);
        expect(config.address, '1.2.3.4');
        expect(config.port, 8388);
        expect(config.name, 'VMess Test');
      });

      test('port as string is converted to int', () {
        final uri = makeVmessUri({
          'add': 'host', 'port': '9090', 'id': 'uid', 'net': 'tcp', 'tls': '',
        });
        expect(VlessParser.parseUri(uri)?.port, 9090);
      });

      test('invalid base64 returns null', () {
        expect(VlessParser.parseUri('vmess://not-valid-base64!!!'), isNull);
      });
    });

    group('Trojan', () {
      test('valid URI parses correctly', () {
        const uri = 'trojan://mypassword@server.com:443?security=tls&sni=server.com#Trojan';
        final config = VlessParser.parseUri(uri);
        expect(config, isNotNull);
        expect(config!.protocol, VpnProtocol.trojan);
        expect(config.password, 'mypassword');
        expect(config.address, 'server.com');
        expect(config.port, 443);
      });

      test('missing @ returns null', () {
        expect(VlessParser.parseUri('trojan://no-at-server:443'), isNull);
      });
    });

    group('Shadowsocks', () {
      test('SIP002 format parses correctly', () {
        final userInfo = base64Encode(utf8.encode('chacha20-ietf-poly1305:mypassword'));
        final uri = 'ss://$userInfo@1.2.3.4:8388#SS Test';
        final config = VlessParser.parseUri(uri);
        expect(config, isNotNull);
        expect(config!.protocol, VpnProtocol.shadowsocks);
        expect(config.method, 'chacha20-ietf-poly1305');
        expect(config.password, 'mypassword');
        expect(config.port, 8388);
      });
    });

    group('Hysteria2', () {
      test('hy2:// scheme parses correctly', () {
        const uri = 'hy2://password@server.com:8443?sni=server.com#HY2';
        final config = VlessParser.parseUri(uri);
        expect(config, isNotNull);
        expect(config!.protocol, VpnProtocol.hysteria2);
        expect(config.password, 'password');
        expect(config.address, 'server.com');
        expect(config.port, 8443);
      });

      test('hysteria2:// scheme also works', () {
        const uri = 'hysteria2://pass@host:443';
        expect(VlessParser.parseUri(uri)?.protocol, VpnProtocol.hysteria2);
      });
    });

    group('Unknown scheme', () {
      test('returns null for unknown protocol', () {
        expect(VlessParser.parseUri('wireguard://some-config'), isNull);
        expect(VlessParser.parseUri(''), isNull);
        expect(VlessParser.parseUri('not-a-uri'), isNull);
      });
    });
  });

  group('VpnConfig.validate', () {
    VpnConfig makeConfig({
      String address = 'example.com',
      int port = 443,
      String uuid = 'test-uuid',
      VpnProtocol protocol = VpnProtocol.vless,
      String? password,
    }) {
      return VpnConfig(
        id: 'id',
        name: 'test',
        protocol: protocol,
        address: address,
        port: port,
        uuid: uuid,
        security: VpnSecurity.tls,
        transport: VpnTransport.tcp,
        password: password,
        createdAt: DateTime.now(),
      );
    }

    test('valid VLESS config passes', () {
      expect(makeConfig().validate(), isNull);
    });

    test('empty address fails', () {
      expect(makeConfig(address: '').validate(), isNotNull);
    });

    test('port 0 fails', () {
      expect(makeConfig(port: 0).validate(), isNotNull);
    });

    test('port 65536 fails', () {
      expect(makeConfig(port: 65536).validate(), isNotNull);
    });

    test('VLESS with empty uuid fails', () {
      expect(makeConfig(uuid: '').validate(), isNotNull);
    });

    test('Shadowsocks with empty password fails', () {
      final config = makeConfig(protocol: VpnProtocol.shadowsocks, uuid: '', password: null);
      expect(config.validate(), isNotNull);
    });

    test('Trojan with password passes', () {
      final config = makeConfig(protocol: VpnProtocol.trojan, uuid: '', password: 'pass');
      expect(config.validate(), isNull);
    });
  });
}
