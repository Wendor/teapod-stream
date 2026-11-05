import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/constants/app_constants.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/services/subscription_service.dart';

import '../helpers/local_server.dart';

const _trojan = 'trojan://pw@t.example:443?security=tls#Trojan%20One';
const _hy2 = 'hy2://pass@h.example:8443#Hy';
const _vless = 'vless://11111111-2222-4333-8444-555555555555@v.example:443?security=none#V';

void main() {
  late LocalServer server;
  final svc = SubscriptionService();

  setUp(() async => server = await LocalServer.start());
  tearDown(() => server.close());

  group('body formats', () {
    test('plain URI list skips blank and unknown lines', () async {
      server.serve('$_trojan\r\n\r\nfoo bar\n$_hy2\n  $_vless  \n');
      final r = await svc.fetchSubscription(server.url());
      expect(r.configs.map((c) => c.protocol),
          [VpnProtocol.trojan, VpnProtocol.hysteria2, VpnProtocol.vless]);
      expect(r.configs.first.name, 'Trojan One');
    });

    test('base64 wrapped at 76 chars is decoded as a whole', () async {
      final b64 = base64.encode(utf8.encode([_trojan, _hy2, _vless].join('\n')));
      final wrapped = [
        for (var i = 0; i < b64.length; i += 76) b64.substring(i, (i + 76).clamp(0, b64.length))
      ].join('\n');
      server.serve(wrapped);
      final r = await svc.fetchSubscription(server.url());
      expect(r.configs, hasLength(3));
    });

    test('unpadded base64 is decoded', () async {
      server.serve(base64.encode(utf8.encode(_hy2)).replaceAll('=', ''));
      final r = await svc.fetchSubscription(server.url());
      expect(r.configs.single.protocol, VpnProtocol.hysteria2);
    });

    test('garbage gives no configs', () async {
      server.serve('<html>nope</html>');
      expect((await svc.fetchSubscription(server.url())).configs, isEmpty);
    });

    test('xray JSON array becomes managed configs', () async {
      server.serve(jsonEncode([
        {
          'remarks': ' — Germany',
          'outbounds': [
            {'tag': 'direct', 'protocol': 'freedom'},
            {
              'tag': 'proxy',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {'address': 'de.example', 'port': 8443}
                ]
              }
            },
          ],
        },
        {
          'remarks': 'SS',
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'shadowsocks',
              'settings': {
                'servers': [
                  {'address': 'ss.example', 'port': 1234}
                ]
              }
            },
          ],
        },
        {'outbounds': []},
        'not a map',
      ]));
      final r = await svc.fetchSubscription(server.url());
      expect(r.configs, hasLength(3));
      final de = r.configs[0];
      expect(de.name, 'Germany');
      expect((de.address, de.port), ('de.example', 8443));
      expect(jsonDecode(de.rawXrayConfig!)['remarks'], ' — Germany');
      expect((r.configs[1].address, r.configs[1].port), ('ss.example', 1234));
      expect((r.configs[2].name, r.configs[2].address, r.configs[2].port), ('Server', 'managed', 443));
      expect(r.configs.map((c) => c.id).toSet(), hasLength(3));
    });

    test('single xray JSON object is accepted', () async {
      server.serve(jsonEncode({'remarks': 'One', 'outbounds': []}));
      expect((await svc.fetchSubscription(server.url())).configs.single.name, 'One');
    });

    test('broken JSON falls back to URI parsing', () async {
      server.serve('[not json');
      expect((await svc.fetchSubscription(server.url())).configs, isEmpty);
    });
  });

  group('headers', () {
    test('metadata is parsed from response headers', () async {
      server.serve(_trojan, headers: {
        'profile-title': 'base64:${base64.encode(utf8.encode('Мой VPN'))}',
        'subscription-userinfo': 'upload=10; download=20; total=30; expire=1800000000; junk; x=y',
        'announce': 'Hello',
        'announce-url': 'https://news',
        'x-hwid-active': 'true',
        'x-hwid-max-devices-reached': 'false',
      });
      final r = await svc.fetchSubscription(server.url());
      expect(r.profileTitle, 'Мой VPN');
      expect(r.uploadBytes, 10);
      expect(r.downloadBytes, 20);
      expect(r.totalBytes, 30);
      expect(r.expireAt, DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000));
      expect(r.announce, 'Hello');
      expect(r.announceUrl, 'https://news');
      expect(r.hwidStatus!.isActive, isTrue);
      expect(r.hwidStatus!.notSupported, isFalse);
      expect(r.hwidStatus!.maxDevicesReached, isFalse);
      expect(r.acceptedCertDer, isNull);
    });

    test('zero total/expire mean unlimited; no hwid headers means no status', () async {
      server.serve(_trojan, headers: {
        'profile-title': 'Plain',
        'subscription-userinfo': 'total=0; expire=0',
        'announce': 'base64:%%%',
      });
      final r = await svc.fetchSubscription(server.url());
      expect(r.profileTitle, 'Plain');
      expect(r.totalBytes, isNull);
      expect(r.expireAt, isNull);
      expect(r.announce, '%%%');
      expect(r.hwidStatus, isNull);
    });

    test('default User-Agent and no HWID headers', () async {
      server.serve(_trojan);
      await svc.fetchSubscription(server.url(), userAgent: '  ');
      final h = server.requests.single;
      expect(h.value('user-agent'), AppConstants.subscriptionUserAgent);
      expect(h.value('x-hwid'), isNull);
    });

    test('custom User-Agent and HWID headers are sent', () async {
      server.serve(_trojan);
      await svc.fetchSubscription(server.url(),
          userAgent: 'Happ/1.0',
          hwid: const HwidDeviceInfo(deviceId: 'dev1', deviceModel: 'Pixel', osVersion: 34));
      final h = server.requests.single;
      expect(h.value('user-agent'), 'Happ/1.0');
      expect(h.value('x-hwid'), 'dev1');
      expect(h.value('x-device-os'), 'Android');
      expect(h.value('x-device-model'), 'Pixel');
      expect(h.value('x-ver-os'), '34');
    });
  });

  test('HwidDeviceInfo.toJson', () {
    expect(const HwidDeviceInfo(deviceId: 'a', deviceModel: 'b', osVersion: 1).toJson(),
        {'deviceId': 'a', 'deviceModel': 'b', 'osVersion': 1});
  });

  group('errors', () {
    test('non-200 throws', () async {
      server.serve('x', status: 403);
      await expectLater(svc.fetchSubscription(server.url()), throwsA(isA<Exception>()));
    });

    test('body over 10 MB throws', () async {
      server.serve(List<int>.filled(10 * 1024 * 1024 + 1, 0x61));
      await expectLater(
          svc.fetchSubscription(server.url()),
          throwsA(predicate((e) => e.toString().contains('exceeds 10 MB'))));
    });
  });

  group('self-signed certificate', () {
    late LocalServer tls;
    late String der;

    setUp(() async {
      tls = await LocalServer.start(tls: LocalServer.selfSignedContext());
      tls.serve(_trojan);
      final pem = File('test/fixtures/localhost_cert.pem').readAsStringSync();
      final body = pem.split('\n').where((l) => !l.startsWith('-----')).join();
      der = base64.encode(base64.decode(body));
    });
    tearDown(() => tls.close());

    test('untrusted certificate throws with details', () async {
      await expectLater(
        svc.fetchSubscription(tls.url()),
        throwsA(isA<UntrustedCertificateException>()
            .having((e) => e.host, 'host', '127.0.0.1')
            .having((e) => e.subject, 'subject', contains('localhost'))
            .having((e) => e.toString(), 'toString', contains('127.0.0.1'))),
      );
    });

    test('allowSelfSigned accepts and returns the certificate to pin', () async {
      final r = await svc.fetchSubscription(tls.url(), allowSelfSigned: true);
      expect(r.configs, hasLength(1));
      expect(r.acceptedCertDer, der);
    });

    test('pinned certificate is trusted without allowSelfSigned', () async {
      final r = await svc.fetchSubscription(tls.url(), pinnedCertDer: der);
      expect(r.configs, hasLength(1));
      expect(r.acceptedCertDer, der);
    });

    test('a different pinned certificate is rejected', () async {
      await expectLater(svc.fetchSubscription(tls.url(), pinnedCertDer: 'AAAA'),
          throwsA(isA<UntrustedCertificateException>()));
    });
  });
}
