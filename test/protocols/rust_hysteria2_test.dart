import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/dns_config.dart';
import 'package:teapodstream/core/models/routing_settings.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/models/xray_tuning.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/protocols/xray/rust_config_builder.dart';
import 'package:teapodstream/protocols/xray/vless_parser.dart';
import 'package:teapodstream/protocols/xray/xray_config_builder.dart';

final pinHex = List.generate(
  32,
  (i) => (i * 7 + 3).toRadixString(16).padLeft(2, '0'),
).join();

VpnEngineOptions options({
  RoutingSettings routing = const RoutingSettings(),
  DnsMode dnsMode = DnsMode.proxy,
  bool mux = false,
  bool fragment = false,
  bool noise = false,
  TlsFingerprint fingerprint = TlsFingerprint.defaultFp,
}) => VpnEngineOptions(
  socksPort: 10808,
  httpPort: 0,
  socksUser: '',
  socksPassword: '',
  routing: routing,
  dnsMode: dnsMode,
  tlsFingerprint: fingerprint,
  mux: MuxSettings(enabled: mux),
  fragment: FragmentSettings(enabled: fragment),
  noise: NoiseSettings(enabled: noise),
);

VpnConfig hy2([String query = 'sni=cover.example']) =>
    VlessParser.parseUri('hy2://s3cret@hy.example:8443/?$query#hy')!;

Map<String, dynamic> proxy(Map<String, dynamic> json) =>
    (json['outbounds'] as List).singleWhere(
          (dynamic o) => o['tag'] == 'proxy',
        )
        as Map<String, dynamic>;

void main() {
  test('translates Hysteria2 into the xray-rust outbound', () {
    final config = hy2('sni=cover.example&pinSHA256=$pinHex');
    expect(RustConfigBuilder.unsupportedReason(config), isNull);
    final outbound = proxy(
      RustConfigBuilder.build(
        config,
        options(fingerprint: TlsFingerprint.firefox),
      ),
    );
    expect(outbound['protocol'], 'hysteria');
    expect(outbound['settings'], {
      'version': 2,
      'address': 'hy.example',
      'port': 8443,
    });
    final stream = outbound['streamSettings'] as Map;
    expect(stream['network'], 'hysteria');
    expect(stream['security'], 'tls');
    expect(stream['hysteriaSettings'], {'version': 2, 'auth': 's3cret'});
    expect(stream.containsKey('finalmask'), isFalse);
    expect(stream.containsKey('sockopt'), isFalse);
    expect(outbound.containsKey('mux'), isFalse);
    // Go key replaced by the hex leaf pin; no uTLS fingerprint or ALPN for QUIC.
    expect(stream['tlsSettings'], {
      'serverName': 'cover.example',
      'allowInsecure': false,
      'pinnedPeerCertSha256': pinHex,
    });
  });

  test('the Go builder emits the pin key Xray-core reads and lets the pin win', () {
    final vless = VlessParser.parseUri(
      'vless://11111111-2222-4333-8444-555555555555@edge.example:443'
      '?type=tcp&security=tls&encryption=none&sni=cover.example'
      '&allowInsecure=1&pinSHA256=$pinHex',
    )!;
    for (final config in [
      hy2('sni=cover.example&pinSHA256=$pinHex'),
      hy2('insecure=1&sni=cover.example&pinSHA256=$pinHex'),
      vless,
    ]) {
      final tls = Map<String, dynamic>.from(
        proxy(XrayConfigBuilder.build(config, options()))['streamSettings']
            ['tlsSettings'] as Map,
      );
      // Xray-core 1aabe7ea: TLSConfig knows only pinnedPeerCertSha256 (hex)
      // and fails to build with allowInsecure: true.
      expect(tls['pinnedPeerCertSha256'], pinHex);
      expect(tls['allowInsecure'], isFalse);
      expect(tls.containsKey('pinnedPeerCertificateChainSha256'), isFalse);
    }
    // Without a pin the flag is passed through unchanged, as before.
    final insecure = proxy(
      XrayConfigBuilder.build(hy2('insecure=1&sni=cover.example'), options()),
    )['streamSettings']['tlsSettings'] as Map;
    expect(insecure['allowInsecure'], isTrue);
    expect(insecure.containsKey('pinnedPeerCertSha256'), isFalse);
  });

  test('SNI falls back to the server address and colon/base64 pins map to hex', () {
    for (final pin in [
      [
        for (var i = 0; i < 64; i += 2) pinHex.substring(i, i + 2).toUpperCase(),
      ].join(':'),
      base64.encode(List.generate(32, (i) => i * 7 + 3)),
    ]) {
      final config = VlessParser.parseUri(
        'hy2://s3cret@203.0.113.7:443?pinSHA256=${Uri.encodeComponent(pin)}',
      )!;
      final tls =
          proxy(RustConfigBuilder.build(config, options()))['streamSettings']
              ['tlsSettings'];
      expect(tls['serverName'], '203.0.113.7');
      expect(tls['pinnedPeerCertSha256'], pinHex);
    }
  });

  test('a certificate pin wins over insecure=1 for Hysteria2 and VLESS TLS', () {
    final vless = VlessParser.parseUri(
      'vless://11111111-2222-4333-8444-555555555555@edge.example:443'
      '?type=tcp&security=tls&encryption=none&sni=cover.example'
      '&allowInsecure=1&pinSHA256=$pinHex',
    )!;
    for (final config in [
      hy2('insecure=1&sni=cover.example&pinSHA256=$pinHex'),
      vless,
    ]) {
      expect(config.allowInsecure, isTrue);
      expect(RustConfigBuilder.unsupportedReason(config), isNull);
      final tls =
          proxy(RustConfigBuilder.build(config, options()))['streamSettings']
              ['tlsSettings'];
      expect(tls['allowInsecure'], isFalse);
      expect(tls['pinnedPeerCertSha256'], pinHex);
    }
  });

  test('Salamander and port hopping use the Go builder FinalMask unchanged', () {
    for (final (query, port) in [
      ('obfs=salamander&obfs-password=salamander-pass', '8443'),
      ('', '20000-30000'),
      ('', '443,5000-6000'),
      ('mport=20000-30000', '443'),
      ('obfs=salamander&obfs-password=salamander-pass', '20000-30000'),
    ]) {
      final config = VlessParser.parseUri(
        'hy2://s3cret@hy.example:$port/?sni=cover.example&$query',
      )!;
      expect(RustConfigBuilder.unsupportedReason(config), isNull, reason: query);
      final rust = proxy(RustConfigBuilder.build(config, options()));
      final go = proxy(XrayConfigBuilder.build(config, options()));
      // xray-rust 0.8.1 reads Xray-core v26.7.28's spelling, which Go writes.
      expect(
        rust['streamSettings']['finalmask'],
        go['streamSettings']['finalmask'],
      );
      expect(rust['settings']['port'], config.port);
      final mask = rust['streamSettings']['finalmask'] as Map;
      expect(mask.containsKey('udp'), config.obfsPassword != null);
      expect(mask.containsKey('quicParams'), config.hopPorts != null);
      if (config.hopPorts != null) {
        expect(mask['quicParams'], {
          'udpHop': {'ports': config.hopPorts},
        });
      }
      expect(rust['streamSettings'].containsKey('sockopt'), isFalse);
    }
  });

  test('rejects Hysteria2 features xray-rust 0.8.1 does not run', () {
    final cases = {
      'obfs=salamander&obfs-password=abc': '4 до 4096',
      'obfs=salamander': 'obfs-password',
      'obfs=gecko&obfs-password=secret-pass': 'gecko',
      'insecure=1': 'allowInsecure',
    };
    for (final entry in cases.entries) {
      final config = hy2(entry.key);
      expect(
        RustConfigBuilder.unsupportedReason(config),
        contains(entry.value),
        reason: entry.key,
      );
      expect(
        () => RustConfigBuilder.build(config, options()),
        throwsFormatException,
      );
    }
    final tooManyPorts = VlessParser.parseUri(
      'hy2://s3cret@hy.example:1-65535,1-2/?sni=cover.example',
    )!;
    expect(RustConfigBuilder.unsupportedReason(tooManyPorts), contains('65535'));
    final longAuth = VlessParser.parseUri(
      'hy2://${'a' * 4097}@hy.example:443',
    )!;
    expect(RustConfigBuilder.unsupportedReason(longAuth), contains('4096'));
  });

  test('Mux and fragmentation do not apply to Hysteria2; noise follows Salamander', () {
    final config = hy2(
      'pinSHA256=$pinHex&obfs=salamander&obfs-password=salamander-pass',
    );
    final json = RustConfigBuilder.build(
      config,
      options(mux: true, fragment: true, noise: true),
    );
    expect(proxy(json).containsKey('mux'), isFalse);
    expect(
      (json['outbounds'] as List).any((dynamic o) => o['tag'] == 'dialer-out'),
      isFalse,
    );
    final stream = proxy(json)['streamSettings'] as Map;
    expect(stream.containsKey('sockopt'), isFalse);
    // Go sends noise through a raw freedom dialer beneath Salamander: in
    // xray-rust's order a noise mask after Salamander stays unobfuscated.
    expect(stream['finalmask'], {
      'udp': [
        {
          'type': 'salamander',
          'settings': {'password': 'salamander-pass'},
        },
        {
          'type': 'noise',
          'settings': {
            'reset': 0,
            'noise': [
              {'rand': '50-100', 'delay': '10-20'},
            ],
          },
        },
      ],
    });
    // Go keeps its freedom dialer for the same options.
    final go = XrayConfigBuilder.build(config, options(noise: true));
    expect(
      (go['outbounds'] as List).any((dynamic o) => o['tag'] == 'dialer-out'),
      isTrue,
    );
    // VLESS keeps rejecting Mux.
    final vless = VlessParser.parseUri(
      'vless://11111111-2222-4333-8444-555555555555@edge.example:443'
      '?type=tcp&security=tls&encryption=none&sni=cover.example',
    )!;
    expect(
      () => RustConfigBuilder.build(vless, options(mux: true)),
      throwsFormatException,
    );
  });

  for (final direction in [
    RoutingDirection.bypass,
    RoutingDirection.onlySelected,
  ]) {
    test('domain routing, FakeDNS, DNS mode and ad blocking match VLESS in $direction mode', () {
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
          final json = RustConfigBuilder.build(
            hy2('pinSHA256=$pinHex'),
            options(routing: routing, dnsMode: dnsMode),
          );
          final vless = RustConfigBuilder.build(
            VlessParser.parseUri(
              'vless://11111111-2222-4333-8444-555555555555@edge.example:443'
              '?type=tcp&security=tls&encryption=none&sni=cover.example',
            )!,
            options(routing: routing, dnsMode: dnsMode),
          );
          expect(json['dns'], vless['dns']);
          expect(json['routing'], vless['routing']);
          expect(json['inbounds'], vless['inbounds']);
          Iterable<dynamic> others(Map<String, dynamic> j) =>
              (j['outbounds'] as List).where((dynamic o) => o['tag'] != 'proxy');
          expect(others(json), others(vless));
          expect(
            (json['outbounds'] as List).first['tag'],
            direction == RoutingDirection.bypass ? 'proxy' : 'direct',
          );
        }
      }
    });
  }
}
