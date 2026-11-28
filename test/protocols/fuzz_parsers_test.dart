// Property tests of the parsers that read untrusted input: share links, subscription bodies, managed xray configs.
// Seeded random mutations of valid inputs; the seed and the number of cases come from the environment for a long
// local run: FUZZ_SEED=7 FUZZ_CASES=200000 flutter test test/protocols/fuzz_parsers_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/constants/xray_defaults.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/app_message.dart';
import 'package:teapodstream/core/models/routing_settings.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/models/vpn_log_entry.dart' show LogLevel;
import 'package:teapodstream/core/services/subscription_service.dart';
import 'package:teapodstream/protocols/xray/vless_parser.dart';
import 'package:teapodstream/protocols/xray/xray_config_builder.dart';

final _seed = int.tryParse(Platform.environment['FUZZ_SEED'] ?? '') ?? 20261128;
final _cases = int.tryParse(Platform.environment['FUZZ_CASES'] ?? '') ?? 3000;

const _uuid = '00000000-0000-4000-8000-000000000000';

final _vmessJson = {
  'v': '2',
  'ps': 'vm',
  'add': 'vm.example',
  'port': '443',
  'id': _uuid,
  'aid': '0',
  'net': 'ws',
  'type': 'none',
  'host': 'cdn.example',
  'path': '/ws',
  'tls': 'tls',
  'sni': 'vm.example',
};

final _links = [
  'vless://$_uuid@v.example:443?encryption=none&security=reality&sni=www.example&fp=chrome&pbk=AAAA&sid=ab&type=tcp&flow=xtls-rprx-vision#Reality',
  'vless://$_uuid@v.example:443?security=tls&type=ws&host=cdn.example&path=%2Fws%3Fed%3D2048&sni=v.example#WS',
  'vless://$_uuid@v.example:443?security=tls&type=grpc&serviceName=svc&mode=multi#gRPC',
  'vless://$_uuid@[2001:db8::1]:8443?security=tls&type=xhttp&path=%2Fx&mode=packet-up&extra=%7B%22xmux%22%3A%7B%7D%7D#XHTTP',
  'vmess://${base64Encode(utf8.encode(jsonEncode(_vmessJson)))}',
  'trojan://secret@t.example:443?security=tls&sni=t.example&type=tcp&alpn=h2%2Chttp%2F1.1#Trojan',
  'ss://${base64Encode(utf8.encode('chacha20-ietf-poly1305:pw'))}@s.example:8388#SS',
  'ss://2022-blake3-aes-128-gcm:${Uri.encodeComponent('AAAAAAAAAAAAAAAAAAAAAA==')}@s.example:8388?plugin=obfs-local%3Bobfs%3Dhttp#SS2022',
  'hy2://pass@hy.example:443,5000-6000/?sni=s&obfs=salamander&obfs-password=o&insecure=0#Hy2',
  'hysteria2://pass@hy.example:443?obfs=gecko&obfs-password=o&minPacketSize=300&maxPacketSize=900#Hy',
  'wireguard://${Uri.encodeComponent('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=')}@wg.example:51820?publickey=${Uri.encodeComponent('BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=')}&address=10.0.0.2%2F32&mtu=1420#WG',
  'ssh://user:pw@ssh.example:22#SSH',
  'naive+https://user:pw@n.example:443?padding=1#Naive',
];

const _wgConf = '''[Interface]
PrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
Address = 10.0.0.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=
AllowedIPs = 0.0.0.0/0
Endpoint = wg.example:51820
''';

final _managed = {
  'remarks': 'managed',
  'log': {'loglevel': 'warning'},
  'api': {
    'tag': 'api',
    'services': ['StatsService'],
  },
  'inbounds': [
    {'tag': 'socks', 'protocol': 'socks', 'listen': '0.0.0.0', 'port': 10808},
    {'tag': 'api', 'protocol': 'dokodemo-door', 'listen': '0.0.0.0', 'port': 10085},
  ],
  'outbounds': [
    {
      'tag': 'proxy-1',
      'protocol': 'vless',
      'settings': {
        'vnext': [
          {
            'address': 'm.example',
            'port': 443,
            'users': [
              {'id': _uuid, 'encryption': 'none'},
            ],
          },
        ],
      },
      'streamSettings': {
        'network': 'tcp',
        'security': 'tls',
        'tlsSettings': {'serverName': 'm.example', 'allowInsecure': true},
      },
    },
    {'tag': 'direct', 'protocol': 'freedom'},
    {'tag': 'block', 'protocol': 'blackhole'},
  ],
  'routing': {
    'balancers': [
      {
        'tag': 'b',
        'selector': ['proxy'],
        'fallbackTag': 'direct',
      },
    ],
    'rules': [
      {'type': 'field', 'balancerTag': 'b', 'network': 'tcp,udp'},
    ],
  },
  'observatory': {
    'subjectSelector': ['proxy'],
    'probeInterval': '10s',
  },
  'reverse': {'bridges': <Object>[]},
};

final _alphabet = <String>[
  ...'abcxyzAZ0129'.split(''),
  ...[':', '/', '@', '?', '&', '=', '#', '%', '[', ']', '.', ',', '-', '_', '+', '~', ' ', '\n', '\t', '"', "'"],
  ...['\\', '{', '}', '%00', '%zz', '%2', '%25', 'é', '中', '😀', '\u0000', '\uffff', '%F0%9F', '//', '::', '@@'],
];

/// One random edit of [s]: insert, delete, replace, truncate, duplicate a slice, or swap two halves.
String _mutate(Random r, String s) {
  if (s.isEmpty) return _alphabet[r.nextInt(_alphabet.length)];
  final i = r.nextInt(s.length);
  final j = (i + 1 + r.nextInt(min(16, s.length - i))).clamp(0, s.length);
  final piece = _alphabet[r.nextInt(_alphabet.length)];
  return switch (r.nextInt(6)) {
    0 => s.substring(0, i) + piece + s.substring(i),
    1 => s.substring(0, i) + s.substring(j),
    2 => s.substring(0, i) + piece + s.substring(j),
    3 => s.substring(0, i),
    4 => s.substring(0, j) + s.substring(i, j) + s.substring(j),
    _ => s.substring(i) + s.substring(0, i),
  };
}

String _mutateN(Random r, String s) {
  for (var n = 1 + r.nextInt(4); n > 0; n--) {
    s = _mutate(r, s);
  }
  return s;
}

/// A random JSON value for replacing a node of a managed config.
Object? _randomJson(Random r, int depth) => switch (r.nextInt(depth > 2 ? 6 : 8)) {
  0 => null,
  1 => r.nextBool(),
  2 => r.nextInt(1 << 20) - 1000,
  3 => '',
  4 => _alphabet[r.nextInt(_alphabet.length)] * (1 + r.nextInt(3)),
  5 => ['direct', 'freedom', 'socks', 'proxy', 'blackhole', 'tag', 'protocol', '0.0.0.0'][r.nextInt(8)],
  6 => [for (var k = r.nextInt(3); k > 0; k--) _randomJson(r, depth + 1)],
  _ => {
    for (var k = r.nextInt(3); k > 0; k--)
      ['tag', 'protocol', 'settings', 'selector', 'fallbackTag', 'rules', 'listen', 'port', 'api'][r.nextInt(9)]:
          _randomJson(r, depth + 1),
  },
};

/// [node] with one random node replaced, removed or added somewhere in its tree.
Object? _mutateJson(Random r, Object? node, int depth) {
  if (node is Map<String, dynamic> && node.isNotEmpty && r.nextInt(4) != 0) {
    final key = node.keys.elementAt(r.nextInt(node.length));
    final copy = Map<String, dynamic>.of(node);
    switch (r.nextInt(5)) {
      case 0:
        copy.remove(key);
      case 1:
        copy[key] = _randomJson(r, depth);
      case 2:
        copy[key.toUpperCase()] = copy[key];
      default:
        copy[key] = _mutateJson(r, node[key], depth + 1);
    }
    return copy;
  }
  if (node is List && node.isNotEmpty && r.nextInt(4) != 0) {
    final i = r.nextInt(node.length);
    final copy = List<Object?>.of(node);
    switch (r.nextInt(4)) {
      case 0:
        copy.removeAt(i);
      case 1:
        copy.insert(i, _randomJson(r, depth));
      default:
        copy[i] = _mutateJson(r, node[i], depth + 1);
    }
    return copy;
  }
  return _randomJson(r, depth);
}

/// The parser's contract: a config, null (not a link it reads) or a [ReasonException]; nothing else.
VpnConfig? _parse(String input) {
  try {
    return VlessParser.parseUri(input);
  } on ReasonException {
    return null;
  } catch (e, st) {
    fail('parseUri threw ${e.runtimeType} for ${jsonEncode(input)}: $e\n$st');
  }
}

void _expectRoundTrip(VpnConfig c, String input) {
  final json = jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>;
  final again = VpnConfig.fromJson(json).toJson();
  expect(jsonEncode(again), jsonEncode(json), reason: 'stored form of ${jsonEncode(input)} changed after a reload');
}

final _options = VpnEngineOptions(
  socksPort: 10808,
  socksUser: 'u',
  socksPassword: 'p',
  logLevel: LogLevel.warning,
  routing: const RoutingSettings(direction: RoutingDirection.bypass, bypassLocal: true),
);

const _allowedTopLevel = {
  'log',
  'dns',
  'routing',
  'inbounds',
  'outbounds',
  'policy',
  'stats',
  'fakedns',
  'fakeDns',
  'observatory',
  'burstObservatory',
  'version',
};

void main() {
  test('seed links parse and survive a reload', () {
    for (final link in [..._links, _wgConf]) {
      final c = VlessParser.parseUri(link);
      expect(c, isNotNull, reason: link);
      _expectRoundTrip(c!, link);
    }
  });

  test('mutated links give a config, null or a typed refusal; a config survives a reload', () {
    final r = Random(_seed);
    final seeds = [..._links, _wgConf];
    for (var n = 0; n < _cases; n++) {
      final input = _mutateN(r, seeds[r.nextInt(seeds.length)]);
      final c = _parse(input);
      if (c != null) _expectRoundTrip(c, input);
    }
  });

  test('mutated vmess JSON inside the link gives a config, null or a typed refusal', () {
    final r = Random(_seed + 1);
    for (var n = 0; n < _cases; n++) {
      final json = _mutateJson(r, _vmessJson, 0);
      final input = 'vmess://${base64Encode(utf8.encode(jsonEncode(json)))}';
      final c = _parse(input);
      if (c != null) _expectRoundTrip(c, input);
    }
  });

  test('a mutated subscription body never throws', () {
    final r = Random(_seed + 2);
    final plain = _links.join('\n');
    final bodies = [
      plain,
      base64Encode(utf8.encode(plain)),
      jsonEncode([_managed]),
      jsonEncode(_managed),
    ];
    for (var n = 0; n < _cases; n++) {
      final body = _mutateN(r, bodies[r.nextInt(bodies.length)]);
      try {
        for (final c in SubscriptionService.parseBody(body)) {
          _expectRoundTrip(c, body);
        }
      } catch (e, st) {
        if (e is TestFailure) rethrow;
        fail('parseBody threw ${e.runtimeType} for ${jsonEncode(body)}: $e\n$st');
      }
    }
  });

  test('a mutated managed config is refused or keeps the allowlist, our inbound and no direct fallback', () {
    final r = Random(_seed + 3);
    for (var n = 0; n < _cases; n++) {
      final raw = jsonEncode(_mutateJson(r, _managed, 0));
      final String merged;
      try {
        merged = XrayConfigBuilder.mergeWithRaw(raw, _options);
      } on ReasonException {
        continue;
      } catch (e, st) {
        fail('mergeWithRaw threw ${e.runtimeType} for $raw: $e\n$st');
      }
      final cfg = jsonDecode(merged) as Map<String, dynamic>;
      expect(_allowedTopLevel.containsAll(cfg.keys), isTrue, reason: 'top-level keys ${cfg.keys} from $raw');
      final inbounds = cfg['inbounds'] as List<dynamic>;
      expect(inbounds, hasLength(1), reason: raw);
      final inbound = inbounds.single as Map<String, dynamic>;
      expect((inbound['protocol'], inbound['listen'], inbound['port']), ('socks', XrayDefaults.socksListen, 10808));
      expect((inbound['settings'] as Map<String, dynamic>)['auth'], 'password', reason: raw);

      final outbounds = (cfg['outbounds'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>();
      final freedom = {
        for (final o in outbounds)
          if ('${o['protocol']}'.toLowerCase() == 'freedom')
            if (o['tag'] case final String t) t,
      };
      final routing = cfg['routing'];
      final balancers = routing is Map<String, dynamic> ? routing['balancers'] : null;
      if (balancers is List) {
        for (final b in balancers.whereType<Map<String, dynamic>>()) {
          expect(freedom.contains(b['fallbackTag']), isFalse, reason: 'balancer falls back to direct in $raw');
        }
      }
      for (final o in outbounds) {
        final tls = (o['streamSettings'] as Map<String, dynamic>?)?['tlsSettings'];
        if (tls is Map) expect(tls.containsKey('allowInsecure'), isFalse, reason: raw);
      }
    }
  });
}
