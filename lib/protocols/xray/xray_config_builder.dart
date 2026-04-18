import 'dart:convert';
import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/vpn_config.dart';
import '../../core/models/dns_config.dart';
import '../../core/models/routing_settings.dart';

class XrayConfigBuilder {
  static Map<String, dynamic> build(VpnConfig config, VpnEngineOptions options) {
    final dnsBlock = _buildDnsBlock(options);
    final routing = options.routing;

    return {
      'log': {'loglevel': options.logLevel.name},
      'dns': dnsBlock,
      'inbounds': [
        {
          'tag': 'socks-in',
          'protocol': 'socks',
          'port': options.socksPort,
          'listen': '127.0.0.1',
          'settings': {
            'auth': options.socksUser.isNotEmpty ? 'password' : 'noauth',
            if (options.socksUser.isNotEmpty)
              'accounts': [
                {'user': options.socksUser, 'pass': options.socksPassword}
              ],
            'udp': options.enableUdp,
          },
          'sniffing': {
            'enabled': true,
            'destOverride': ['http', 'tls', 'quic'],
            // routeOnly: true preserves original IP for geoip matching — without it xray
            // re-resolves the domain via VPN DNS and may get CDN IPs outside the target geo
            'routeOnly': routing.isActive && routing.geoEnabled && routing.geoCodes.isNotEmpty,
          },
        },
      ],
      'outbounds': [
        _buildOutbound(config),
        {'tag': 'direct', 'protocol': 'freedom'},
        {'tag': 'block', 'protocol': 'blackhole'},
        {'tag': 'dns-out', 'protocol': 'dns'}
      ],
      'routing': {
        'domainStrategy': 'IPIfNonMatch',
        'rules': [
          if (options.dnsMode == DnsMode.proxy) ...[
            // Proxy mode: intercept DNS via xray's DNS module → queries go through VPN
            {
              'type': 'field',
              'port': '53',
              'network': 'udp,tcp',
              'outboundTag': 'dns-out',
            },
          ],
          if (options.dnsMode == DnsMode.direct) ...[
            // Direct mode: DNS queries bypass the VPN tunnel entirely.
            // xray's own process is excluded from the TUN, so 'direct' outbound
            // connects straight to the internet without going through the VPN.
            {
              'type': 'field',
              'port': '53',
              'network': 'udp,tcp',
              'outboundTag': 'direct',
            },
          ],
          ..._buildGeoRules(routing),
          {
            'type': 'field',
            'inboundTag': ['socks-in'],
            'outboundTag': routing.direction == RoutingDirection.onlySelected
                ? 'direct'
                : 'proxy',
          }
        ],
      },
      'policy': {
        'levels': {
          '0': {
            'handshake': 4,
            'connIdle': 120,
            'uplinkOnly': 5,
            'downlinkOnly': 30,
          }
        },
        'system': {
          'statsInboundUplink': false,
          'statsInboundDownlink': false,
        }
      },
    };
  }

  static List<Map<String, dynamic>> _buildGeoRules(RoutingSettings routing) {
    if (!routing.isActive) return [];

    final rules = <Map<String, dynamic>>[];

    // Private IPs always bypass regardless of direction
    if (routing.bypassLocal) {
      rules.add({'type': 'field', 'ip': ['geoip:private'], 'outboundTag': 'direct'});
    }

    if (!routing.geoEnabled && !routing.domainEnabled) return rules;

    final selectedOut =
        routing.direction == RoutingDirection.bypass ? 'direct' : 'proxy';

    if (routing.domainEnabled && routing.domainZones.isNotEmpty) {
      rules.add({
        'type': 'field',
        'domain': routing.domainZones.map((z) => 'domain:$z').toList(),
        'outboundTag': selectedOut,
      });
    }

    if (routing.geoEnabled && routing.geoCodes.isNotEmpty) {
      rules.add({
        'type': 'field',
        'ip': routing.geoCodes.map((c) => 'geoip:${c.toLowerCase()}').toList(),
        'outboundTag': selectedOut,
      });
    }

    return rules;
  }

  static Map<String, dynamic> _buildDnsBlock(VpnEngineOptions options) {
    final server = options.dnsServer;
    List<dynamic> servers;

    if (options.dnsMode == DnsMode.direct) {
      // Direct mode: DNS queries bypass the VPN via the 'direct' routing rule above.
      // Use system resolver for xray's own domain lookups (e.g. routing decisions).
      return {
        'servers': ['localhost'],
        'queryStrategy': 'UseIPv4',
      };
    }

    // Proxy mode: DNS queries are intercepted and handled by xray's DNS module.
    switch (server.type) {
      case DnsType.udp:
        servers = [
          {'address': server.address, 'port': server.port},
        ];
        break;
      case DnsType.doh:
        // xray expects full HTTPS URL for DoH
        servers = [
          {'address': server.address},
        ];
        break;
      case DnsType.dot:
        // xray DoT format: tls://address:port
        servers = [
          {'address': 'tls://${server.address}:${server.port}'},
        ];
        break;
    }

    return {
      'hosts': {},
      'servers': servers,
      'queryStrategy': 'UseIPv4',
    };
  }

  static Map<String, dynamic> _buildOutbound(VpnConfig config) {
    if (config.protocol == VpnProtocol.hysteria2) {
      return {
        'tag': 'proxy',
        'protocol': 'hysteria',
        'settings': _buildOutboundSettings(config),
        'streamSettings': _buildStreamSettings(config),
      };
    }
    return {
      'tag': 'proxy',
      'protocol': config.protocol.name,
      'settings': _buildOutboundSettings(config),
      'streamSettings': _buildStreamSettings(config),
    };
  }

  static Map<String, dynamic> _buildOutboundSettings(VpnConfig config) {
    switch (config.protocol) {
      case VpnProtocol.vless:
        return {
          'vnext': [
            {
              'address': config.address,
              'port': config.port,
              'users': [
                {'id': config.uuid, 'encryption': config.encryption ?? 'none', 'flow': config.flow ?? ''}
              ]
            }
          ]
        };
      case VpnProtocol.vmess:
        return {
          'vnext': [
            {
              'address': config.address,
              'port': config.port,
              'users': [
                {'id': config.uuid, 'security': 'auto'}
              ]
            }
          ]
        };
      case VpnProtocol.trojan:
        return {
          'servers': [
            {
              'address': config.address,
              'port': config.port,
              'password': config.password ?? '',
            }
          ]
        };
      case VpnProtocol.shadowsocks:
        return {
          'servers': [
            {
              'address': config.address,
              'port': config.port,
              'method': config.method ?? 'chacha20-ietf-poly1305',
              'password': config.password ?? '',
            }
          ]
        };
      case VpnProtocol.hysteria2:
        return {
          'version': 2,
          'address': config.address,
          'port': config.port,
        };
    }
  }

  // xray uses "h2" for HTTP/2, not the enum name "http2".
  static String _networkName(VpnTransport t) =>
      t == VpnTransport.http2 ? 'h2' : t.name;

  static Map<String, dynamic> _buildStreamSettings(VpnConfig config) {
    if (config.protocol == VpnProtocol.hysteria2) {
      return {
        'network': 'hysteria',
        'security': 'tls',
        'tlsSettings': {
          'serverName': config.sni ?? '',
          'allowInsecure': false,
        },
        'hysteriaSettings': {
          'version': 2,
          'auth': config.password ?? '',
        },
      };
    }
    return {
      'network': _networkName(config.transport),
      'security': config.security.name,
      if (config.security == VpnSecurity.reality)
        'realitySettings': {
          'serverName': config.sni ?? '',
          'fingerprint': config.fingerprint ?? 'chrome',
          'publicKey': config.publicKey ?? '',
          'shortId': config.shortId ?? '',
          'spiderX': config.spiderX ?? '',
          if (config.postQuantumKey != null && config.postQuantumKey!.isNotEmpty)
            'mldsa65Verify': config.postQuantumKey,
        },
      if (config.security == VpnSecurity.tls)
        'tlsSettings': {
          'serverName': config.sni ?? '',
          'allowInsecure': false,
          if (config.fingerprint != null && config.fingerprint!.isNotEmpty)
            'fingerprint': config.fingerprint,
        },
      if (config.transport == VpnTransport.ws)
        'wsSettings': {
          'path': config.wsPath ?? '/',
          'headers': {'Host': config.wsHost ?? ''}
        },
      if (config.transport == VpnTransport.grpc)
        'grpcSettings': {
          'serviceName': config.grpcServiceName ?? '',
        },
      if (config.transport == VpnTransport.xhttp)
        'xhttpSettings': {
          'path': config.wsPath ?? '/',
          if (config.wsHost != null && config.wsHost!.isNotEmpty)
            'host': config.wsHost,
        },
      if (config.transport == VpnTransport.splithttp)
        'splithttpSettings': {
          'path': config.wsPath ?? '/',
          if (config.wsHost != null && config.wsHost!.isNotEmpty)
            'host': config.wsHost,
        },
      if (config.transport == VpnTransport.httpupgrade)
        'httpupgradeSettings': {
          'path': config.wsPath ?? '/',
          if (config.wsHost != null && config.wsHost!.isNotEmpty)
            'host': config.wsHost,
        },
    };
  }

  static String buildJson(VpnConfig config, VpnEngineOptions options) {
    return const JsonEncoder().convert(build(config, options));
  }
}
