// Exports Rust configs through the production parser and builder for
// `xray-rust config check`: every supported protocol/transport/security
// variant, the options that change the generated JSON (routing, DNS,
// fragmentation, noise, QUIC/UDP blocking, fingerprints) and the profiles the
// builder must refuse. All credentials and keys are synthetic.
//
//   TEAPOD_MATRIX_OUTPUT=/tmp/matrix.json flutter test \
//     --dart-define=TEAPOD_CORE=rust test/support/export_rust_config_matrix.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/constants/core_features.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/dns_config.dart';
import 'package:teapodstream/core/models/routing_settings.dart';
import 'package:teapodstream/core/models/xray_tuning.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/protocols/xray/rust_config_builder.dart';
import 'package:teapodstream/protocols/xray/vless_parser.dart';

const uuid = '11111111-2222-4333-8444-555555555555';
final pbk = base64Url.encode(List.filled(32, 7)).replaceAll('=', '');
final pin = List.generate(32, (i) => (i * 7 + 3).toRadixString(16).padLeft(2, '0')).join();
final key16 = base64.encode(List.generate(16, (i) => i + 1));
final key32 = base64.encode(List.generate(32, (i) => i + 11));

String vless(String type, String security, {String flow = '', String extra = ''}) =>
    'vless://$uuid@vless.example:443?encryption=none&type=$type&security=$security'
    '&flow=$flow&sni=cover.example&host=edge.example&path=%2Ftunnel'
    '&serviceName=grpc-service&pbk=$pbk&sid=1234abcd&spx=%2Fprobe$extra#v';

String trojan(String type, String security, {String extra = ''}) =>
    'trojan://trojan-test-password@trojan.example:443?type=$type&security=$security'
    '&sni=cover.example&host=edge.example&path=%2Ftunnel&serviceName=grpc-service'
    '&pbk=$pbk&sid=1234abcd$extra#t';

String vmess(Map<String, Object?> fields) => 'vmess://${base64.encode(utf8.encode(jsonEncode({
      'v': '2', 'ps': 'm', 'add': 'vmess.example', 'port': '443', 'id': uuid,
      'aid': '0', 'scy': 'auto', 'net': 'ws', 'type': 'none',
      'host': 'edge.example', 'path': '/tunnel', 'tls': 'tls', 'sni': 'cover.example',
      ...fields,
    })))}';

String ssPlain(String method, String key, {String query = ''}) =>
    'ss://$method:${Uri.encodeComponent(key)}@ss.example:8388$query#s';

String hy2(String query, {String port = '8443'}) =>
    'hy2://s3cret@hy.example:$port/?sni=cover.example&$query#h';

/// Profile name → (share link, expected rejection substring or null).
Map<String, (String, String?)> profiles() {
  final p = <String, (String, String?)>{};
  for (final security in ['tls', 'reality']) {
    for (final type in ['tcp', 'raw', 'ws', 'httpupgrade', 'grpc', 'xhttp', 'splithttp']) {
      final wsReality = security == 'reality' && (type == 'ws' || type == 'httpupgrade');
      p['vless-$type-$security'] = (vless(type, security), wsReality ? 'Reality' : null);
      p['trojan-$type-$security'] = (trojan(type, security), wsReality ? 'Reality' : null);
    }
    for (final flow in RustConfigBuilder.visionFlows) {
      p['vless-tcp-$security-$flow'] = (vless('tcp', security, flow: flow), null);
      p['vless-grpc-$security-$flow'] = (vless('grpc', security, flow: flow), 'Vision');
    }
  }
  for (final mode in ['packet-up', 'stream-up', 'stream-one']) {
    p['vless-xhttp-reality-$mode'] = (vless('xhttp', 'reality', extra: '&mode=$mode'), null);
  }
  p['vless-xhttp-tls-h3'] = (vless('xhttp', 'tls', extra: '&alpn=h3'), null);
  p['trojan-xhttp-tls-h3'] = (trojan('xhttp', 'tls', extra: '&alpn=h3'), null);
  p['vless-tcp-tls-pin-insecure'] =
      (vless('tcp', 'tls', extra: '&allowInsecure=1&pinSHA256=$pin'), null);
  p['trojan-tcp-tls-pin'] = (trojan('tcp', 'tls', extra: '&pinSHA256=$pin'), null);
  p['vless-tcp-tls-insecure'] = (vless('tcp', 'tls', extra: '&allowInsecure=1'), 'allowInsecure');
  p['vless-tcp-none'] = (vless('tcp', 'none'), 'TLS или Reality');
  p['vless-kcp-tls'] = (vless('kcp', 'tls'), 'Транспорт');
  p['vless-tcp-http-header'] = (vless('tcp', 'tls', extra: '&headerType=http'), 'headerType');
  p['vless-tcp-tls-ech'] = (vless('tcp', 'tls', extra: '&ech=AEX%2B'), 'ECH');
  p['trojan-tcp-none'] = (trojan('tcp', 'none'), 'Trojan');
  p['trojan-quic-tls'] = (trojan('quic', 'tls'), 'Транспорт');

  for (final net in ['tcp', 'ws', 'httpupgrade', 'grpc', 'xhttp']) {
    for (final tls in ['tls', '']) {
      p['vmess-$net-${tls.isEmpty ? 'none' : tls}'] = (vmess({'net': net, 'tls': tls}), null);
    }
  }
  for (final scy in ['aes-128-gcm', 'chacha20-poly1305', '']) {
    p['vmess-ws-tls-scy-${scy.isEmpty ? 'absent' : scy}'] = (vmess({'scy': scy}), null);
  }
  p['vmess-xhttp-tls-h3'] = (vmess({'net': 'xhttp', 'alpn': 'h3'}), null);
  // Non-AEAD scy is sent as auto and aid is ignored, as in Go.
  p['vmess-scy-none'] = (vmess({'scy': 'none'}), null);
  p['vmess-scy-zero'] = (vmess({'scy': 'zero'}), null);
  p['vmess-scy-cfb'] = (vmess({'scy': 'aes-128-cfb'}), null);
  p['vmess-aid-64'] = (vmess({'aid': '64'}), null);
  p['vmess-tls-upper-case'] = (vmess({'tls': 'TLS'}), 'tls');
  p['vmess-kcp'] = (vmess({'net': 'kcp'}), 'Транспорт');
  p['vmess-quic'] = (vmess({'net': 'quic'}), 'Транспорт');
  p['vmess-tcp-http-header'] = (vmess({'net': 'tcp', 'type': 'http'}), 'headerType');
  p['vmess-reality'] = (vmess({'tls': 'reality'}), 'reality');
  p['vmess-non-uuid-id'] = (vmess({'id': 'not-a-uuid'}), 'UUID');

  p['ss-aes128'] = (ssPlain('2022-blake3-aes-128-gcm', key16), null);
  p['ss-aes256'] = (ssPlain('2022-blake3-aes-256-gcm', key32), null);
  p['ss-chacha'] = (ssPlain('2022-blake3-chacha20-poly1305', key32), null);
  p['ss-aes128-identity'] = (ssPlain('2022-blake3-aes-128-gcm', '$key16:$key16'), null);
  p['ss-aes256-base64url-userinfo'] = (
    'ss://${base64Url.encode(utf8.encode('2022-blake3-aes-256-gcm:$key32')).replaceAll('=', '')}'
        '@ss.example:8388#s',
    null,
  );
  p['ss-aes256-legacy-base64'] = (
    'ss://${base64.encode(utf8.encode('2022-blake3-aes-256-gcm:$key32@ss.example:8388'))}#s',
    null,
  );
  p['ss-chacha-identity'] =
      (ssPlain('2022-blake3-chacha20-poly1305', '$key32:$key32'), 'один ключ');
  p['ss-aes256-short-key'] = (ssPlain('2022-blake3-aes-256-gcm', key16), 'base64');
  p['ss-legacy-chacha'] = (ssPlain('chacha20-ietf-poly1305', 'secret'), 'Shadowsocks 2022');
  p['ss-legacy-aes'] = (ssPlain('aes-256-gcm', 'secret'), 'Shadowsocks 2022');
  p['ss-plugin'] = (
    ssPlain('2022-blake3-aes-128-gcm', key16, query: '/?plugin=obfs-local%3Bobfs%3Dhttp'),
    'SIP003',
  );
  p['ss-outline-prefix'] =
      (ssPlain('2022-blake3-aes-128-gcm', key16, query: '/?prefix=%16%03%01'), 'Outline');

  p['hy2-pin'] = (hy2('pinSHA256=$pin'), null);
  p['hy2-insecure-pin'] = (hy2('insecure=1&pinSHA256=$pin'), null);
  p['hy2-salamander'] = (hy2('obfs=salamander&obfs-password=salamander-pass'), null);
  p['hy2-hop-range'] = (hy2('', port: '20000-30000'), null);
  p['hy2-hop-list'] = (hy2('', port: '443,5000-6000'), null);
  p['hy2-mport'] = (hy2('mport=20000-20100', port: '443'), null);
  p['hy2-salamander-hop'] =
      (hy2('obfs=salamander&obfs-password=salamander-pass', port: '20000-30000'), null);
  p['hy2-salamander-short'] = (hy2('obfs=salamander&obfs-password=abc'), 'Salamander');
  p['hy2-salamander-no-password'] = (hy2('obfs=salamander'), 'obfs-password');
  p['hy2-obfs-unknown'] = (hy2('obfs=gecko&obfs-password=salamander-pass'), 'gecko');
  p['hy2-insecure'] = (hy2('insecure=1'), 'allowInsecure');
  return p;
}

VpnEngineOptions options({
  RoutingSettings routing = const RoutingSettings(),
  DnsMode dnsMode = DnsMode.proxy,
  DnsServerConfig dnsServer = DnsServerConfig.cloudflare,
  FragmentSettings fragment = const FragmentSettings(),
  NoiseSettings noise = const NoiseSettings(),
  bool blockQuic = false,
  bool enableUdp = true,
  TlsFingerprint fingerprint = TlsFingerprint.defaultFp,
}) => VpnEngineOptions(
  socksPort: 10808,
  httpPort: 0,
  socksUser: '',
  socksPassword: '',
  routing: routing,
  dnsMode: dnsMode,
  dnsServer: dnsServer,
  fragment: fragment,
  noise: noise,
  blockQuic: blockQuic,
  enableUdp: enableUdp,
  tlsFingerprint: fingerprint,
);

const fragmentOn = FragmentSettings(enabled: true);

/// Toggles exercised on every profile.
final toggles = <String, VpnEngineOptions Function()>{
  'default': () => options(),
  'fragment': () => options(fragment: fragmentOn),
  'fragment-tiny': () => options(
    fragment: const FragmentSettings(enabled: true, length: '1-3', interval: '900-1000'),
  ),
  'noise-rand': () => options(noise: const NoiseSettings(enabled: true)),
  'noise-str': () => options(
    noise: const NoiseSettings(enabled: true, type: NoiseType.str, packet: 'synthetic'),
  ),
  'noise-hex': () => options(
    noise: const NoiseSettings(enabled: true, type: NoiseType.hex, packet: '00ff10'),
  ),
  'noise-base64': () => options(
    noise: const NoiseSettings(enabled: true, type: NoiseType.base64, packet: 'AAEC'),
  ),
  'quic-block': () => options(blockQuic: true),
  'udp-off': () => options(enableUdp: false),
  'all-toggles': () => options(
    fragment: fragmentOn,
    noise: const NoiseSettings(enabled: true),
    blockQuic: true,
  ),
};

final routings = <String, RoutingSettings>{
  'global': const RoutingSettings(),
  'bypass-geo': const RoutingSettings(
    direction: RoutingDirection.bypass,
    bypassLocal: true,
    geoEnabled: true,
    geoCodes: ['RU'],
    geositeEnabled: true,
    geositeCodes: ['youtube'],
    sitesEnabled: true,
    sites: ['example.com'],
    ruServicesEnabled: true,
  ),
  'only-geo': const RoutingSettings(
    direction: RoutingDirection.onlySelected,
    geoEnabled: true,
    geoCodes: ['US'],
    geositeEnabled: true,
    geositeCodes: ['youtube'],
    domainEnabled: true,
    domainZones: ['example.org'],
  ),
  'bypass-ads': const RoutingSettings(
    direction: RoutingDirection.bypass,
    geositeEnabled: true,
    geositeCodes: ['youtube'],
    adBlockEnabled: true,
  ),
  'global-ads': const RoutingSettings(adBlockEnabled: true),
};

final dnsServers = <String, DnsServerConfig>{
  'udp': DnsServerConfig.cloudflare,
  'doh': DnsServerConfig.cloudflareDoH,
  'dot': DnsServerConfig.cloudflareDoT,
  'custom-dot-name': DnsServerConfig.fromPreset(
    'custom',
    customAddress: 'dns.example.net:5853',
    customType: DnsType.dot,
  ),
};

/// One representative per protocol for the routing × DNS × UDP axes.
const representatives = [
  'vless-tcp-reality-xtls-rprx-vision',
  'vless-xhttp-tls-h3',
  'trojan-grpc-tls',
  'vmess-ws-none',
  'ss-aes256',
  'hy2-salamander-hop',
];

void main() {
  test('export the Rust config matrix', () {
    final cases = <Map<String, Object?>>[];
    final links = profiles();
    void add(String name, String profile, String? expected, VpnEngineOptions Function() build) {
      final config = VlessParser.parseUri(links[profile]!.$1);
      final entry = <String, Object?>{'name': name, 'profile': profile, 'expect': expected};
      if (config == null) {
        entry['error'] = 'parser returned null';
      } else {
        final base = build();
        // The provider adds the -udp443 Vision QUIC block, as on the device.
        final opts = VpnEngineOptions(
          socksPort: base.socksPort,
          httpPort: base.httpPort,
          socksUser: base.socksUser,
          socksPassword: base.socksPassword,
          routing: base.routing,
          dnsMode: base.dnsMode,
          dnsServer: base.dnsServer,
          fragment: base.fragment,
          noise: base.noise,
          enableUdp: base.enableUdp,
          tlsFingerprint: base.tlsFingerprint,
          blockQuic: CoreFeatures.rust.effectiveQuicBlock(
            requested: base.blockQuic,
            flow: config.flow,
          ),
        );
        try {
          entry['config'] = RustConfigBuilder.buildJson(config, opts);
          // The switchConfig candidate variant of the same profile and options.
          entry['probe'] = RustConfigBuilder.buildProbeJson(config, opts);
        } on FormatException catch (e) {
          entry['error'] = e.message;
        }
      }
      cases.add(entry);
    }

    for (final profile in links.keys) {
      for (final toggle in toggles.entries) {
        add('$profile/${toggle.key}', profile, links[profile]!.$2, toggle.value);
      }
    }
    for (final profile in representatives) {
      for (final routing in routings.entries) {
        for (final dnsMode in DnsMode.values) {
          for (final dns in dnsServers.entries) {
            for (final udp in ['udp', 'quic-block', 'udp-off']) {
              add(
                '$profile/${routing.key}/${dnsMode.name}/${dns.key}/$udp',
                profile,
                links[profile]!.$2,
                () => options(
                  routing: routing.value,
                  dnsMode: dnsMode,
                  dnsServer: dns.value,
                  blockQuic: udp == 'quic-block',
                  enableUdp: udp != 'udp-off',
                ),
              );
            }
          }
        }
      }
    }
    for (final profile in [
      'vless-tcp-tls',
      'vless-tcp-reality',
      'trojan-tcp-tls',
      'trojan-xhttp-reality',
      'vmess-ws-tls',
    ]) {
      for (final fp in TlsFingerprint.values) {
        add('$profile/fp-${fp.name}', profile, links[profile]!.$2,
            () => options(fingerprint: fp, fragment: fragmentOn));
      }
    }
    File(Platform.environment['TEAPOD_MATRIX_OUTPUT']!)
        .writeAsStringSync(jsonEncode({'cases': cases}));
  });
}
