import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/protocols/xray/xray_config_builder.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/models/routing_settings.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';

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
}) => VpnEngineOptions(
  socksPort: socksPort,
  httpPort: 0,
  socksUser: '',
  socksPassword: '',
  routing: routing ?? const RoutingSettings(),
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
      test('is false when routing is global (default)', () {
        final json = XrayConfigBuilder.build(_vlessConfig(), _defaultOptions());
        final inbound = (json['inbounds'] as List).first as Map<String, dynamic>;
        final sniffing = inbound['sniffing'] as Map<String, dynamic>;
        expect(sniffing['routeOnly'], isFalse);
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

      test('is true when adblock is enabled', () {
        final routing = const RoutingSettings(adBlockEnabled: true);
        final json = XrayConfigBuilder.build(_vlessConfig(), _defaultOptions(routing: routing));
        final inbound = (json['inbounds'] as List).first as Map<String, dynamic>;
        final sniffing = inbound['sniffing'] as Map<String, dynamic>;
        expect(sniffing['routeOnly'], isTrue);
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
}
