import 'dart:io';

import '../../core/constants/routing_defaults.dart';
import '../../core/constants/xray_defaults.dart';
import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/dns_config.dart';
import '../../core/models/routing_settings.dart';
import '../../core/services/settings_service.dart';
import 'singbox_outbound.dart';

/// DNS и маршрутизация sing-box 1.14: те же правила, что у xray, в нотации sing-box.
abstract final class SingBoxRoute {
  static const inboundTag = 'socks-in';
  static const directTag = 'direct';
  static const _localDns = 'dns-local';
  static const _adBlockTags = ['geosite-category-ads-all', 'geosite-win-spy'];

  static String _geoipTag(String code) => 'geoip-${code.trim().toLowerCase()}';
  static String _geositeTag(String code) => 'geosite-${code.trim().toLowerCase()}';

  /// [tcpOnlyProxy] — прокси без UDP (SSH, Naive): DNS через туннель идёт по TCP.
  static Map<String, dynamic> dns(VpnEngineOptions o, {bool tcpOnlyProxy = false}) {
    final server = o.dnsServer;
    final detour = o.dnsMode == DnsMode.proxy ? {'detour': SingBoxOutbound.tag} : const <String, dynamic>{};
    final Map<String, dynamic> main;
    switch (server.type) {
      case DnsType.udp:
        main = {
          'type': tcpOnlyProxy && o.dnsMode == DnsMode.proxy ? 'tcp' : 'udp',
          'tag': 'dns-main',
          'server': server.address,
          'server_port': server.port,
          ...detour,
        };
      case DnsType.doh:
        final uri = Uri.parse(server.address);
        main = {
          'type': 'https',
          'tag': 'dns-main',
          ..._host(uri.host, server),
          'server_port': uri.hasPort ? uri.port : server.port,
          'path': uri.path.isEmpty ? '/dns-query' : uri.path,
          ...detour,
          if (_needsResolver(uri.host, server)) 'domain_resolver': _localDns,
        };
      case DnsType.dot:
        final host = server.domain ?? server.address;
        main = {
          'type': 'tls',
          'tag': 'dns-main',
          ..._host(host, server),
          'server_port': server.port,
          ...detour,
          if (_needsResolver(host, server)) 'domain_resolver': _localDns,
        };
    }
    return {
      'servers': [main, {'type': 'local', 'tag': _localDns}],
      if (o.routing.adBlockEnabled)
        'rules': [
          {'rule_set': _adBlockTags, 'action': 'predefined', 'rcode': 'NOERROR'},
        ],
      'final': 'dns-main',
      'strategy': switch (o.dnsQueryStrategy) {
        DnsQueryStrategy.ipv4Only => 'ipv4_only',
        DnsQueryStrategy.ipv6Only => 'ipv6_only',
        DnsQueryStrategy.auto => 'prefer_ipv4',
      },
    };
  }

  /// Сервер по IP fallback (с SNI домена) или по имени.
  static Map<String, dynamic> _host(String host, DnsServerConfig server) {
    final ip = server.fallbackIp;
    if (server.domain != null && ip != null && ip.isNotEmpty) {
      return {'server': ip, 'tls': {'enabled': true, 'server_name': server.domain}};
    }
    return {'server': host};
  }

  static bool _needsResolver(String host, DnsServerConfig server) =>
      !(server.domain != null && (server.fallbackIp?.isNotEmpty ?? false)) && InternetAddress.tryParse(host) == null;

  static Map<String, dynamic> route(VpnEngineOptions o) {
    final routing = o.routing;
    final ruleSets = <String>[
      if (routing.isActive && routing.geositeEnabled) ...routing.geositeCodes.map(_geositeTag),
      if (routing.isActive && routing.geoEnabled) ...routing.geoCodes.map(_geoipTag),
      if (routing.adBlockEnabled) ..._adBlockTags,
    ];
    return {
      'rules': [
        if (o.sniffingEnabled) {'inbound': [inboundTag], 'action': 'sniff'},
        {'port': [53], 'action': 'hijack-dns'},
        if (!o.enableUdp) {'network': ['udp'], 'action': 'reject'},
        ..._userRules(routing),
        if (routing.direction == RoutingDirection.onlySelected) ..._probeRules(o),
      ],
      if (ruleSets.isNotEmpty)
        'rule_set': [
          for (final tag in ruleSets.toSet())
            {'type': 'local', 'tag': tag, 'format': 'binary', 'path': '$tag.srs'},
        ],
      'final': routing.direction == RoutingDirection.onlySelected ? directTag : SingBoxOutbound.tag,
      'default_domain_resolver': _localDns,
    };
  }

  static List<Map<String, dynamic>> _userRules(RoutingSettings routing) {
    if (!routing.isActive) return const [];
    final out = routing.direction == RoutingDirection.bypass ? directTag : SingBoxOutbound.tag;
    return [
      if (routing.bypassLocal) {'ip_is_private': true, 'outbound': directTag},
      if (routing.domainEnabled && routing.domainZones.isNotEmpty)
        {'domain_suffix': routing.domainZones, 'outbound': out},
      if (routing.geositeEnabled && routing.geositeCodes.isNotEmpty)
        {'rule_set': routing.geositeCodes.map(_geositeTag).toList(), 'outbound': out},
      if (routing.geoEnabled && routing.geoCodes.isNotEmpty)
        {'rule_set': routing.geoCodes.map(_geoipTag).toList(), 'outbound': out},
      if (routing.sitesEnabled && routing.sites.isNotEmpty) {'domain_suffix': routing.sites, 'outbound': out},
      if (routing.ruServicesEnabled) {..._xrayDomains(RoutingDefaults.ruServicesDomains), 'outbound': out},
    ];
  }

  /// `domain:x` → domain_suffix, `full:x` → domain.
  static Map<String, dynamic> _xrayDomains(List<String> rules) => {
        'domain': [for (final r in rules) if (r.startsWith('full:')) r.substring(5)],
        'domain_suffix': [for (final r in rules) if (r.startsWith('domain:')) r.substring(7)],
      };

  /// В режиме «только выбранные» диагностика и проба всегда идут через прокси.
  static List<Map<String, dynamic>> _probeRules(VpnEngineOptions o) {
    final host = Uri.tryParse(o.heartbeat.url)?.host ?? '';
    final isIp = InternetAddress.tryParse(host) != null;
    return [
      {
        'domain': ['cp.cloudflare.com', 'ip-api.com', if (host.isNotEmpty && !isIp) host],
        'outbound': SingBoxOutbound.tag,
      },
      if (isIp) {'ip_cidr': [host], 'outbound': SingBoxOutbound.tag},
    ];
  }

  /// Адрес SOCKS-inbound (общий с xray).
  static const listen = XrayDefaults.socksListen;
}
