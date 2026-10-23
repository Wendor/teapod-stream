import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/dns_config.dart';
import 'package:teapodstream/core/models/routing_settings.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/models/xray_tuning.dart';
import 'package:teapodstream/protocols/xray/rust_config_builder.dart';
import 'package:teapodstream/protocols/xray/vless_parser.dart';

// The switchConfig candidate variant (RustConfigBuilder.buildProbe) that
// Android starts as a temporary xray-rust core beside the running VPN.

const uuid = '11111111-2222-4333-8444-555555555555';
final pbk = base64Url.encode(List.filled(32, 7)).replaceAll('=', '');
final key32 = base64.encode(List.generate(32, (i) => i + 11));

VpnEngineOptions options({
  FragmentSettings fragment = const FragmentSettings(),
  NoiseSettings noise = const NoiseSettings(),
  RoutingSettings routing = const RoutingSettings(),
  DnsMode dnsMode = DnsMode.proxy,
  MuxSettings mux = const MuxSettings(),
}) => VpnEngineOptions(
  socksPort: 10808,
  httpPort: 0,
  socksUser: '',
  socksPassword: '',
  fragment: fragment,
  noise: noise,
  routing: routing,
  dnsMode: dnsMode,
  mux: mux,
);

VpnConfig parse(String link) => VlessParser.parseUri(link)!;

final profiles = <String, VpnConfig>{
  'vless-xhttp-reality': parse(
    'vless://$uuid@vless.example:443?encryption=none&type=xhttp'
    '&security=reality&sni=cover.example&pbk=$pbk&sid=1234abcd#v',
  ),
  'vless-tcp-tls-vision': parse(
    'vless://$uuid@vless.example:443?encryption=none&type=tcp'
    '&security=tls&flow=xtls-rprx-vision&sni=cover.example#v',
  ),
  'trojan-ws-tls': parse(
    'trojan://secret@trojan.example:443?type=ws&security=tls'
    '&sni=cover.example&host=edge.example&path=%2Ftunnel#t',
  ),
  'vmess-ws-tls': parse(
    'vmess://${base64.encode(utf8.encode(jsonEncode({'add': 'vmess.example', 'port': '443', 'id': uuid, 'aid': '0', 'net': 'ws', 'tls': 'tls', 'sni': 'cover.example'})))}',
  ),
  'ss2022': parse(
    'ss://2022-blake3-aes-256-gcm:${Uri.encodeComponent(key32)}@ss.example:8388#s',
  ),
  'hy2-salamander-hop': parse(
    'hy2://s3cret@hy.example:20000/?sni=cover.example&obfs=salamander'
    '&obfs-password=mask-pass&mport=20000-20010#h',
  ),
};

Map<String, dynamic> proxyOf(Map<String, dynamic> json) =>
    (json['outbounds'] as List).singleWhere(
          (dynamic o) => o['tag'] == 'proxy',
        )
        as Map<String, dynamic>;

void main() {
  test('the probe carries exactly the VPN proxy outbound', () {
    final variants = {
      'plain': options(),
      'fragment': options(fragment: const FragmentSettings(enabled: true)),
      'noise': options(noise: const NoiseSettings(enabled: true)),
      // ONLY routing makes direct the default outbound of the VPN config.
      'only': options(
        routing: const RoutingSettings(
          direction: RoutingDirection.onlySelected,
          geositeEnabled: true,
          geositeCodes: ['youtube'],
        ),
      ),
      'direct-dns': options(dnsMode: DnsMode.direct),
    };
    for (final profile in profiles.entries) {
      for (final variant in variants.entries) {
        // Refused for VPN and probe alike, see the last test.
        if (profile.key == 'ss2022' && variant.key == 'noise') continue;
        final reason = '${profile.key}/${variant.key}';
        final vpn = RustConfigBuilder.build(profile.value, variant.value);
        final probe = RustConfigBuilder.buildProbe(
          profile.value,
          variant.value,
        );
        expect(probe.keys.toSet(), {'inbounds', 'outbounds', 'dns'}, reason: reason);
        expect(probe['outbounds'], [proxyOf(vpn)], reason: reason);
        expect(probe['dns'], {'hosts': <String, dynamic>{}}, reason: reason);
        expect(probe['inbounds'], [
          {
            'tag': 'probe-in',
            'protocol': 'socks',
            'listen': '127.0.0.1',
            'port': 0,
            'settings': {'auth': 'noauth', 'udp': false},
          },
        ], reason: reason);
        // Encodes without non-JSON values, as the method channel needs.
        expect(
          jsonDecode(RustConfigBuilder.buildProbeJson(profile.value, variant.value)),
          probe,
          reason: reason,
        );
      }
    }
  });

  test('the probe keeps FinalMask, pins and Hysteria hopping', () {
    final hy2 = proxyOf(
      RustConfigBuilder.buildProbe(
        profiles['hy2-salamander-hop']!,
        options(noise: const NoiseSettings(enabled: true)),
      ),
    );
    final mask = hy2['streamSettings']['finalmask'] as Map;
    expect((mask['udp'] as List).map((dynamic m) => m['type']), [
      'salamander',
      'noise',
    ]);
    expect(mask['quicParams']['udpHop']['ports'], isNotEmpty);

    final vless = proxyOf(
      RustConfigBuilder.buildProbe(
        profiles['vless-tcp-tls-vision']!,
        options(fragment: const FragmentSettings(enabled: true)),
      ),
    );
    expect(vless['settings']['vnext'][0]['users'][0]['flow'], 'xtls-rprx-vision');
    expect(
      (vless['streamSettings']['finalmask']['tcp'] as List).single['type'],
      'fragment',
    );
  });

  test('a profile or option the VPN would refuse is refused for the probe too', () {
    expect(
      () => RustConfigBuilder.buildProbe(
        profiles['vless-xhttp-reality']!,
        options(mux: const MuxSettings(enabled: true)),
      ),
      throwsFormatException,
    );
    expect(
      () => RustConfigBuilder.buildProbe(
        profiles['ss2022']!,
        options(noise: const NoiseSettings(enabled: true)),
      ),
      throwsFormatException,
    );
    final kcpVmess = parse(
      'vmess://${base64.encode(utf8.encode(jsonEncode({'add': 'vmess.example', 'port': '443', 'id': uuid, 'aid': '0', 'net': 'kcp', 'tls': 'tls'})))}',
    );
    expect(
      () => RustConfigBuilder.buildProbe(kcpVmess, options()),
      throwsFormatException,
    );
  });
}
