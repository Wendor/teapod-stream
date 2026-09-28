import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/protocols/xray/xray_config_builder.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/models/routing_settings.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/dns_config.dart';

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
}) => VpnEngineOptions(
  socksPort: socksPort,
  httpPort: 0,
  socksUser: '',
  socksPassword: '',
  routing: routing ?? const RoutingSettings(),
  sniffingEnabled: sniffingEnabled,
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
      final dns = XrayConfigBuilder.buildDnsBlock(VpnEngineOptions(
        socksPort: 10808,
        httpPort: 0,
        socksUser: '',
        socksPassword: '',
        routing: const RoutingSettings(),
        dnsServer: DnsServerConfig.fromPreset('custom',
            customAddress: 'xbox-dns.ru', customType: DnsType.dot),
      ));
      final servers = dns['servers'] as List;
      final main = servers.last as Map<String, dynamic>;
      expect(main['address'], 'tls://xbox-dns.ru');
      expect(main['port'], 853);
      expect(dns['disableFallback'], isTrue);
      // bootstrap resolves only the DoT hostname itself
      final bootstrap = servers.first as Map<String, dynamic>;
      expect(bootstrap['domains'], ['xbox-dns.ru']);
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
        final routing = const RoutingSettings(
          direction: RoutingDirection.bypass,
          geoEnabled: true,
          geoCodes: ['RU'],
        );
        final json = XrayConfigBuilder.build(_vlessConfig(), _defaultOptions(routing: routing));
        final inbound = (json['inbounds'] as List).first as Map<String, dynamic>;
        final sniffing = inbound['sniffing'] as Map<String, dynamic>;
        expect(sniffing['routeOnly'], isTrue);
      });

      test('is absent when sniffing is disabled', () {
        final json = XrayConfigBuilder.build(
            _vlessConfig(), _defaultOptions(sniffingEnabled: false));
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
        final geoRules = rules.where((r) =>
          (r as Map).containsKey('ip') &&
          ((r['ip'] as List).any((ip) => (ip as String).startsWith('geoip:') && ip != 'geoip:private'))
        ).toList();
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
          id: 'id', name: 'ss', protocol: VpnProtocol.shadowsocks,
          address: '1.2.3.4', port: 8388, uuid: '',
          security: VpnSecurity.none, transport: VpnTransport.tcp,
          method: 'chacha20-ietf-poly1305', password: 'secret',
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
    Map<String, dynamic> rawManaged({
      String probeInterval = '30s',
      String? fallbackTag = 'direct',
    }) => {
      'inbounds': [
        {'tag': 'socks', 'protocol': 'socks', 'port': 1080},
      ],
      'outbounds': [
        {
          'tag': 'c1-a',
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {'address': 'srv', 'port': 443, 'users': [{'id': 'u', 'flow': 'xtls-rprx-vision'}]},
            ],
          },
        },
        {'tag': 'direct', 'protocol': 'freedom', 'settings': {}},
        {'tag': 'blocked', 'protocol': 'blackhole', 'settings': {}},
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
        outbounds.any((o) =>
            (o as Map)['tag'] == XrayConfigBuilder.blackholeTag && o['protocol'] == 'blackhole'),
        isTrue,
      );
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
      final cfg = merge(
        rawManaged(),
        _defaultOptions(routing: const RoutingSettings(adBlockEnabled: true)),
      );
      final rules = (cfg['routing'] as Map)['rules'] as List;
      final adRule = rules.cast<Map>().firstWhere(
          (r) => (r['domain'] as List?)?.contains('geosite:category-ads-all') ?? false);
      expect(adRule['outboundTag'], XrayConfigBuilder.blackholeTag);
      // App rules must come before server rules (first-match wins).
      expect(rules.indexOf(adRule), lessThan(rules.indexWhere((r) => (r as Map).containsKey('balancerTag'))));
    });

    test('no adblock rule when disabled', () {
      final cfg = merge(rawManaged());
      final rules = (cfg['routing'] as Map)['rules'] as List;
      expect(
        rules.cast<Map>().any((r) => (r['domain'] as List?)?.contains('geosite:category-ads-all') ?? false),
        isFalse,
      );
    });
  });
}
