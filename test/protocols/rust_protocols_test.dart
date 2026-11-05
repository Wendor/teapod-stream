import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/dns_config.dart';
import 'package:teapodstream/core/models/routing_settings.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/protocols/xray/rust_config_builder.dart';
import 'package:teapodstream/protocols/xray/vless_parser.dart';
import 'package:teapodstream/protocols/xray/xray_config_builder.dart';

const uuid = '11111111-2222-4333-8444-555555555555';
final pbk = base64Url.encode(List.filled(32, 7)).replaceAll('=', '');
final pinHex = List.generate(
  32,
  (i) => (i * 7 + 3).toRadixString(16).padLeft(2, '0'),
).join();
final key16 = base64.encode(List.generate(16, (i) => i + 1));
final key32 = base64.encode(List.generate(32, (i) => i + 11));

VpnEngineOptions options({
  RoutingSettings routing = const RoutingSettings(),
  DnsMode dnsMode = DnsMode.proxy,
}) => VpnEngineOptions(
  socksPort: 10808,
  httpPort: 0,
  socksUser: '',
  socksPassword: '',
  routing: routing,
  dnsMode: dnsMode,
);

VpnConfig parse(String link) => VlessParser.parseUri(link)!;

String trojan(String type, String security, [String extra = '']) =>
    'trojan://trojan-test-password@trojan.example:443?type=$type'
    '&security=$security&sni=cover.example&host=edge.example&path=%2Ftunnel'
    '&serviceName=grpc-service&pbk=$pbk&sid=1234abcd$extra#t';

String vmess(Map<String, Object?> fields) =>
    'vmess://${base64.encode(utf8.encode(jsonEncode({
      'v': '2',
      'ps': 'm',
      'add': 'vmess.example',
      'port': '443',
      'id': uuid,
      'aid': '0',
      'scy': 'auto',
      'net': 'ws',
      'type': 'none',
      'host': 'edge.example',
      'path': '/tunnel',
      'tls': 'tls',
      'sni': 'cover.example',
      ...fields,
    })))}';

String ss(String method, String key, [String query = '']) =>
    'ss://$method:${Uri.encodeComponent(key)}@ss.example:8388$query#s';

Map<String, dynamic> proxy(Map<String, dynamic> json) =>
    (json['outbounds'] as List).singleWhere(
          (dynamic o) => o['tag'] == 'proxy',
        )
        as Map<String, dynamic>;

void expectRejected(VpnConfig config, String reason) {
  expect(RustConfigBuilder.unsupportedReason(config), contains(reason));
  expect(
    () => RustConfigBuilder.build(config, options()),
    throwsFormatException,
  );
}

void main() {
  group('Trojan', () {
    for (final security in ['tls', 'reality']) {
      for (final type in ['tcp', 'raw', 'ws', 'httpupgrade', 'grpc', 'xhttp']) {
        if (security == 'reality' && (type == 'ws' || type == 'httpupgrade')) {
          continue;
        }
        test('runs over $type + $security', () {
          final config = parse(trojan(type, security));
          expect(config.security.name, security);
          expect(RustConfigBuilder.unsupportedReason(config), isNull);
          final outbound = proxy(RustConfigBuilder.build(config, options()));
          expect(outbound['protocol'], 'trojan');
          // xray-rust: exactly one servers entry, no flow.
          expect(outbound['settings'], {
            'servers': [
              {
                'address': 'trojan.example',
                'port': 443,
                'password': 'trojan-test-password',
              },
            ],
          });
          final stream = outbound['streamSettings'] as Map;
          expect(stream['security'], security);
          expect(
            stream['network'],
            switch (type) {
              'raw' => 'tcp',
              _ => type,
            },
          );
          expect(stream['${security}Settings']['serverName'], 'cover.example');
          if (security == 'reality') {
            expect(stream['realitySettings']['publicKey'], pbk);
            expect(stream['realitySettings']['shortId'], '1234abcd');
          }
        });
      }
    }

    test('keeps the certificate pin and the h3 ALPN of xHTTP', () {
      final config = parse(
        trojan('xhttp', 'tls', '&alpn=h3&pinSHA256=$pinHex&allowInsecure=1'),
      );
      // allowInsecure is still not read for Trojan: the pin alone decides.
      expect(config.allowInsecure, isFalse);
      final tls = proxy(RustConfigBuilder.build(config, options()))
          ['streamSettings']['tlsSettings'];
      expect(tls['alpn'], ['h3']);
      expect(tls['pinnedPeerCertSha256'], pinHex);
      expect(tls['allowInsecure'], isFalse);
    });

    test('rejects what xray-rust refuses or would silently change', () {
      expectRejected(parse(trojan('tcp', 'none')), 'TLS или Reality');
      expectRejected(parse(trojan('ws', 'reality')), 'Reality');
      expectRejected(parse(trojan('quic', 'tls')), 'Транспорт');
      expectRejected(parse(trojan('kcp', 'tls')), 'Транспорт');
      expectRejected(
        parse(trojan('tcp', 'tls', '&headerType=http')),
        'headerType',
      );
      expectRejected(parse(trojan('tcp', 'tls', '&ech=AEX%2B')), 'ECH');
      expectRejected(
        parse(
          'trojan://${'p' * 4097}@trojan.example:443?security=tls&sni=cover.example',
        ),
        '4096',
      );
    });
  });

  group('VMess', () {
    test('runs VMess AEAD over every carrier, with and without TLS', () {
      for (final net in ['tcp', 'ws', 'httpupgrade', 'grpc', 'xhttp']) {
        for (final tls in ['tls', '']) {
          final config = parse(vmess({'net': net, 'tls': tls}));
          expect(
            RustConfigBuilder.unsupportedReason(config),
            isNull,
            reason: '$net/$tls',
          );
          final outbound = proxy(RustConfigBuilder.build(config, options()));
          expect(outbound['protocol'], 'vmess');
          // One vnext server with one user; no alterId is written.
          expect(outbound['settings'], {
            'vnext': [
              {
                'address': 'vmess.example',
                'port': 443,
                'users': [
                  {'id': uuid, 'security': 'auto'},
                ],
              },
            ],
          });
          expect(
            outbound['streamSettings']['security'],
            tls.isEmpty ? 'none' : 'tls',
          );
        }
      }
    });

    test('keeps an explicit AEAD cipher that Go replaces with auto', () {
      for (final scy in ['aes-128-gcm', 'chacha20-poly1305', 'AUTO', '']) {
        final config = parse(vmess({'scy': scy}));
        final user =
            proxy(RustConfigBuilder.build(config, options()))
                ['settings']['vnext'][0]['users'][0];
        expect(user['security'], scy.isEmpty ? 'auto' : scy.toLowerCase());
        final goUser =
            proxy(XrayConfigBuilder.build(config, options()))
                ['settings']['vnext'][0]['users'][0];
        expect(goUser['security'], 'auto');
      }
    });

    test('sends non-AEAD ciphers as auto and ignores alterId, as Go', () {
      final aead = proxy(RustConfigBuilder.build(parse(vmess({})), options()));
      // The client speaks AEAD whatever the link's aid; no alterId is written.
      final legacy = parse(vmess({'aid': '64'}));
      expect(RustConfigBuilder.unsupportedReason(legacy), isNull);
      final legacyOut = proxy(RustConfigBuilder.build(legacy, options()));
      expect(legacyOut['settings'], aead['settings']);
      expect(
        (legacyOut['settings']['vnext'][0]['users'][0] as Map).containsKey(
          'alterId',
        ),
        isFalse,
      );
      // The server reads the body cipher from the request header.
      for (final scy in ['none', 'zero', 'aes-128-cfb']) {
        final config = parse(vmess({'scy': scy}));
        expect(RustConfigBuilder.unsupportedReason(config), isNull, reason: scy);
        final user =
            proxy(RustConfigBuilder.build(config, options()))
                ['settings']['vnext'][0]['users'][0];
        expect(user['security'], 'auto', reason: scy);
      }
    });

    test('rejects unsupported VMess link fields', () {
      for (final net in ['kcp', 'quic', 'h2']) {
        expectRejected(parse(vmess({'net': net})), 'Транспорт');
      }
      expectRejected(
        parse(vmess({'net': 'tcp', 'type': 'http'})),
        'headerType',
      );
      // The parser maps every tls value but "tls" to no transport security.
      expectRejected(parse(vmess({'tls': 'reality'})), 'reality');
      // "TLS" or " tls" would silently go to the TLS port as plain VMess.
      for (final tls in ['TLS', 'Tls', ' tls']) {
        final config = parse(vmess({'tls': tls}));
        expect(config.security, VpnSecurity.none, reason: tls);
        expectRejected(config, 'tls=«$tls»');
      }
      expectRejected(parse(vmess({'id': 'not-a-uuid'})), 'UUID');
    });
  });

  group('Shadowsocks 2022', () {
    test('runs the three blake3 methods from SIP002 and legacy links', () {
      for (final (method, key) in [
        ('2022-blake3-aes-128-gcm', key16),
        ('2022-blake3-aes-256-gcm', key32),
        ('2022-blake3-chacha20-poly1305', key32),
        ('2022-blake3-aes-128-gcm', '$key16:$key16'),
      ]) {
        for (final link in [
          ss(method, key),
          'ss://${base64Url.encode(utf8.encode('$method:$key')).replaceAll('=', '')}'
              '@ss.example:8388#s',
          'ss://${base64.encode(utf8.encode('$method:$key@ss.example:8388'))}#s',
        ]) {
          final config = parse(link);
          expect(config.password, key, reason: link);
          expect(RustConfigBuilder.unsupportedReason(config), isNull);
          final outbound = proxy(RustConfigBuilder.build(config, options()));
          expect(outbound['protocol'], 'shadowsocks');
          expect(outbound['settings'], {
            'servers': [
              {
                'address': 'ss.example',
                'port': 8388,
                'method': method,
                'password': key,
              },
            ],
          });
          expect(outbound['streamSettings'], {
            'network': 'tcp',
            'security': 'none',
          });
        }
      }
    });

    test('rejects AEAD-2017, bad keys, plugins and Outline prefixes', () {
      for (final method in [
        'chacha20-ietf-poly1305',
        'aes-256-gcm',
        'aes-128-gcm',
      ]) {
        expectRejected(parse(ss(method, 'secret')), 'Shadowsocks 2022');
      }
      expectRejected(
        parse(ss('2022-blake3-chacha20-poly1305', '$key32:$key32')),
        'один ключ',
      );
      expectRejected(
        parse(ss('2022-blake3-aes-128-gcm', List.filled(9, key16).join(':'))),
        'до 8 ключей',
      );
      expectRejected(parse(ss('2022-blake3-aes-256-gcm', key16)), 'base64');
      expectRejected(
        parse(ss('2022-blake3-aes-128-gcm', key16.replaceAll('=', ''))),
        'base64',
      );
      expectRejected(
        parse(
          ss('2022-blake3-aes-128-gcm', key16, '/?plugin=obfs-local%3Bobfs%3Dhttp'),
        ),
        'SIP003',
      );
      expectRejected(
        parse(ss('2022-blake3-aes-128-gcm', key16, '/?prefix=%16%03%01')),
        'Outline',
      );
    });
  });

  for (final direction in [
    RoutingDirection.bypass,
    RoutingDirection.onlySelected,
  ]) {
    test('routing, FakeDNS, DNS and ad blocking match VLESS in $direction mode', () {
      final vless = parse(
        'vless://$uuid@edge.example:443?type=tcp&security=tls'
        '&encryption=none&sni=cover.example',
      );
      for (final dnsMode in DnsMode.values) {
        for (final adBlock in [false, true]) {
          final routing = RoutingSettings(
            direction: direction,
            geoEnabled: true,
            geoCodes: ['RU'],
            geositeEnabled: true,
            geositeCodes: ['youtube'],
            adBlockEnabled: adBlock,
          );
          final opts = options(routing: routing, dnsMode: dnsMode);
          final expected = RustConfigBuilder.build(vless, opts);
          for (final config in [
            parse(trojan('grpc', 'tls')),
            parse(vmess({})),
            parse(ss('2022-blake3-aes-256-gcm', key32)),
          ]) {
            final json = RustConfigBuilder.build(config, opts);
            expect(json['dns'], expected['dns']);
            expect(json['routing'], expected['routing']);
            expect(json['inbounds'], expected['inbounds']);
            Iterable<dynamic> others(Map<String, dynamic> j) =>
                (j['outbounds'] as List).where(
                  (dynamic o) => o['tag'] != 'proxy',
                );
            expect(others(json), others(expected));
          }
        }
      }
    });
  }
}
