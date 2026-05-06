import 'dart:convert';
import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/vpn_config.dart';
import '../../core/models/dns_config.dart';
import '../../core/models/routing_settings.dart';
import '../../core/constants/xray_defaults.dart';

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
          'listen': XrayDefaults.socksListen,
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
            'routeOnly': true,
          },
        },
      ],
      'outbounds': [
        _buildOutbound(config),
        {'tag': 'direct', 'protocol': 'freedom'},
        {'tag': 'dns-out', 'protocol': 'dns'}
      ],
      'routing': {
        'domainStrategy': 'IPIfNonMatch',
        'rules': [
          if (options.dnsMode == DnsMode.proxy) ...[
            // Proxy mode: intercept DNS queries from the user and handle them via xray's DNS module.
            // We only match socks-in to avoid loops when the DNS module sends its own queries.
            {
              'type': 'field',
              'inboundTag': ['socks-in'],
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
            'outboundTag': routing.direction == RoutingDirection.onlySelected ? 'direct' : 'proxy',
          }
        ],
      },
      'policy': {
        'levels': {
          '0': {
            'handshake': XrayDefaults.handshakeTimeout,
            'connIdle': XrayDefaults.connIdleTimeout,
            'uplinkOnly': XrayDefaults.uplinkOnlyTimeout,
            'downlinkOnly': XrayDefaults.downlinkOnlyTimeout,
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

    if (!routing.geoEnabled && !routing.domainEnabled && !routing.geositeEnabled) return rules;

    final selectedOut =
        routing.direction == RoutingDirection.bypass ? 'direct' : 'proxy';

    if (routing.domainEnabled && routing.domainZones.isNotEmpty) {
      rules.add({
        'type': 'field',
        'domain': routing.domainZones.map((z) => 'domain:$z').toList(),
        'outboundTag': selectedOut,
      });
    }

    if (routing.geositeEnabled && routing.geositeCodes.isNotEmpty) {
      rules.add({
        'type': 'field',
        'domain': routing.geositeCodes.map((c) => 'geosite:$c').toList(),
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
    final routing = options.routing;
    List<dynamic> servers = [];

    if (options.dnsMode == DnsMode.direct) {
      // Direct mode: DNS queries bypass the VPN via the 'direct' routing rule above.
      // Use system resolver for xray's own domain lookups (e.g. routing decisions).
      return {
        'servers': ['localhost'],
        'queryStrategy': 'UseIPv4',
        'disableFallback': true,
      };
    }

    // Proxy mode: DNS queries are intercepted and handled by xray's DNS module.
    // Add adblock first - returns empty response for matched domains
    if (routing.adBlockEnabled) {
      servers.add({
        'address': 'rcode://success',
        'domains': [XrayDefaults.adBlockGeosite],
      });
    }

    // Add main DNS server
    switch (server.type) {
      case DnsType.udp:
        servers.add({'address': server.address, 'port': server.port});
        break;
      case DnsType.doh:
        servers.add({'address': server.address});
        break;
      case DnsType.dot:
        servers.add({'address': 'tls://${server.address}', 'port': server.port});
        break;
    }

    final hosts = <String, String>{};
    if (server.domain != null && server.fallbackIp != null) {
      hosts[server.domain!] = server.fallbackIp!;
    } else if (server.type == DnsType.doh || server.type == DnsType.dot) {
      // Bootstrap for domain-based custom DoH/DoT: without a static hosts entry,
      // xray can't resolve the server hostname (circular dependency).
      final host = server.type == DnsType.doh
          ? (Uri.tryParse(server.address)?.host ?? '')
          : server.address;
      if (host.isNotEmpty && !_isIpAddress(host)) {
        servers.insert(servers.length - 1, {
          'address': XrayDefaults.bootstrapDns,
          'port': 53,
          'domains': [host],
        });
      }
    }

    return {
      'hosts': hosts,
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

  static List<String>? _formatPinSHA256(String? pin) {
    if (pin == null || pin.isEmpty) return null;
    try {
      if (pin.contains(':')) {
        final bytes = pin.split(':').map((e) => int.parse(e, radix: 16)).toList();
        return [base64Encode(bytes)];
      }
      if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(pin)) {
        final bytes = <int>[];
        for (var i = 0; i < pin.length; i += 2) {
          bytes.add(int.parse(pin.substring(i, i + 2), radix: 16));
        }
        return [base64Encode(bytes)];
      }
      return [pin];
    } catch (_) {
      return [pin];
    }
  }

  static Map<String, dynamic> _buildStreamSettings(VpnConfig config) {
    if (config.protocol == VpnProtocol.hysteria2) {
      return {
        'network': 'hysteria',
        'security': 'tls',
        'tlsSettings': {
          'serverName': config.sni ?? '',
          'allowInsecure': config.allowInsecure,
          if (config.pinSHA256 != null && config.pinSHA256!.isNotEmpty)
            'pinnedPeerCertificateChainSha256': _formatPinSHA256(config.pinSHA256),
        },
        'hysteriaSettings': {
          'version': 2,
          'auth': config.password ?? '',
        },
        if (config.obfsPassword != null && config.obfsPassword!.isNotEmpty)
          'finalmask': {
            'udp': [
              {
                'type': 'salamander',
                'settings': {'password': config.obfsPassword},
              }
            ]
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
          if (config.xhttpMode != null && config.xhttpMode!.isNotEmpty)
            'mode': config.xhttpMode,
          if (config.xhttpExtra != null && config.xhttpExtra!.isNotEmpty)
            'extra': config.xhttpExtra,
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
      if (config.finalmask != null && config.finalmask!.isNotEmpty)
        'finalmask': config.finalmask,
    };
  }

  static String buildJson(VpnConfig config, VpnEngineOptions options) {
    return const JsonEncoder().convert(build(config, options));
  }

  static bool _isIpAddress(String host) {
    if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host)) return true;
    if (host.contains(':')) return true; // IPv6
    return false;
  }
}
