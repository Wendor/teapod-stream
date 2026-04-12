import 'dart:convert';
import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/vpn_config.dart';
import '../../core/models/dns_config.dart';

class XrayConfigBuilder {
  static Map<String, dynamic> build(VpnConfig config, VpnEngineOptions options) {
    final dnsBlock = _buildDnsBlock(options);

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
            'routeOnly': false,
          },
        }
      ],
      'outbounds': [
        _buildOutbound(config),
        {'tag': 'direct', 'protocol': 'freedom'},
        {'tag': 'block', 'protocol': 'blackhole'},
        {'tag': 'dns-out', 'protocol': 'dns'}
      ],
      'routing': {
        'domainStrategy': options.dnsMode == DnsMode.direct ? 'UseIP' : 'IPIfNonMatch',
        'rules': [
          if (options.dnsMode == DnsMode.proxy) ...[
            {
              'type': 'field',
              'port': '53',
              'network': 'udp,tcp',
              'outboundTag': 'dns-out',
            },
          ],
          {
            'type': 'field',
            'inboundTag': ['socks-in'],
            'outboundTag': 'proxy',
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

  static Map<String, dynamic> _buildDnsBlock(VpnEngineOptions options) {
    final server = options.dnsServer;
    List<dynamic> servers;

    if (options.dnsMode == DnsMode.direct) {
      // Direct mode: no DNS block, let system/tun2socks handle DNS
      return {
        'servers': ['localhost'],
        'queryStrategy': 'UseIP',
      };
    }

    // Proxy mode: configure DNS servers for xray
    switch (server.type) {
      case DnsType.udp:
        servers = [
          {'address': server.address, 'port': server.port},
        ];
        break;
      case DnsType.doh:
        // xray supports DoH via https:// prefix
        servers = [
          {'address': server.address},
        ];
        break;
      case DnsType.dot:
        // DoT via tls+local:// prefix in xray
        servers = [
          {'address': 'tls+local://${server.address}:${server.port}'},
        ];
        break;
    }

    return {
      'hosts': {},
      'servers': servers,
      'queryStrategy': 'UseIP',
    };
  }

  static Map<String, dynamic> _buildOutbound(VpnConfig config) {
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
      default:
        return {};
    }
  }

  static Map<String, dynamic> _buildStreamSettings(VpnConfig config) {
    return {
      'network': config.transport.name,
      'security': config.security.name,
      if (config.security == VpnSecurity.reality)
        'realitySettings': {
          'serverName': config.sni ?? '',
          'fingerprint': config.fingerprint ?? 'chrome',
          'publicKey': config.publicKey ?? '',
          'shortId': config.shortId ?? '',
          'spiderX': config.spiderX ?? '',
        },
      if (config.security == VpnSecurity.tls)
        'tlsSettings': {
          'serverName': config.sni ?? '',
          'allowInsecure': false,
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
    };
  }

  static String buildJson(VpnConfig config, VpnEngineOptions options) {
    return const JsonEncoder().convert(build(config, options));
  }
}
