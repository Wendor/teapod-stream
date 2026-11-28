import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/protocols/xray/xray_config_builder.dart';
import 'package:teapodstream/protocols/xray/vless_parser.dart';
import 'package:teapodstream/core/models/app_message.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/models/routing_settings.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/dns_config.dart';
import 'package:teapodstream/core/models/vpn_log_entry.dart' show LogLevel;
import 'package:teapodstream/core/models/xray_tuning.dart';
import 'package:teapodstream/core/constants/routing_defaults.dart';

VpnConfig _vlessConfig({String address = '1.2.3.4', int port = 443}) => VpnConfig(
  id: 'id',
  name: 'test',
  protocol: VpnProtocol.vless,
  address: address,
  port: port,
  uuid: 'test-uuid',
  security: VpnSecurity.tls,
  transport: VpnTransport.tcp,
  createdAt: DateTime.now(),
);

VpnEngineOptions _defaultOptions({
  int socksPort = 10808,
  RoutingSettings? routing,
  bool sniffingEnabled = true,
  bool enableUdp = true,
}) => VpnEngineOptions(
  socksPort: socksPort,
  socksUser: '',
  socksPassword: '',
  routing: routing ?? const RoutingSettings(),
  sniffingEnabled: sniffingEnabled,
  enableUdp: enableUdp,
);

void main() {
  group('XrayConfigBuilder.build', () {
    test('generates required top-level keys', () {
      final json = XrayConfigBuilder.build(_vlessConfig(), _defaultOptions());
      expect(json.containsKey('log'), isTrue);
      expect(json.containsKey('dns'), isTrue);
      expect(json.containsKey('inbounds'), isTrue);
      expect(json.containsKey('outbounds'), isTrue);
      expect(json.containsKey('routing'), isTrue);
      expect(json.containsKey('policy'), isTrue);
    });

    test('custom DoT server keeps its own port and disables fallback', () {
      final dns = XrayConfigBuilder.buildDnsBlock(
        VpnEngineOptions(
          socksPort: 10808,
          socksUser: '',
          socksPassword: '',
          routing: const RoutingSettings(),
          dnsServer: DnsServerConfig.fromPreset('custom', customAddress: 'xbox-dns.ru', customType: DnsType.dot),
        ),
      );
      final servers = dns['servers'] as List;
      final main = servers.first as Map<String, dynamic>;
      expect(main['address'], 'tls://xbox-dns.ru');
      expect(main['port'], 853);
      expect(dns['disableFallback'], isTrue);
      // bootstrap resolves only the DoT hostname itself
      final bootstrap = servers.last as Map<String, dynamic>;
      expect(bootstrap['domains'], ['xbox-dns.ru']);
    });

    test('main DNS server stays first when adblock is enabled', () {
      final dns = XrayConfigBuilder.buildDnsBlock(
        _defaultOptions(routing: const RoutingSettings(adBlockEnabled: true)),
      );
      final servers = dns['servers'] as List;
      expect((servers.first as Map)['address'], isNot('rcode://success'));
      expect((servers.last as Map)['address'], 'rcode://success');
    });

    test('inbound socks uses correct port', () {
      final json = XrayConfigBuilder.build(_vlessConfig(), _defaultOptions(socksPort: 12345));
      final inbound = (json['inbounds'] as List).first as Map<String, dynamic>;
      expect(inbound['port'], 12345);
      expect(inbound['protocol'], 'socks');
    });

    test('inbound listen is 127.0.0.1', () {
      final json = XrayConfigBuilder.build(_vlessConfig(), _defaultOptions());
      final inbound = (json['inbounds'] as List).first as Map<String, dynamic>;
      expect(inbound['listen'], '127.0.0.1');
    });

    test('outbounds contain proxy, direct, dns-out', () {
      final json = XrayConfigBuilder.build(_vlessConfig(), _defaultOptions());
      final outbounds = json['outbounds'] as List;
      final tags = outbounds.map((o) => (o as Map)['tag']).toList();
      expect(tags, containsAll(['proxy', 'direct', 'dns-out']));
    });

    test('routing domainStrategy is IPIfNonMatch', () {
      final json = XrayConfigBuilder.build(_vlessConfig(), _defaultOptions());
      final routing = json['routing'] as Map<String, dynamic>;
      expect(routing['domainStrategy'], 'IPIfNonMatch');
    });

    group('sniffing routeOnly', () {
      // routeOnly is always true when sniffing is enabled — prevents xray from replacing
      // the connection destination with re-resolved domain (DNS leak / tun2socks breakage).
      test('is true by default (sniffing enabled)', () {
        final json = XrayConfigBuilder.build(_vlessConfig(), _defaultOptions());
        final inbound = (json['inbounds'] as List).first as Map<String, dynamic>;
        final sniffing = inbound['sniffing'] as Map<String, dynamic>;
        expect(sniffing['routeOnly'], isTrue);
      });

      test('is true when geo routing is active', () {
        final routing = const RoutingSettings(direction: RoutingDirection.bypass, geoEnabled: true, geoCodes: ['RU']);
        final json = XrayConfigBuilder.build(_vlessConfig(), _defaultOptions(routing: routing));
        final inbound = (json['inbounds'] as List).first as Map<String, dynamic>;
        final sniffing = inbound['sniffing'] as Map<String, dynamic>;
        expect(sniffing['routeOnly'], isTrue);
      });

      test('is absent when sniffing is disabled', () {
        final json = XrayConfigBuilder.build(_vlessConfig(), _defaultOptions(sniffingEnabled: false));
        final inbound = (json['inbounds'] as List).first as Map<String, dynamic>;
        final sniffing = inbound['sniffing'] as Map<String, dynamic>;
        expect(sniffing['enabled'], isFalse);
        expect(sniffing.containsKey('routeOnly'), isFalse);
      });
    });

    group('geo routing rules', () {
      test('no geo rules when routing is global', () {
        final json = XrayConfigBuilder.build(_vlessConfig(), _defaultOptions());
        final routing = json['routing'] as Map<String, dynamic>;
        final rules = routing['rules'] as List;
        // No rules with geo IPs when routing is global (only DNS + catch-all rules)
        final geoRules = rules
            .where(
              (r) =>
                  (r as Map).containsKey('ip') &&
                  ((r['ip'] as List).any((ip) => (ip as String).startsWith('geoip:') && ip != 'geoip:private')),
            )
            .toList();
        expect(geoRules, isEmpty);
      });

      test('bypass local adds private geoip rule', () {
        final routing = const RoutingSettings(
          direction: RoutingDirection.bypass,
          bypassLocal: true,
          geoEnabled: true,
          geoCodes: ['RU'],
        );
        final json = XrayConfigBuilder.build(_vlessConfig(), _defaultOptions(routing: routing));
        final rules = (json['routing'] as Map)['rules'] as List;
        final ips = rules
            .where((r) => (r as Map).containsKey('ip'))
            .map((r) => (r as Map)['ip'] as List)
            .expand((x) => x)
            .toList();
        expect(ips, contains('geoip:private'));
      });
    });

    group('VLESS outbound', () {
      test('uses vnext format with uuid', () {
        final json = XrayConfigBuilder.build(_vlessConfig(), _defaultOptions());
        final outbounds = json['outbounds'] as List;
        final proxy = outbounds.firstWhere((o) => (o as Map)['tag'] == 'proxy') as Map;
        final vnext = (proxy['settings'] as Map)['vnext'] as List;
        expect(vnext.first['address'], '1.2.3.4');
        expect((vnext.first['users'] as List).first['id'], 'test-uuid');
      });
    });

    group('Shadowsocks outbound', () {
      test('uses servers format with method and password', () {
        final config = VpnConfig(
          id: 'id',
          name: 'ss',
          protocol: VpnProtocol.shadowsocks,
          address: '1.2.3.4',
          port: 8388,
          uuid: '',
          security: VpnSecurity.none,
          transport: VpnTransport.tcp,
          method: 'chacha20-ietf-poly1305',
          password: 'secret',
          createdAt: DateTime.now(),
        );
        final json = XrayConfigBuilder.build(config, _defaultOptions());
        final outbounds = json['outbounds'] as List;
        final proxy = outbounds.firstWhere((o) => (o as Map)['tag'] == 'proxy') as Map;
        final servers = (proxy['settings'] as Map)['servers'] as List;
        expect(servers.first['method'], 'chacha20-ietf-poly1305');
        expect(servers.first['password'], 'secret');
      });
    });
  });

  group('XrayConfigBuilder.mergeWithRaw', () {
    Map<String, dynamic> rawManaged({String probeInterval = '30s', String? fallbackTag = 'direct'}) => {
      'inbounds': [
        {'tag': 'socks', 'protocol': 'socks', 'port': 1080},
      ],
      'outbounds': [
        {
          'tag': 'c1-a',
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {
                'address': 'srv',
                'port': 443,
                'users': [
                  {'id': 'u', 'flow': 'xtls-rprx-vision'},
                ],
              },
            ],
          },
        },
        {'tag': 'direct', 'protocol': 'freedom', 'settings': <String, dynamic>{}},
        {'tag': 'blocked', 'protocol': 'blackhole', 'settings': <String, dynamic>{}},
      ],
      'observatory': {
        'probeInterval': probeInterval,
        'probeUrl': 'https://www.cloudflare.com/cdn-cgi/trace',
        'subjectSelector': ['c1-'],
      },
      'routing': {
        'rules': [
          {'type': 'field', 'network': 'tcp,udp', 'balancerTag': 'lb'},
        ],
        'balancers': [
          {
            'tag': 'lb',
            'selector': ['c1-'],
            'fallbackTag': ?fallbackTag,
            'strategy': {'type': 'leastLoad'},
          },
        ],
      },
    };

    Map<String, dynamic> merge(Map<String, dynamic> raw, [VpnEngineOptions? options]) =>
        jsonDecode(XrayConfigBuilder.mergeWithRaw(jsonEncode(raw), options ?? _defaultOptions()))
            as Map<String, dynamic>;

    test('clamps aggressive observatory probeInterval to 600s', () {
      final cfg = merge(rawManaged(probeInterval: '30s'));
      expect((cfg['observatory'] as Map)['probeInterval'], '600s');
    });

    test('keeps probeInterval when already slow', () {
      final cfg = merge(rawManaged(probeInterval: '15m'));
      expect((cfg['observatory'] as Map)['probeInterval'], '15m');
    });

    test('rewrites freedom fallbackTag to first selector outbound', () {
      final cfg = merge(rawManaged());
      final balancer = ((cfg['routing'] as Map)['balancers'] as List).first as Map;
      expect(balancer['fallbackTag'], 'c1-a');
      final outbounds = cfg['outbounds'] as List;
      expect(outbounds.any((o) => (o as Map)['tag'] == XrayConfigBuilder.blackholeTag), isFalse);
    });

    test('rewrites freedom fallbackTag to blackhole when selector matches nothing', () {
      final raw = rawManaged();
      (((raw['routing'] as Map)['balancers'] as List).first as Map)['selector'] = ['nope-'];
      final cfg = merge(raw);
      final balancer = ((cfg['routing'] as Map)['balancers'] as List).first as Map;
      expect(balancer['fallbackTag'], XrayConfigBuilder.blackholeTag);
      final outbounds = cfg['outbounds'] as List;
      expect(
        outbounds.any((o) => (o as Map)['tag'] == XrayConfigBuilder.blackholeTag && o['protocol'] == 'blackhole'),
        isTrue,
      );
    });

    test('rewrites a freedom fallback whatever the letter case of its keys', () {
      final raw = rawManaged(fallbackTag: null);
      final balancer = ((raw['routing'] as Map)['balancers'] as List).first as Map<String, dynamic>;
      balancer
        ..remove('selector')
        ..['Selector'] = ['c1-']
        ..['FallbackTag'] = 'free';
      (raw['outbounds'] as List).add({'Tag': 'free', 'Protocol': 'freedom'});
      final cfg = merge(raw);
      final merged = ((cfg['routing'] as Map)['balancers'] as List).first as Map;
      expect(merged['fallbackTag'], 'c1-a');
      expect(merged.containsKey('FallbackTag'), isFalse);
    });

    test('reads inbound and outbound protocols in any letter case, as xray does', () {
      final raw = rawManaged();
      final outbounds = raw['outbounds'] as List;
      (outbounds[1] as Map)['protocol'] = 'Freedom';
      (outbounds[2] as Map)['protocol'] = 'BLACKHOLE';
      // A freedom/blackhole listed first under the selector's prefix is not a proxy for the fallback.
      outbounds.insert(0, {'tag': 'c1-0', 'protocol': 'Freedom'});
      (raw['inbounds'] as List).first = {'tag': 'in-socks', 'protocol': 'SOCKS', 'port': 1080};
      final cfg = merge(raw);
      final balancer = ((cfg['routing'] as Map)['balancers'] as List).first as Map;
      expect(balancer['fallbackTag'], 'c1-a');
      expect(((cfg['inbounds'] as List).first as Map)['tag'], 'in-socks');
      // The server's `direct` is a freedom: the app's direct rules use it, no second freedom is injected.
      final merged = (cfg['outbounds'] as List).cast<Map<String, dynamic>>();
      expect(merged.where((o) => o['protocol'] == 'freedom').map((o) => o['tag']), unorderedEquals(['c1-0', 'direct']));
      expect(merged.any((o) => o['tag'] == XrayConfigBuilder.directTag), isFalse);
    });

    test('refuses a balancer or outbound with two spellings of a key it reads', () {
      final raw = rawManaged();
      (((raw['routing'] as Map)['balancers'] as List).first as Map)['Selector'] = ['t'];
      expect(
        () => merge(raw),
        throwsA(isA<ReasonException>().having((e) => '${e.reason}', 'reason', contains('(selector, Selector)'))),
      );
      final outbound = rawManaged();
      ((outbound['outbounds'] as List).first as Map)['TAG'] = 'other';
      expect(() => merge(outbound), throwsFormatException);
    });

    test('keeps fallbackTag pointing to non-freedom outbound', () {
      final cfg = merge(rawManaged(fallbackTag: 'blocked'));
      final balancer = ((cfg['routing'] as Map)['balancers'] as List).first as Map;
      expect(balancer['fallbackTag'], 'blocked');
      final outbounds = cfg['outbounds'] as List;
      expect(outbounds.any((o) => (o as Map)['tag'] == XrayConfigBuilder.blackholeTag), isFalse);
    });

    test('handles config without balancers', () {
      final raw = rawManaged()..remove('routing');
      final cfg = merge(raw);
      expect(cfg['outbounds'], isNotEmpty);
    });

    test('adds adblock routing rule to blackhole when enabled', () {
      final cfg = merge(rawManaged(), _defaultOptions(routing: const RoutingSettings(adBlockEnabled: true)));
      final rules = (cfg['routing'] as Map)['rules'] as List;
      final adRule = rules.cast<Map<String, dynamic>>().firstWhere(
        (r) => (r['domain'] as List?)?.contains('geosite:category-ads-all') ?? false,
      );
      expect(adRule['outboundTag'], XrayConfigBuilder.blackholeTag);
      // App rules must come before server rules (first-match wins).
      expect(rules.indexOf(adRule), lessThan(rules.indexWhere((r) => (r as Map).containsKey('balancerTag'))));
    });

    test('no adblock rule when disabled', () {
      final cfg = merge(rawManaged());
      final rules = (cfg['routing'] as Map)['rules'] as List;
      expect(
        rules.cast<Map<String, dynamic>>().any(
          (r) => (r['domain'] as List?)?.contains('geosite:category-ads-all') ?? false,
        ),
        isFalse,
      );
    });
  });

  group('routing rules', () {
    List<Map<String, dynamic>> rulesFor(RoutingSettings routing) {
      final json = XrayConfigBuilder.build(_vlessConfig(), _defaultOptions(routing: routing));
      final r = (json['routing'] as Map<String, dynamic>)['rules'] as List;
      return r.cast<Map<String, dynamic>>();
    }

    test('sites alone produce a domain rule to the selected outbound', () {
      final rules = rulesFor(
        const RoutingSettings(direction: RoutingDirection.bypass, sitesEnabled: true, sites: ['example.com']),
      );
      expect(rules.any((r) => (r['domain'] as List?)?.contains('domain:example.com') ?? false), isTrue);
    });

    test('ru services alone produce a domain rule to the selected outbound', () {
      final rules = rulesFor(const RoutingSettings(direction: RoutingDirection.bypass, ruServicesEnabled: true));
      expect(rules.where((r) => r['domain'] != null && r['outboundTag'] == 'direct'), isNotEmpty);
    });
  });

  group('UDP off', () {
    const block = {'type': 'field', 'network': 'udp', 'port': '1-52,54-65535'};

    test('build keeps SOCKS UDP for DNS and blocks the rest after the DNS rule', () {
      final json = XrayConfigBuilder.build(_vlessConfig(), _defaultOptions(enableUdp: false));
      expect(json['inbounds'][0]['settings']['udp'], isTrue);
      final rules = (json['routing']['rules'] as List).cast<Map<String, dynamic>>();
      final dns = rules.indexWhere((r) => r['outboundTag'] == 'dns-out');
      expect(rules[dns + 1], {
        ...block,
        'inboundTag': ['socks-in'],
        'outboundTag': 'block',
      });
    });

    test('build adds no UDP rule when UDP is on', () {
      final json = XrayConfigBuilder.build(_vlessConfig(), _defaultOptions());
      expect((json['routing']['rules'] as List).where((r) => r['network'] == 'udp'), isEmpty);
    });

    test('mergeWithRaw blocks non-DNS UDP of the managed socks inbound', () {
      final raw = {
        'inbounds': [
          {'tag': 'socks', 'protocol': 'socks', 'port': 1080},
        ],
        'outbounds': [
          {'tag': 'proxy', 'protocol': 'freedom'},
        ],
      };
      final cfg =
          jsonDecode(XrayConfigBuilder.mergeWithRaw(jsonEncode(raw), _defaultOptions(enableUdp: false)))
              as Map<String, dynamic>;
      expect(cfg['inbounds'][0]['settings']['udp'], isTrue);
      expect(
        cfg['routing']['rules'],
        contains(
          equals({
            ...block,
            'inboundTag': ['socks'],
            'outboundTag': XrayConfigBuilder.blackholeTag,
          }),
        ),
      );
      expect((cfg['outbounds'] as List).map((o) => o['tag']), contains(XrayConfigBuilder.blackholeTag));
    });

    test('mergeWithRaw puts the UDP block before server rules that route UDP to freedom', () {
      final raw = {
        'inbounds': [
          {'tag': 'socks', 'protocol': 'socks', 'port': 1080},
        ],
        'outbounds': [
          {'tag': 'out', 'protocol': 'freedom'},
        ],
        'routing': {
          'rules': [
            {'type': 'field', 'network': 'tcp,udp', 'outboundTag': 'out'},
          ],
        },
      };
      final cfg =
          jsonDecode(XrayConfigBuilder.mergeWithRaw(jsonEncode(raw), _defaultOptions(enableUdp: false)))
              as Map<String, dynamic>;
      final rules = (cfg['routing']['rules'] as List).cast<Map<String, dynamic>>();
      final blockAt = rules.indexWhere((r) => r['outboundTag'] == XrayConfigBuilder.blackholeTag);
      final serverAt = rules.indexWhere((r) => r['outboundTag'] == 'out');
      expect(blockAt, greaterThanOrEqualTo(0));
      expect(blockAt, lessThan(serverAt));
      expect(rules[blockAt], {
        ...block,
        'inboundTag': ['socks'],
        'outboundTag': XrayConfigBuilder.blackholeTag,
      });
      final bh = (cfg['outbounds'] as List).firstWhere((o) => o['tag'] == XrayConfigBuilder.blackholeTag);
      expect(bh['protocol'], 'blackhole');
    });

    test('mergeWithRaw sends the direct rules to a direct freedom that exists', () {
      const bypass = RoutingSettings(bypassLocal: true);
      List<Map<String, dynamic>> outbounds(Map<String, dynamic> cfg) =>
          (cfg['outbounds'] as List).cast<Map<String, dynamic>>();
      String privateTag(Map<String, dynamic> cfg) =>
          ((cfg['routing']['rules'] as List).cast<Map<String, dynamic>>().firstWhere(
                    (r) => (r['ip'] as List?)?.contains('geoip:private') ?? false,
                  )
                  as Map)['outboundTag']
              as String;
      Map<String, dynamic> merge(List<Map<String, Object>> serverOutbounds, RoutingSettings routing) =>
          jsonDecode(
                XrayConfigBuilder.mergeWithRaw(
                  jsonEncode({
                    'outbounds': [
                      {'tag': 'node', 'protocol': 'vless'},
                      ...serverOutbounds,
                    ],
                  }),
                  _defaultOptions(routing: routing),
                ),
              )
              as Map<String, dynamic>;

      // The server's own direct freedom is used as is.
      final own = merge([
        {'tag': 'direct', 'protocol': 'freedom'},
      ], bypass);
      expect(privateTag(own), 'direct');
      expect(outbounds(own).map((o) => o['tag']), ['node', 'direct']);

      // No direct outbound, or a direct of another protocol: a freedom of the app's own.
      final none = merge([], bypass);
      expect(privateTag(none), XrayConfigBuilder.directTag);
      expect(outbounds(none).last, {
        'tag': XrayConfigBuilder.directTag,
        'protocol': 'freedom',
        'settings': <String, dynamic>{},
      });
      final taken = merge([
        {'tag': 'direct', 'protocol': 'blackhole'},
      ], bypass);
      expect(privateTag(taken), XrayConfigBuilder.directTag);
      expect(outbounds(taken).firstWhere((o) => o['tag'] == 'direct')['protocol'], 'blackhole');

      // No direct rule — nothing added.
      expect(outbounds(merge([], const RoutingSettings(bypassLocal: false))).map((o) => o['tag']), ['node']);
    });

    test('mergeWithRaw keeps injected outbounds out of server balancers and reads keys in any case', () {
      Map<String, dynamic> merge(Map<String, Object> raw) =>
          jsonDecode(
                XrayConfigBuilder.mergeWithRaw(
                  jsonEncode(raw),
                  _defaultOptions(routing: const RoutingSettings(bypassLocal: true)),
                ),
              )
              as Map<String, dynamic>;
      Map<String, Object> raw(List<Object> selector, [List<Map<String, Object>> extra = const []]) => {
        'outbounds': [
          {'tag': 'node', 'protocol': 'vless'},
          ...extra,
        ],
        'routing': {
          'balancers': [
            {'tag': 'lb', 'selector': selector},
          ],
        },
      };
      String privateTag(Map<String, dynamic> cfg) =>
          ((cfg['routing']['rules'] as List).cast<Map<String, dynamic>>().firstWhere(
                    (r) => (r['ip'] as List?)?.contains('geoip:private') ?? false,
                  )
                  as Map)['outboundTag']
              as String;
      List<Object?> selector(Map<String, dynamic> cfg) => cfg['routing']['balancers'][0]['selector'] as List;

      // A selector prefix that matches the injected tag: the tag moves out of its reach.
      for (final prefix in ['t', 'teapod', 'teapod-direct']) {
        final cfg = merge(raw([prefix, 'node']));
        final tag = privateTag(cfg);
        expect(tag.startsWith(prefix), isFalse, reason: prefix);
        expect((cfg['outbounds'] as List).last, {'tag': tag, 'protocol': 'freedom', 'settings': <String, dynamic>{}});
      }
      // An empty selector matches every tag: it becomes all the server's tags, also ones like the app's.
      final all = merge(
        raw(
          [''],
          [
            {'tag': 'teapod-direct-east', 'protocol': 'vless'},
            {'tag': 'teapod-blackhole-west', 'protocol': 'vless'},
          ],
        ),
      );
      expect(selector(all), ['node', 'teapod-direct-east', 'teapod-blackhole-west']);
      expect(privateTag(all), XrayConfigBuilder.directTag);
      expect(selector(all).whereType<String>().any(privateTag(all).startsWith), isFalse);
      // Untagged outbounds aren't balanced: an empty tag isn't a candidate, and with none tagged the selector
      // matches nothing (xray refuses an empty list) while the injected tag stays out of it.
      final untagged = merge({
        'outbounds': [
          {'tag': '', 'protocol': 'vless'},
          {'protocol': 'vless'},
        ],
        'routing': {
          'balancers': [
            {
              'tag': 'lb',
              'selector': [''],
            },
          ],
        },
      });
      expect(selector(untagged), hasLength(1));
      expect(selector(untagged).single, isNot(''));
      expect(privateTag(untagged), XrayConfigBuilder.directTag);

      // Xray reads `Tag` / `Protocol` as tag / protocol: a server direct freedom written so is used, and a tag taken
      // so isn't added a second time.
      final upper = merge(
        raw(
          ['node'],
          [
            {'Tag': 'direct', 'Protocol': 'freedom'},
          ],
        ),
      );
      expect(privateTag(upper), 'direct');
      expect((upper['outbounds'] as List), hasLength(2));
      final taken = merge(
        raw(
          ['node'],
          [
            {'Tag': XrayConfigBuilder.directTag, 'protocol': 'blackhole'},
          ],
        ),
      );
      expect(privateTag(taken), '${XrayConfigBuilder.directTag}-2');

      // A tag the server already names without an outbound (a fallback, a rule) isn't taken: the reference would
      // start pointing to an injected freedom.
      final named = raw(['node']);
      ((named['routing'] as Map)['balancers'] as List).first['fallbackTag'] = XrayConfigBuilder.directTag;
      (named['routing'] as Map)['rules'] = [
        {'type': 'field', 'network': 'udp', 'outboundTag': '${XrayConfigBuilder.directTag}-2'},
      ];
      final avoided = merge(named);
      expect(privateTag(avoided), '${XrayConfigBuilder.directTag}-3');
      expect(avoided['routing']['balancers'][0]['fallbackTag'], XrayConfigBuilder.directTag);
    });

    test('mergeWithRaw keeps a server outbound that took our tag and blocks UDP via a free tag', () {
      const tag = XrayConfigBuilder.blackholeTag;
      final serverRule = {'type': 'field', 'network': 'tcp', 'outboundTag': tag};
      final raw = {
        'inbounds': [
          {'tag': 'socks', 'protocol': 'socks', 'port': 1080},
        ],
        'outbounds': [
          {'tag': tag, 'protocol': 'freedom'},
        ],
        'routing': {
          'rules': [serverRule],
        },
      };
      final cfg =
          jsonDecode(XrayConfigBuilder.mergeWithRaw(jsonEncode(raw), _defaultOptions(enableUdp: false)))
              as Map<String, dynamic>;
      final protocols = {for (final o in cfg['outbounds'] as List) o['tag']: o['protocol']};
      expect(protocols[tag], 'freedom');
      expect(protocols['$tag-2'], 'blackhole');
      final rules = cfg['routing']['rules'] as List;
      expect(rules, contains(equals(serverRule)));
      expect(
        rules,
        contains(
          equals({
            ...block,
            'inboundTag': ['socks'],
            'outboundTag': '$tag-2',
          }),
        ),
      );
    });
  });

  group('certificate pins', () {
    final hex = List.generate(32, (i) => i.toRadixString(16).padLeft(2, '0')).join();
    final colon = List.generate(32, (i) => i.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');
    final b64 = base64.encode(List.generate(32, (i) => i));

    test('colon hex becomes lowercase hex', () {
      expect(XrayConfigBuilder.certificatePins(colon), hex);
    });
    test('base64 of 32 bytes becomes hex', () {
      expect(XrayConfigBuilder.certificatePins(b64), hex);
    });
    test('comma list keeps every pin', () {
      expect(XrayConfigBuilder.certificatePins('$colon, $b64'), '$hex,$hex');
    });
    test('garbage is rejected', () {
      expect(() => XrayConfigBuilder.certificatePins('garbage'), throwsFormatException);
    });

    Map<String, dynamic> tlsOf(VpnConfig c) {
      final json = XrayConfigBuilder.build(c, _defaultOptions());
      final proxy = (json['outbounds'] as List).cast<Map<String, dynamic>>().firstWhere((o) => o['tag'] == 'proxy');
      return (proxy['streamSettings'] as Map<String, dynamic>)['tlsSettings'] as Map<String, dynamic>;
    }

    test('TLS pin wins over allowInsecure', () {
      final tls = tlsOf(
        VpnConfig(
          id: 'p',
          name: 'p',
          protocol: VpnProtocol.vless,
          address: 'h',
          port: 443,
          uuid: 'u',
          security: VpnSecurity.tls,
          transport: VpnTransport.tcp,
          createdAt: DateTime(2026),
          allowInsecure: true,
          pinSHA256: colon,
        ),
      );
      expect(tls['pinnedPeerCertSha256'], hex);
      expect(tls['allowInsecure'], isFalse);
      expect(tls.containsKey('pinnedPeerCertificateChainSha256'), isFalse);
    });

    test('Hysteria2 pin wins over allowInsecure', () {
      final tls = tlsOf(
        VpnConfig(
          id: 'p',
          name: 'p',
          protocol: VpnProtocol.hysteria2,
          address: 'h',
          port: 443,
          uuid: '',
          password: 'pw',
          security: VpnSecurity.tls,
          transport: VpnTransport.tcp,
          createdAt: DateTime(2026),
          allowInsecure: true,
          pinSHA256: hex,
        ),
      );
      expect(tls['pinnedPeerCertSha256'], hex);
      expect(tls['allowInsecure'], isFalse);
      expect(tls.containsKey('pinnedPeerCertificateChainSha256'), isFalse);
    });
  });
  group('hysteria2 hopping', () {
    group('Hysteria2 outbound', () {
      Map<String, dynamic> stream(String uri) {
        final json = XrayConfigBuilder.build(VlessParser.parseUri(uri)!, _defaultOptions());
        final proxy = (json['outbounds'] as List).firstWhere((o) => (o as Map)['tag'] == 'proxy') as Map;
        return proxy['streamSettings'] as Map<String, dynamic>;
      }

      test('a single port emits no finalmask (unchanged)', () {
        expect(stream('hy2://pass@hy.example:443?sni=s').containsKey('finalmask'), isFalse);
        expect(stream('hy2://pass@hy.example:443?obfs=salamander&obfs-password=o')['finalmask'], {
          'udp': [
            {
              'type': 'salamander',
              'settings': {'password': 'o'},
            },
          ],
        });
      });

      test('Gecko is the salamander mask with a packetSize range', () {
        expect(stream('hy2://pass@hy.example:443?obfs=gecko&obfs-password=o')['finalmask'], {
          'udp': [
            {
              'type': 'salamander',
              'settings': {'password': 'o', 'packetSize': '512-1200'},
            },
          ],
        });
        expect(
          stream(
            'hy2://pass@hy.example:443?obfs=gecko&obfs-password=o&minPacketSize=700&maxPacketSize=900',
          )['finalmask'],
          {
            'udp': [
              {
                'type': 'salamander',
                'settings': {'password': 'o', 'packetSize': '700-900'},
              },
            ],
          },
        );
      });

      test('port range becomes the udphop mask (first in udp) with the first port as settings.port', () {
        final json = XrayConfigBuilder.build(
          VlessParser.parseUri('hy2://pass@hy.example:20000-30000/?sni=s')!,
          _defaultOptions(),
        );
        final proxy = (json['outbounds'] as List).firstWhere((o) => (o as Map)['tag'] == 'proxy') as Map;
        expect(proxy['settings']['port'], 20000);
        expect(proxy['streamSettings']['finalmask'], {
          'udp': [
            {
              'type': 'udphop',
              'settings': {'mode': 'intervalLocal,intervalRemote', 'remotePorts': '20000-30000'},
            },
          ],
        });
        expect(stream('hy2://pass@hy.example:443,5000-6000?obfs=salamander&obfs-password=o')['finalmask'], {
          'udp': [
            {
              'type': 'udphop',
              'settings': {'mode': 'intervalLocal,intervalRemote', 'remotePorts': '443,5000-6000'},
            },
            {
              'type': 'salamander',
              'settings': {'password': 'o'},
            },
          ],
        });
        expect(stream('hy2://pass@hy.example:443?mport=20000-30000')['finalmask'], {
          'udp': [
            {
              'type': 'udphop',
              'settings': {'mode': 'intervalLocal,intervalRemote', 'remotePorts': '20000-30000'},
            },
          ],
        });
      });

      test('hop spec survives toJson/fromJson', () {
        final config = VlessParser.parseUri('hy2://pass@hy.example:443,5000-6000/?sni=s')!;
        final restored = VpnConfig.fromJsonString(config.toJsonString());
        expect(restored.hopPorts, '443,5000-6000');
        expect(restored.port, 443);
        expect(restored.copyWith(name: 'renamed').hopPorts, '443,5000-6000');
        expect(
          XrayConfigBuilder.buildJson(restored, _defaultOptions()),
          XrayConfigBuilder.buildJson(config, _defaultOptions()),
        );
        final legacy = config.toJson()..remove('hopPorts');
        expect(VpnConfig.fromJson(legacy).hopPorts, isNull);
      });
    });
  });

  test('access log only at debug level', () {
    Map<String, dynamic> logOf(LogLevel level) =>
        XrayConfigBuilder.build(
              _vlessConfig(),
              VpnEngineOptions(socksPort: 1, socksUser: '', socksPassword: '', logLevel: level),
            )['log']
            as Map<String, dynamic>;
    expect(logOf(LogLevel.debug).containsKey('access'), isFalse);
    for (final level in [LogLevel.info, LogLevel.warning, LogLevel.error]) {
      expect(logOf(level)['access'], 'none', reason: level.name);
    }
  });

  group('Xray-core v26 compatibility (Go)', () {
    VpnConfig link(String uri) => VlessParser.parseUri(uri)!;
    Map<String, dynamic> streamOf(VpnConfig c) {
      final json = XrayConfigBuilder.build(c, _defaultOptions());
      final proxy = (json['outbounds'] as List).cast<Map<String, dynamic>>().firstWhere((o) => o['tag'] == 'proxy');
      return proxy['streamSettings'] as Map<String, dynamic>;
    }

    test('profiles with removed features are reported, not started', () {
      expect('${XrayConfigBuilder.unsupportedReason(link('hy2://pw@h:443?insecure=1#n'))}', contains('allowInsecure'));
      expect(
        '${XrayConfigBuilder.unsupportedReason(link('vless://u@h:443?security=tls&type=h2#n'))}',
        contains('HTTP/2'),
      );
      expect(
        '${XrayConfigBuilder.unsupportedReason(link('vless://u@h:443?security=tls&type=quic#n'))}',
        contains('QUIC'),
      );
      expect(XrayConfigBuilder.unsupportedReason(link('vless://u@h:443?security=tls&pinSHA256=zz#n')), isNotNull);
      expect(XrayConfigBuilder.unsupportedReason(link('vless://u@h:443?security=tls&type=ws#n')), isNull);
    });

    test('a Shadowsocks link with a plugin is refused, as the other cores do', () {
      const key = 'Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpwdw';
      expect(
        '${XrayConfigBuilder.unsupportedReason(link('ss://$key@h:8388/?plugin=obfs-local%3Bobfs%3Dhttp#n'))}',
        contains('plugin'),
      );
      expect(XrayConfigBuilder.unsupportedReason(link('ss://$key@h:8388#n')), isNull);
    });

    test('ECH goes to tlsSettings.echConfigList', () {
      final tls = streamOf(link('vless://u@h:443?security=tls&ech=AEX%2B#n'))['tlsSettings'] as Map;
      expect(tls['echConfigList'], 'AEX+');
      expect(tls.containsKey('echSettings'), isFalse);
    });

    test('WebSocket Host goes to wsSettings.host, not the deprecated headers; none without a host', () {
      expect(streamOf(link('vless://u@h:443?security=tls&type=ws&host=edge.example&path=%2Fws#n'))['wsSettings'], {
        'path': '/ws',
        'host': 'edge.example',
      });
      expect(streamOf(link('vless://u@h:443?security=tls&type=ws#n'))['wsSettings'], {'path': '/'});
    });

    test('ruServicesDomains uses only the prefixes every core reads (sing-box: domain: and full:)', () {
      for (final d in RoutingDefaults.ruServicesDomains) {
        expect(d.startsWith('domain:') || d.startsWith('full:'), isTrue, reason: d);
      }
    });

    test('TCP HTTP header from headerType / VMess type', () {
      final vless = streamOf(link('vless://u@h:80?type=tcp&headerType=http&host=a.com,b.com&path=%2Fx#n'));
      expect(vless['tcpSettings'], {
        'header': {
          'type': 'http',
          'request': {
            'path': ['/x'],
            'headers': {
              'Host': ['a.com', 'b.com'],
            },
          },
        },
      });
      final vmessBody = base64.encode(
        utf8.encode(
          jsonEncode({
            'v': '2',
            'ps': 'n',
            'add': 'h',
            'port': '80',
            'id': 'u',
            'net': 'tcp',
            'type': 'http',
            'host': 'c.com',
          }),
        ),
      );
      final vmess = streamOf(link('vmess://$vmessBody'));
      expect((vmess['tcpSettings'] as Map)['header']['request']['path'], ['/']);
      expect(streamOf(link('vless://u@h:443?type=tcp&security=tls#n')).containsKey('tcpSettings'), isFalse);
    });

    test('mergeWithRaw drops api/metrics and allowInsecure, fails closed', () {
      final raw = {
        'api': {
          'listen': '127.0.0.1:10085',
          'services': ['HandlerService'],
        },
        'metrics': {'listen': '127.0.0.1:11111'},
        'inbounds': [
          {'tag': 'socks', 'protocol': 'socks', 'listen': '0.0.0.0', 'port': 1080},
        ],
        'outbounds': [
          {
            'tag': 'proxy',
            'protocol': 'vless',
            'streamSettings': {
              'security': 'tls',
              'tlsSettings': {'serverName': 's', 'allowInsecure': true},
            },
          },
        ],
      };
      final cfg = jsonDecode(XrayConfigBuilder.mergeWithRaw(jsonEncode(raw), _defaultOptions())) as Map;
      expect(cfg.containsKey('api'), isFalse);
      expect(cfg.containsKey('metrics'), isFalse);
      expect(cfg['outbounds'][0]['streamSettings']['tlsSettings'], {'serverName': 's'});
      expect(cfg['inbounds'][0]['listen'], '127.0.0.1');
      expect(() => XrayConfigBuilder.mergeWithRaw('{"inbounds": {}}', _defaultOptions()), throwsFormatException);
    });

    test('mergeWithRaw keeps only the client sections and drops reverse from outbounds', () {
      final raw = {
        'log': {'loglevel': 'debug'},
        'Inbounds': [
          {'tag': 'x', 'protocol': 'socks', 'listen': '0.0.0.0', 'port': 1081},
        ],
        'inbounds': [
          {'tag': 'socks', 'protocol': 'socks', 'listen': '0.0.0.0', 'port': 1080},
        ],
        'dns': {
          'servers': ['1.1.1.1'],
        },
        'routing': {'rules': <Object>[]},
        'policy': {'levels': <String, Object>{}},
        'stats': <String, Object>{},
        'fakedns': [
          {'ipPool': '198.18.0.0/15', 'poolSize': 65535},
        ],
        'observatory': {
          'subjectSelector': ['p'],
        },
        'burstObservatory': {
          'subjectSelector': ['p'],
        },
        'reverse': {
          'bridges': [
            {'tag': 'b', 'domain': 'r.example'},
          ],
        },
        'Reverse': <String, Object>{},
        'env': {'k': 'v'},
        'geodata': {'outbound': 'direct'},
        'transport': <String, Object>{},
        'outbounds': [
          {
            'tag': 'p',
            'protocol': 'vless',
            'settings': {
              'address': 's.example',
              'port': 443,
              'id': 'u',
              'encryption': 'none',
              'reverse': {'tag': 'r'},
              'Reverse': {'tag': 'r'},
            },
          },
          {
            'tag': 'v',
            'protocol': 'vless',
            'Settings': {
              'Vnext': [
                {
                  'address': 's.example',
                  'port': 443,
                  'Users': [
                    {
                      'id': 'u',
                      'encryption': 'none',
                      'reverse': {'tag': 'r'},
                    },
                  ],
                },
              ],
            },
          },
          {'tag': 'direct', 'protocol': 'freedom'},
        ],
      };
      final cfg = jsonDecode(XrayConfigBuilder.mergeWithRaw(jsonEncode(raw), _defaultOptions())) as Map;
      expect(cfg.keys.toSet(), {
        'log',
        'inbounds',
        'dns',
        'routing',
        'policy',
        'stats',
        'fakedns',
        'observatory',
        'burstObservatory',
        'outbounds',
      });
      expect(cfg['inbounds'], hasLength(1));
      expect(cfg['inbounds'][0]['listen'], '127.0.0.1');
      expect(cfg['outbounds'][0]['settings'], {'address': 's.example', 'port': 443, 'id': 'u', 'encryption': 'none'});
      expect(cfg['outbounds'][1]['Settings']['Vnext'][0]['Users'][0], {'id': 'u', 'encryption': 'none'});
      expect(cfg['dns'], raw['dns']);
    });
  });

  group('Mux from the link', () {
    const base =
        'vless://11111111-2222-4333-8444-555555555555@cdn.example:443?security=tls&sni=cdn.example&encryption=none';
    Map<String, dynamic>? mux(String query, VpnEngineOptions options) {
      final json = XrayConfigBuilder.build(VlessParser.parseUri('$base$query#x')!, options);
      final proxy = (json['outbounds'] as List).firstWhere((o) => (o as Map)['tag'] == 'proxy') as Map;
      return proxy['mux'] as Map<String, dynamic>?;
    }

    final globalOn = _defaultOptions().copyWith(mux: const MuxSettings(enabled: true, concurrency: 16));

    test('mux=on turns Mux on over xhttp, which the global setting skips', () {
      expect(mux('&type=xhttp&path=%2Fs', globalOn), isNull);
      expect(mux('&type=xhttp&path=%2Fs&mux=on', _defaultOptions()), {
        'enabled': true,
        'concurrency': 8,
        'xudpConcurrency': 16,
        'xudpProxyUDP443': 'reject',
      });
      expect(mux('&type=xhttp&path=%2Fs&mux=true', globalOn)?['concurrency'], 16);
    });

    test('mux=off turns the global Mux off for one server', () {
      expect(mux('&type=ws&path=%2Fs', globalOn), isNotNull);
      expect(mux('&type=ws&path=%2Fs&mux=off', globalOn), isNull);
      expect(mux('&type=ws&path=%2Fs&mux=0', globalOn), isNull);
    });

    test('an unknown value leaves the global setting', () {
      expect(mux('&type=ws&path=%2Fs&mux=maybe', globalOn), isNotNull);
      expect(mux('&type=ws&path=%2Fs&mux=maybe', _defaultOptions()), isNull);
    });

    test('Hysteria2 never gets Mux', () {
      final json = XrayConfigBuilder.build(
        VlessParser.parseUri('hy2://pass@hy.example:443/?sni=s&mux=on#x')!,
        globalOn,
      );
      final proxy = (json['outbounds'] as List).firstWhere((o) => (o as Map)['tag'] == 'proxy') as Map;
      expect(proxy.containsKey('mux'), isFalse);
    });
  });
}
