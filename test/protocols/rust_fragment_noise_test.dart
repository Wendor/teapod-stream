import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/dns_config.dart';
import 'package:teapodstream/core/models/routing_settings.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/models/xray_tuning.dart';
import 'package:teapodstream/protocols/xray/rust_config_builder.dart';
import 'package:teapodstream/protocols/xray/vless_parser.dart';
import 'package:teapodstream/protocols/xray/xray_config_builder.dart';

const uuid = '11111111-2222-4333-8444-555555555555';
final pbk = base64Url.encode(List.filled(32, 7)).replaceAll('=', '');
final key32 = base64.encode(List.generate(32, (i) => i + 11));

VpnEngineOptions options({
  FragmentSettings fragment = const FragmentSettings(),
  NoiseSettings noise = const NoiseSettings(),
  bool blockQuic = false,
  bool enableUdp = true,
  DnsMode dnsMode = DnsMode.proxy,
  RoutingSettings routing = const RoutingSettings(),
}) => VpnEngineOptions(
  socksPort: 10808,
  httpPort: 0,
  socksUser: '',
  socksPassword: '',
  fragment: fragment,
  noise: noise,
  blockQuic: blockQuic,
  enableUdp: enableUdp,
  dnsMode: dnsMode,
  routing: routing,
);

const fragmentOn = FragmentSettings(enabled: true);
const noiseOn = NoiseSettings(enabled: true);

VpnConfig vless(String type, String security, [String extra = '']) =>
    VlessParser.parseUri(
      'vless://$uuid@vless.example:443?encryption=none&type=$type'
      '&security=$security&sni=cover.example&pbk=$pbk&sid=1234abcd$extra#v',
    )!;

final hy2 = VlessParser.parseUri(
  'hy2://s3cret@hy.example:8443/?sni=cover.example',
)!;
final ss = VlessParser.parseUri(
  'ss://2022-blake3-aes-256-gcm:${Uri.encodeComponent(key32)}@ss.example:8388#s',
)!;
final vmessPlain = VlessParser.parseUri(
  'vmess://${base64.encode(utf8.encode(jsonEncode({'add': 'vmess.example', 'port': '443', 'id': uuid, 'net': 'ws', 'tls': ''})))}',
)!;

Map<String, dynamic> stream(Map<String, dynamic> json) =>
    (json['outbounds'] as List).singleWhere(
          (dynamic o) => o['tag'] == 'proxy',
        )['streamSettings']
        as Map<String, dynamic>;

void expectNoDialer(Map<String, dynamic> json) {
  expect(
    (json['outbounds'] as List).any((dynamic o) => o['tag'] == 'dialer-out'),
    isFalse,
  );
  expect(stream(json).containsKey('sockopt'), isFalse);
}

void main() {
  group('ClientHello fragmentation', () {
    test('becomes a FinalMask tlshello mask on TCP TLS/REALITY carriers', () {
      for (final config in [
        vless('tcp', 'tls'),
        vless('tcp', 'reality', '&flow=xtls-rprx-vision'),
        vless('ws', 'tls'),
        vless('grpc', 'reality'),
        vless('xhttp', 'reality'),
        vless('xhttp', 'tls', '&alpn=h2'),
      ]) {
        final json = RustConfigBuilder.build(config, options(fragment: fragmentOn));
        expectNoDialer(json);
        expect(stream(json)['finalmask'], {
          'tcp': [
            {
              'type': 'fragment',
              'settings': {
                'packets': 'tlshello',
                'length': '100-200',
                'delay': '10-20',
              },
            },
          ],
        });
        // Go keeps the freedom dialer with the same values.
        final go = XrayConfigBuilder.build(config, options(fragment: fragmentOn));
        final dialer = (go['outbounds'] as List).singleWhere(
          (dynamic o) => o['tag'] == 'dialer-out',
        );
        expect(dialer['settings']['fragment'], {
          'packets': 'tlshello',
          'length': '100-200',
          'interval': '10-20',
        });
        expect(stream(go)['sockopt'], {'dialerProxy': 'dialer-out'});
      }
    });

    test('is not applied where Go has nothing to cut either', () {
      for (final config in [
        hy2,
        vless('xhttp', 'tls', '&alpn=h3'),
        ss,
        vmessPlain,
      ]) {
        final json = RustConfigBuilder.build(config, options(fragment: fragmentOn));
        expectNoDialer(json);
        expect(stream(json).containsKey('finalmask'), isFalse);
      }
      // Invalid values are not applied in either build (the screen says so).
      final invalid = RustConfigBuilder.build(
        vless('tcp', 'tls'),
        options(fragment: const FragmentSettings(enabled: true, length: 'x')),
      );
      expect(stream(invalid).containsKey('finalmask'), isFalse);
    });

    test('caps the record count to fit xray-rust plan limits', () {
      for (final (length, interval, cap) in [
        ('1-3', '900-1000', 10),
        ('1-3', '0-0', 4096),
        ('2-5', '10-20', 500),
      ]) {
        final json = RustConfigBuilder.build(
          vless('tcp', 'tls'),
          options(
            fragment: FragmentSettings(
              enabled: true,
              length: length,
              interval: interval,
            ),
          ),
        );
        expect(
          stream(json)['finalmask']['tcp'][0]['settings']['maxSplit'],
          cap,
          reason: '$length/$interval',
        );
      }
    });

    test('rejects what xray-rust cannot cut', () {
      for (final (fragment, reason) in [
        (const FragmentSettings(enabled: true, packets: '1-3'), 'tlshello'),
        (const FragmentSettings(enabled: true, packets: ''), 'tlshello'),
        (const FragmentSettings(enabled: true, length: '100-20000'), '16384'),
        (const FragmentSettings(enabled: true, interval: '10-2000'), '1000'),
      ]) {
        expect(
          () => RustConfigBuilder.build(
            vless('tcp', 'tls'),
            options(fragment: fragment),
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains(reason),
            ),
          ),
        );
      }
      // Go's packet-range mode also cuts Shadowsocks writes.
      expect(
        () => RustConfigBuilder.build(
          ss,
          options(fragment: const FragmentSettings(enabled: true, packets: '1-3')),
        ),
        throwsFormatException,
      );
      final download = VpnConfig.fromJson({
        ...vless('xhttp', 'reality').toJson(),
        'xhttpExtra': {
          'downloadSettings': {'address': 'down.example', 'port': 443},
        },
      });
      expect(
        () => RustConfigBuilder.build(download, options(fragment: fragmentOn)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('downloadSettings'),
          ),
        ),
      );
    });
  });

  group('UDP noise', () {
    test('becomes a FinalMask noise mask for Hysteria2 and xHTTP h3', () {
      for (final (noise, item) in [
        (noiseOn, {'rand': '50-100', 'delay': '10-20'}),
        (
          const NoiseSettings(
            enabled: true,
            type: NoiseType.str,
            packet: ' synthetic ',
            delay: '0-5',
          ),
          {'type': 'str', 'packet': 'synthetic', 'delay': '0-5'},
        ),
        (
          const NoiseSettings(enabled: true, type: NoiseType.hex, packet: '00ff10'),
          {'type': 'hex', 'packet': '00ff10', 'delay': '10-20'},
        ),
        (
          const NoiseSettings(enabled: true, type: NoiseType.base64, packet: 'AAEC'),
          {'type': 'base64', 'packet': 'AAEC', 'delay': '10-20'},
        ),
      ]) {
        for (final config in [hy2, vless('xhttp', 'tls', '&alpn=h3')]) {
          final json = RustConfigBuilder.build(config, options(noise: noise));
          expectNoDialer(json);
          expect(stream(json)['finalmask'], {
            'udp': [
              {
                'type': 'noise',
                'settings': {
                  'reset': 0,
                  'noise': [item],
                },
              },
            ],
          });
        }
      }
    });

    test('is not applied to UDP carried inside TCP transports', () {
      for (final config in [
        vless('tcp', 'reality'),
        vless('xhttp', 'tls', '&alpn=h2'),
        vmessPlain,
      ]) {
        final json = RustConfigBuilder.build(config, options(noise: noiseOn));
        expectNoDialer(json);
        expect(stream(json).containsKey('finalmask'), isFalse);
      }
    });

    test('rejects Shadowsocks and values xray-rust refuses', () {
      expect(
        () => RustConfigBuilder.build(ss, options(noise: noiseOn)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Shadowsocks'),
          ),
        ),
      );
      for (final noise in [
        const NoiseSettings(enabled: true, type: NoiseType.hex, packet: 'abc'),
        const NoiseSettings(enabled: true, type: NoiseType.hex, packet: 'zz'),
        const NoiseSettings(enabled: true, type: NoiseType.base64, packet: 'AAE'),
        const NoiseSettings(enabled: true, packet: '10-5000'),
        NoiseSettings(enabled: true, type: NoiseType.str, packet: 'x' * 4097),
        const NoiseSettings(enabled: true, delay: '10-1001'),
      ]) {
        expect(
          () => RustConfigBuilder.build(hy2, options(noise: noise)),
          throwsFormatException,
          reason: noise.toJson().toString(),
        );
      }
    });
  });

  group('QUIC blocking and the UDP switch', () {
    List<dynamic> rules(Map<String, dynamic> json) =>
        json['routing']['rules'] as List<dynamic>;
    bool hasBlackhole(Map<String, dynamic> json) => (json['outbounds'] as List)
        .any((dynamic o) => o['tag'] == 'block' && o['protocol'] == 'blackhole');

    test('add no rule and no blackhole by default', () {
      final json = RustConfigBuilder.build(vless('tcp', 'tls'), options());
      expect(hasBlackhole(json), isFalse);
      expect(
        rules(json).any((dynamic r) => r['outboundTag'] == 'block'),
        isFalse,
      );
      expect(json['inbounds'].last['settings'], {'auth': 'noauth', 'udp': true});
    });

    for (final dnsMode in DnsMode.values) {
      for (final direction in RoutingDirection.values) {
        test('drop TUN UDP after the DNS rules ($dnsMode, $direction)', () {
          final routing = RoutingSettings(
            direction: direction,
            geoEnabled: true,
            geoCodes: ['RU'],
            geositeEnabled: true,
            geositeCodes: ['youtube'],
          );
          for (final (blockQuic, enableUdp, port) in [
            (true, true, '443'),
            (false, false, null),
            (true, false, null),
          ]) {
            final json = RustConfigBuilder.build(
              vless('tcp', 'reality'),
              options(
                blockQuic: blockQuic,
                enableUdp: enableUdp,
                dnsMode: dnsMode,
                routing: routing,
              ),
            );
            expect(hasBlackhole(json), isTrue);
            final list = rules(json);
            final dns = list.lastIndexWhere(
              (dynamic r) => r['outboundTag'] == 'dns-out',
            );
            // Port 53 reaches dns-out first; the core's own DNS module is
            // routed by its inbound tag before that.
            expect(list.sublist(0, dns + 1).map((dynamic r) => r['outboundTag']), [
              dnsMode == DnsMode.proxy ? 'proxy' : 'direct',
              'dns-out',
            ]);
            expect(list[dns + 1], {
              'type': 'field',
              // xray-rust ignores SOCKS `udp: false`: the rule closes it.
              'inboundTag': enableUdp ? ['tun-in'] : ['tun-in', 'socks-in'],
              'network': 'udp',
              'port': ?port,
              'outboundTag': 'block',
            });
            expect(
              list.where((dynamic r) => r['outboundTag'] == 'block'),
              hasLength(1),
            );
            expect(json['inbounds'].last['settings']['udp'], enableUdp);
            expect(
              json['outbounds'].first['tag'],
              direction == RoutingDirection.onlySelected ? 'direct' : 'proxy',
            );
          }
        });
      }
    }

    test('do not touch Hysteria2 QUIC or Shadowsocks UDP to the server', () {
      for (final config in [hy2, ss]) {
        final json = RustConfigBuilder.build(
          config,
          options(blockQuic: true, enableUdp: false),
        );
        final block = rules(json).singleWhere(
          (dynamic r) => r['outboundTag'] == 'block',
        );
        // Only application flows from TUN and the local SOCKS; the proxy's
        // own carrier is not routed through these rules.
        expect(block['inboundTag'], ['tun-in', 'socks-in']);
      }
    });
  });
}
