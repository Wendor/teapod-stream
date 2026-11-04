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

      test('percent-decodes the password, as share links encode it', () {
        expect(
          VlessParser.parseUri('trojan://p%40ss%3A1@server.com:443?security=tls')!
              .password,
          'p@ss:1',
        );
        // A raw "@" still parses (the last "@" ends the password); a stray
        // "%" leaves the password as given.
        expect(
          VlessParser.parseUri('trojan://p@ss@server.com:443')!.password,
          'p@ss',
        );
        expect(
          VlessParser.parseUri('trojan://100%zz@server.com:443')!.password,
          '100%zz',
        );
      });

      test('security defaults to TLS and keeps reality or none', () {
        for (final (query, security) in [
          ('', VpnSecurity.tls),
          ('security=tls', VpnSecurity.tls),
          ('security=xtls', VpnSecurity.tls),
          ('security=reality', VpnSecurity.reality),
          ('security=REALITY', VpnSecurity.reality),
          ('security=none', VpnSecurity.none),
        ]) {
          final config = VlessParser.parseUri('trojan://pw@server.com:443?$query');
          expect(config!.security, security, reason: query);
        }
      });

      test('keeps REALITY keys, pin, ALPN and ECH; allowInsecure is not read', () {
        final config = VlessParser.parseUri(
          'trojan://pw@server.com:443?security=reality&type=grpc&pbk=key&sid=ab12'
          '&spx=%2Fprobe&pqv=pq&pinSHA256=00ff&alpn=h2%2Chttp%2F1.1&ech=AEX%2B'
          '&allowInsecure=1&sni=cover.example',
        )!;
        expect(config.publicKey, 'key');
        expect(config.shortId, 'ab12');
        expect(config.spiderX, '/probe');
        expect(config.postQuantumKey, 'pq');
        expect(config.pinSHA256, '00ff');
        expect(config.alpn, 'h2,http/1.1');
        expect(config.ech, 'AEX+');
        expect(config.allowInsecure, isFalse);
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

      test('percent-encoded SIP002 userinfo is decoded', () {
        const key = 'YctPZ6U7xPPcU+gp3u+0tx/tRizJN9K8y+uKlW2qjlI=';
        for (final link in [
          'ss://2022-blake3-aes-256-gcm:${Uri.encodeComponent(key)}@1.2.3.4:8388#SS',
          'ss://${Uri.encodeComponent('2022-blake3-aes-256-gcm:$key')}@1.2.3.4:8388/?#SS',
          // base64 userinfo whose padding was percent-encoded
          'ss://${base64Encode(utf8.encode('aes-256-gcm:pass')).replaceAll('=', '%3D')}@1.2.3.4:8388',
        ]) {
          final config = VlessParser.parseUri(link)!;
          expect(config.port, 8388, reason: link);
          if (config.method == 'aes-256-gcm') {
            expect(config.password, 'pass');
          } else {
            expect(config.method, '2022-blake3-aes-256-gcm');
            expect(config.password, key);
          }
        }
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

      test('official host:port/?query form keeps a non-default port', () {
        final config = VlessParser.parseUri(
          'hysteria2://pass@server.com:8443/?sni=cover.example#HY2',
        )!;
        expect(config.port, 8443);
        expect(config.hopPorts, isNull);
        expect(config.sni, 'cover.example');
        expect(config.name, 'HY2');
      });

      test('port range or list keeps the first port and the hop spec', () {
        final cases = {
          'hy2://pass@server.com:20000-30000/?sni=s': (20000, '20000-30000'),
          'hy2://pass@server.com:443,5000-6000?sni=s': (443, '443,5000-6000'),
          'hy2://pass@[2001:db8::1]:20000-20010/?sni=s': (20000, '20000-20010'),
          'hy2://pass@server.com:443?mport=20000-30000': (443, '20000-30000'),
          'hy2://pass@server.com:443?mport=8443': (443, '8443'),
        };
        for (final entry in cases.entries) {
          final config = VlessParser.parseUri(entry.key);
          expect(config, isNotNull, reason: entry.key);
          expect(config!.port, entry.value.$1, reason: entry.key);
          expect(config.hopPorts, entry.value.$2, reason: entry.key);
          expect(config.validate(), isNull, reason: entry.key);
        }
        expect(
          VlessParser.parseUri('hy2://pass@[2001:db8::1]:20000-20010')!.address,
          '2001:db8::1',
        );
        // An mport equal to the only port is not hopping.
        expect(
          VlessParser.parseUri('hy2://pass@server.com:443?mport=443')!.hopPorts,
          isNull,
        );
      });

      test('an unreadable port is rejected instead of becoming 443', () {
        for (final uri in [
          'hy2://pass@server.com:30000-20000',
          'hy2://pass@server.com:0-10',
          'hy2://pass@server.com:443-70000',
          'hy2://pass@server.com:abc',
          'hy2://pass@server.com:443,',
        ]) {
          expect(VlessParser.parseUri(uri), isNull, reason: uri);
        }
      });

      test('an unreadable mport is ignored when the main port is valid', () {
        for (final uri in [
          'hy2://pass@server.com:443?mport=x-y',
          'hy2://pass@server.com:443?mport=70000',
          'hy2://pass@server.com:443?mport=20000:30000&sni=s',
          'hy2://pass@server.com:443?mport=30000-20000',
        ]) {
          final config = VlessParser.parseUri(uri);
          expect(config, isNotNull, reason: uri);
          expect(config!.port, 443, reason: uri);
          expect(config.hopPorts, isNull, reason: uri);
          expect(config.validate(), isNull, reason: uri);
        }
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
