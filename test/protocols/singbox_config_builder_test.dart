import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/dns_config.dart';
import 'package:teapodstream/core/models/heartbeat_settings.dart';
import 'package:teapodstream/core/models/routing_settings.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/models/vpn_log_entry.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/protocols/parsers/naive_parser.dart';
import 'package:teapodstream/protocols/parsers/ssh_parser.dart';
import 'package:teapodstream/protocols/singbox/singbox_config_builder.dart';

final _trojan = VpnConfig(
  id: 't', name: 't', protocol: VpnProtocol.trojan, address: 'srv.example.com', port: 443, uuid: '',
  security: VpnSecurity.tls, transport: VpnTransport.tcp, createdAt: DateTime(2026), password: 'pw',
);

VpnEngineOptions _opts({
  RoutingSettings routing = const RoutingSettings(),
  bool sniffing = true,
  bool udp = true,
  DnsMode dnsMode = DnsMode.proxy,
  DnsServerConfig dns = const DnsServerConfig(type: DnsType.udp, address: '1.1.1.1', port: 53),
  DnsQueryStrategy strategy = DnsQueryStrategy.ipv4Only,
}) =>
    VpnEngineOptions(
      socksPort: 10808, httpPort: 0, socksUser: 'u', socksPassword: 'p', routing: routing,
      sniffingEnabled: sniffing, enableUdp: udp, dnsMode: dnsMode, dnsServer: dns, dnsQueryStrategy: strategy,
      heartbeat: const HeartbeatSettings(target: HeartbeatTarget.custom, customUrl: 'https://probe.example.org/204'),
    );

Map<String, dynamic> _build(VpnEngineOptions o) => SingBoxConfigBuilder.build(_trojan, o);

List<Map<String, dynamic>> _rules(Map<String, dynamic> json) =>
    ((json['route'] as Map)['rules'] as List).cast<Map<String, dynamic>>();

void main() {
  test('inbound mixed with auth on loopback, outbounds proxy + direct', () {
    final json = _build(_opts());
    expect(json['inbounds'], [
      {
        'type': 'mixed', 'tag': 'socks-in', 'listen': '127.0.0.1', 'listen_port': 10808,
        'users': [{'username': 'u', 'password': 'p'}],
      },
    ]);
    final outbounds = (json['outbounds'] as List).cast<Map<String, dynamic>>();
    expect(outbounds.map((o) => o['tag']), ['proxy', 'direct']);
    expect(outbounds.last['type'], 'direct');
  });

  test('rule order: sniff, dns hijack, udp reject, private, user rules, probes; final', () {
    const routing = RoutingSettings(
      direction: RoutingDirection.onlySelected, bypassLocal: true,
      domainEnabled: true, domainZones: ['ru'],
      geositeEnabled: true, geositeCodes: ['YouTube'],
      geoEnabled: true, geoCodes: ['RU'],
      sitesEnabled: true, sites: ['example.net'],
      ruServicesEnabled: true,
    );
    final json = _build(_opts(routing: routing, udp: false));
    final rules = _rules(json);
    expect(rules[0], {'inbound': ['socks-in'], 'action': 'sniff'});
    expect(rules[1], {'port': [53], 'action': 'hijack-dns'});
    expect(rules[2], {'network': ['udp'], 'action': 'reject'});
    expect(rules[3], {'ip_is_private': true, 'outbound': 'direct'});
    expect(rules[4], {'domain_suffix': ['ru'], 'outbound': 'proxy'});
    expect(rules[5], {'rule_set': ['geosite-youtube'], 'outbound': 'proxy'});
    expect(rules[6], {'rule_set': ['geoip-ru'], 'outbound': 'proxy'});
    expect(rules[7], {'domain_suffix': ['example.net'], 'outbound': 'proxy'});
    expect(rules[8]['outbound'], 'proxy');
    expect(rules[8]['domain'], contains('go.yandex'));
    expect(rules[8]['domain_suffix'], contains('avito.ru'));
    expect(rules[9], {
      'domain': ['cp.cloudflare.com', 'ip-api.com', 'probe.example.org'],
      'outbound': 'proxy',
    });
    final route = json['route'] as Map<String, dynamic>;
    expect(route['final'], 'direct');
    expect(route['rule_set'], [
      {'type': 'local', 'tag': 'geosite-youtube', 'format': 'binary', 'path': 'geosite-youtube.srs'},
      {'type': 'local', 'tag': 'geoip-ru', 'format': 'binary', 'path': 'geoip-ru.srs'},
    ]);
    expect(route['default_domain_resolver'], 'dns-local');
  });

  test('global routing: no user rules, final proxy, no sniff when disabled', () {
    final json = _build(_opts(sniffing: false));
    final rules = _rules(json);
    expect(rules.first, {'port': [53], 'action': 'hijack-dns'});
    expect(rules, hasLength(1));
    expect((json['route'] as Map)['final'], 'proxy');
    expect((json['route'] as Map).containsKey('rule_set'), isFalse);
  });

  test('bypass direction sends user rules direct', () {
    const routing = RoutingSettings(direction: RoutingDirection.bypass, geoEnabled: true, geoCodes: ['ru']);
    final rules = _rules(_build(_opts(routing: routing)));
    expect(rules.last, {'rule_set': ['geoip-ru'], 'outbound': 'direct'});
  });

  test('ad blocking answers DNS from geosite rule sets', () {
    const routing = RoutingSettings(direction: RoutingDirection.bypass, adBlockEnabled: true);
    final json = _build(_opts(routing: routing));
    final dns = json['dns'] as Map<String, dynamic>;
    expect((dns['rules'] as List).first, {
      'rule_set': ['geosite-category-ads-all', 'geosite-win-spy'],
      'action': 'predefined',
      'rcode': 'NOERROR',
    });
    final tags = ((json['route'] as Map)['rule_set'] as List).map((r) => (r as Map)['tag']);
    expect(tags, containsAll(['geosite-category-ads-all', 'geosite-win-spy']));
  });

  test('DNS servers per type, detour, strategy and fallback IP', () {
    Map<String, dynamic> main(VpnEngineOptions o) =>
        (((_build(o)['dns'] as Map)['servers'] as List).cast<Map<String, dynamic>>())
            .firstWhere((s) => s['tag'] == 'dns-main');
    expect(main(_opts()), {'type': 'udp', 'tag': 'dns-main', 'server': '1.1.1.1', 'server_port': 53, 'detour': 'proxy'});
    expect(main(_opts(dnsMode: DnsMode.direct)).containsKey('detour'), isFalse);
    expect(
      main(_opts(dns: const DnsServerConfig(type: DnsType.doh, address: 'https://dns.example/dns-query', port: 443))),
      {'type': 'https', 'tag': 'dns-main', 'server': 'dns.example', 'server_port': 443, 'path': '/dns-query',
        'detour': 'proxy', 'domain_resolver': 'dns-local'},
    );
    expect(
      main(_opts(dns: const DnsServerConfig(type: DnsType.dot, address: 'dot.example', port: 853,
          domain: 'dot.example', fallbackIp: '9.9.9.9'))),
      {'type': 'tls', 'tag': 'dns-main', 'server': '9.9.9.9', 'server_port': 853,
        'tls': {'enabled': true, 'server_name': 'dot.example'}, 'detour': 'proxy'},
    );
    final dns = _build(_opts(strategy: DnsQueryStrategy.auto))['dns'] as Map<String, dynamic>;
    expect(dns['strategy'], 'prefer_ipv4');
    expect(dns['final'], 'dns-main');
    expect((dns['servers'] as List).cast<Map>().any((s) => s['tag'] == 'dns-local' && s['type'] == 'local'), isTrue);
  });

  test('probe config has no inbounds and the same proxy', () {
    final probe = jsonDecode(SingBoxConfigBuilder.buildProbeJson(_trojan, _opts())) as Map<String, dynamic>;
    expect(probe.containsKey('inbounds'), isFalse);
    expect(((probe['outbounds'] as List).first as Map)['tag'], 'proxy');
    expect(jsonDecode(SingBoxConfigBuilder.buildJson(_trojan, _opts())), _build(_opts()));
  });

  test('TCP-only proxies (SSH, Naive) get DNS over TCP through the tunnel', () {
    Map<String, dynamic> main(VpnConfig c, VpnEngineOptions o) =>
        (((SingBoxConfigBuilder.build(c, o)['dns'] as Map)['servers'] as List).cast<Map<String, dynamic>>())
            .firstWhere((s) => s['tag'] == 'dns-main');
    final ssh = SshParser.parseUri('ssh://root:pw@s.example:22')!;
    final naive = NaiveParser.parseUri('naive+https://u:p@n.example')!;
    for (final c in [ssh, naive]) {
      expect(main(c, _opts()), {'type': 'tcp', 'tag': 'dns-main', 'server': '1.1.1.1', 'server_port': 53, 'detour': 'proxy'},
          reason: c.protocol.name);
    }
    expect(main(ssh, _opts(dnsMode: DnsMode.direct))['type'], 'udp');
    expect(main(_trojan, _opts())['type'], 'udp');
  });

  test('connection logs stay out of the log file unless debug', () {
    String level(LogLevel l) => ((SingBoxConfigBuilder.build(_trojan, VpnEngineOptions(
          socksPort: 1, httpPort: 0, socksUser: '', socksPassword: '', logLevel: l,
        ))['log'] as Map)['level']) as String;
    expect(level(LogLevel.info), 'warn');
    expect(level(LogLevel.warning), 'warn');
    expect(level(LogLevel.error), 'error');
    expect(level(LogLevel.debug), 'debug');
  });
}
