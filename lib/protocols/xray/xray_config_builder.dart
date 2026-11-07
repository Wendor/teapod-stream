import 'dart:convert';
import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/vpn_config.dart';
import '../../core/models/dns_config.dart';
import '../../core/models/routing_settings.dart';
import '../../core/models/xray_tuning.dart';
import '../../core/constants/routing_defaults.dart';
import '../../core/constants/xray_defaults.dart';
import '../../core/models/vpn_log_entry.dart' show LogLevel;
import '../../core/services/settings_service.dart' show DnsQueryStrategy, TlsFingerprint;
import 'vless_parser.dart';

class XrayConfigBuilder {

  /// Профили, которые xray-core v26 отвергает при старте (`PrintRemovedFeatureError`
  /// и битый пин): без проверки они падали бы «xray failed to start» и
  /// попадали в кандидаты urltest. null — профиль собирается.
  static String? unsupportedReason(VpnConfig config) {
    if (config.protocol.hasProtocolSettings) return config.protocol.singBoxOnlyReason;
    if (config.rawXrayConfig != null) return null;
    if (config.transport == VpnTransport.http2 || config.transport == VpnTransport.quic) {
      return 'Транспорты HTTP/2 и QUIC удалены из Xray-core: сервер нужно перевести на xHTTP.';
    }
    final pin = config.pinSHA256?.trim() ?? '';
    if (pin.isNotEmpty) {
      try {
        certificatePins(pin);
      } on FormatException catch (e) {
        return e.message;
      }
    }
    final tls = config.security == VpnSecurity.tls || config.protocol == VpnProtocol.hysteria2;
    if (tls && config.allowInsecure && pin.isEmpty) {
      return 'Xray-core больше не поддерживает allowInsecure: укажи pinSHA256 сертификата '
          'сервера или используй действительный сертификат.';
    }
    return null;
  }

  static Map<String, dynamic> build(VpnConfig config, VpnEngineOptions options) {
    final dnsBlock = _buildDnsBlock(options);
    final routing = options.routing;
    // routeOnly=true: sniffed domain is used for routing only — xray does NOT replace
    // the connection destination. Without this, xray re-resolves the domain and
    // redirects the connection to a different IP, breaking tun2socks and leaking DNS.
    final routeOnly = options.sniffingEnabled;
    final probeHost = Uri.tryParse(options.heartbeat.url)?.host ?? '';

    return {
      'log': _logBlock(options),
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
            'enabled': options.sniffingEnabled,
            if (options.sniffingEnabled) ...{
              'destOverride': ['http', 'tls', 'quic'],
              'routeOnly': routeOnly,
            },
          },
        },
      ],
      'outbounds': [
        _buildOutbound(config, options),
        if (_dialerApplies(config, options)) _buildDialerOutbound(config, options),
        {'tag': 'direct', 'protocol': 'freedom'},
        {'tag': 'dns-out', 'protocol': 'dns'},
        {'tag': 'block', 'protocol': 'blackhole'},
      ],
      'routing': {
        'domainStrategy': 'IPIfNonMatch',
        'rules': [
          // QUIC blocking is handled at the TUN level by tun2socks, which replies
          // with an ICMP Port Unreachable so the browser falls back to TCP immediately.
          // No xray routing rule is needed: silently dropping UDP/443 here (blackhole)
          // would force browsers to wait ~55s for QUIC retransmission to time out,
          // and rerouting QUIC to 'direct' would leak the destination outside the tunnel.
          // App DNS goes to xray's DNS module with the selected server. Its own sockets
          // egress through the tunnel in proxy mode, or past it in direct mode (xray's
          // process is excluded from the TUN) — as if there were no VPN.
          {
            'type': 'field',
            'inboundTag': ['dns-module'],
            'outboundTag': options.dnsMode == DnsMode.proxy ? 'proxy' : 'direct',
          },
          {
            'type': 'field',
            'inboundTag': ['socks-in'],
            'port': '53',
            'network': 'udp,tcp',
            'outboundTag': 'dns-out',
          },
          ..._buildGeoRules(routing),
          // In ONLY mode the catch-all routes to direct, so diagnostic hosts that aren't
          // in the user's rules would bypass the proxy and may be blocked locally.
          // Force them via proxy so heartbeat and IP-detection always test the tunnel.
          // Свой URL пробы тоже: иначе она мерила бы прямой интернет, а не туннель.
          if (routing.direction == RoutingDirection.onlySelected) ...[
            {
              'type': 'field',
              'domain': [
                'full:cp.cloudflare.com',
                'full:ip-api.com',
                if (probeHost.isNotEmpty && !_isIpAddress(probeHost)) 'full:$probeHost',
              ],
              'outboundTag': 'proxy',
            },
            if (_isIpAddress(probeHost))
              {'type': 'field', 'ip': [probeHost], 'outboundTag': 'proxy'},
          ],
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

  /// Access-log (строка на каждое соединение: JNI → logcat + файл лога, по сути
  /// история посещений на диске) — только при debug. Ошибки дозвона xray пишет
  /// в error-log уровня info, они остаются.
  static Map<String, dynamic> _logBlock(VpnEngineOptions options) => {
        'loglevel': options.logLevel.name,
        if (options.logLevel != LogLevel.debug)
          'access': 'none',
      };

  static List<Map<String, dynamic>> _buildGeoRules(RoutingSettings routing) {
    if (!routing.isActive) return [];

    final rules = <Map<String, dynamic>>[];

    // Private IPs always bypass regardless of direction
    if (routing.bypassLocal) {
      rules.add({'type': 'field', 'ip': ['geoip:private'], 'outboundTag': 'direct'});
    }

    if (!routing.geoEnabled && !routing.domainEnabled && !routing.geositeEnabled &&
        !routing.sitesEnabled && !routing.ruServicesEnabled) {
      return rules;
    }

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

    if (routing.sitesEnabled && routing.sites.isNotEmpty) {
      rules.add({
        'type': 'field',
        'domain': routing.sites.map((s) => 'domain:$s').toList(),
        'outboundTag': selectedOut,
      });
    }

    if (routing.ruServicesEnabled) {
      rules.add({
        'type': 'field',
        'domain': RoutingDefaults.ruServicesDomains,
        'outboundTag': selectedOut,
      });
    }

    return rules;
  }

  static String _queryStrategy(DnsQueryStrategy s) => switch (s) {
    DnsQueryStrategy.ipv4Only => 'UseIPv4',
    DnsQueryStrategy.ipv6Only => 'UseIPv6',
    DnsQueryStrategy.auto     => 'UseIP',
  };

  static Map<String, dynamic> buildDnsBlock(VpnEngineOptions options) => _buildDnsBlock(options);

  static Map<String, dynamic> _buildDnsBlock(VpnEngineOptions options) {
    final server = options.dnsServer;
    final routing = options.routing;
    final strategy = _queryStrategy(options.dnsQueryStrategy);
    List<dynamic> servers = [];

    // Main server must be first: with disableFallback, xray sends every domain that
    // matches no 'domains' filter to servers[0].
    switch (server.type) {
      case DnsType.udp:
        servers.add({'address': server.address, 'port': server.port});
        break;
      case DnsType.doh:
        servers.add({'address': server.address});
        break;
      case DnsType.dot:
        // Use domain as TLS address (SNI) when available; fall back to IP.
        servers.add({'address': 'tls://${server.domain ?? server.address}', 'port': server.port});
        break;
    }

    // Adblock: returns empty response for matched domains
    if (routing.adBlockEnabled) {
      servers.add({
        'address': 'rcode://success',
        'domains': [XrayDefaults.adBlockGeosite, 'geosite:win-spy'],
      });
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
        servers.add({
          'address': XrayDefaults.bootstrapDns,
          'port': 53,
          'domains': [host],
        });
      }
    }

    return {
      'tag': 'dns-module',
      'hosts': hosts,
      'servers': servers,
      'queryStrategy': strategy,
      // Without this, a broken primary server (e.g. DoT on a wrong port) silently
      // falls back to the domain-filtered bootstrap server, and all queries end up
      // on 8.8.8.8 instead of the server the user selected.
      'disableFallback': true,
    };
  }

  /// Тег вспомогательного freedom-outbound, через который proxy дозванивается
  /// до сервера: там живут фрагментация (TCP) и шумы (UDP).
  static const _dialerTag = 'dialer-out';

  /// Fragment режет TCP-поток — для hysteria2 (QUIC поверх UDP) он неприменим.
  static bool _fragmentApplies(VpnConfig config, VpnEngineOptions options) =>
      options.fragment.enabled &&
      options.fragment.isValid &&
      config.protocol != VpnProtocol.hysteria2;

  /// Noise пишется только в UDP-плечо (`proxy/freedom`: ветка non-TCP), то есть
  /// реально работает для Hysteria2 и QUIC-транспорта. Для TCP безвреден.
  static bool _noiseApplies(VpnEngineOptions options) =>
      options.noise.enabled && options.noise.isValid;

  static bool _dialerApplies(VpnConfig config, VpnEngineOptions options) =>
      _fragmentApplies(config, options) || _noiseApplies(options);

  /// Mux бесполезен поверх hysteria2 (QUIC мультиплексирует сам) и xhttp
  /// (свой xmux; двойное мультиплексирование upstream не рекомендует).
  static bool _muxApplies(VpnConfig config, VpnEngineOptions options) =>
      options.mux.enabled &&
      config.protocol != VpnProtocol.hysteria2 &&
      config.transport != VpnTransport.xhttp;

  /// TCP_USER_TIMEOUT: соединение, где DPI молча дропает пакеты, рвётся через
  /// 30 с неподтверждённых данных, а не висит в ретрансляции до tcp_retries2.
  static const _tcpUserTimeoutMs = 30000;

  static Map<String, dynamic> _buildDialerOutbound(
      VpnConfig config, VpnEngineOptions options) {
    final f = options.fragment;
    final n = options.noise;
    return {
      'tag': _dialerTag,
      'protocol': 'freedom',
      'streamSettings': {
        'sockopt': {'tcpUserTimeout': _tcpUserTimeoutMs},
      },
      'settings': {
        'domainStrategy': 'AsIs',
        if (_fragmentApplies(config, options))
          'fragment': {
            'packets': f.packets.trim(),
            'length': f.length.trim(),
            'interval': f.interval.trim(),
          },
        if (_noiseApplies(options))
          'noises': [
            {
              'type': n.type.name,
              'packet': n.packet.trim(),
              'delay': n.delay.trim(),
            }
          ],
      },
    };
  }

  /// XTLS Vision несовместим с TCP-mux: сервер рвёт mux-соединения с TCP-запросами
  /// (см. proxy/vless/outbound). Оставляем только XUDP-ветку — `concurrency: -1`.
  static Map<String, dynamic> _buildMux(VpnConfig config, MuxSettings mux) {
    final vision = config.flow?.contains('xtls-rprx-vision') ?? false;
    return {
      'enabled': true,
      'concurrency': vision ? -1 : mux.concurrency,
      'xudpConcurrency': mux.xudpConcurrency,
      'xudpProxyUDP443': mux.xudpProxyUDP443.name,
    };
  }

  static Map<String, dynamic> _buildOutbound(VpnConfig config, VpnEngineOptions options) {
    final stream = _buildStreamSettings(config, options.tlsFingerprint);
    if (_dialerApplies(config, options)) {
      stream['sockopt'] = {'dialerProxy': _dialerTag};
    } else if (config.protocol != VpnProtocol.hysteria2) {
      stream['sockopt'] = {'tcpUserTimeout': _tcpUserTimeoutMs};
    }
    return {
      'tag': 'proxy',
      'protocol': config.protocol == VpnProtocol.hysteria2 ? 'hysteria' : config.protocol.name,
      'settings': _buildOutboundSettings(config),
      'streamSettings': stream,
      if (_muxApplies(config, options)) 'mux': _buildMux(config, options.mux),
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
      case VpnProtocol.wireguard || VpnProtocol.ssh || VpnProtocol.naive:
        throw UnsupportedError(config.protocol.singBoxOnlyReason);
    }
  }

  // xray uses "h2" for HTTP/2, not the enum name "http2".
  static String _networkName(VpnTransport t) =>
      t == VpnTransport.http2 ? 'h2' : t.name;

  /// `pinnedPeerCertSha256`: SHA-256 полного DER-сертификата в hex, через запятую.
  /// `pinSHA256` из ссылки — hex (с двоеточиями или без) или base64 от 32 байт.
  static String certificatePins(String value) {
    final pins = <String>[];
    for (final entry in value.split(',')) {
      final raw = entry.trim();
      final hex = raw.replaceAll(':', '');
      if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hex)) {
        pins.add(hex.toLowerCase());
        continue;
      }
      try {
        final bytes = base64.decode(raw);
        if (bytes.length != 32) throw const FormatException();
        pins.add(bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join());
      } on FormatException {
        throw const FormatException(
          'pinSHA256 должен быть SHA-256 сертификата: 64 hex-символа или base64 от 32 байт.',
        );
      }
    }
    return pins.join(',');
  }

  static Map<String, dynamic> _buildStreamSettings(VpnConfig config, TlsFingerprint fp) {
    // Глобальный override из настроек приложения; defaultFp — значение из конфига.
    final fingerprint = fp.xrayValue ?? config.fingerprint;
    // Пин сильнее allowInsecure: принимается только этот сертификат.
    final pin = config.pinSHA256?.trim() ?? '';
    if (config.protocol == VpnProtocol.hysteria2) {
      final salamander = config.obfsPassword?.isNotEmpty ?? false;
      final hopping = config.hopPorts?.isNotEmpty ?? false;
      return {
        'network': 'hysteria',
        'security': 'tls',
        'tlsSettings': {
          // hysteria-dialer в xray не вызывает WithDestination: при пустом serverName
          // SNI берётся из URL auth-запроса и становится литералом "hysteria".
          'serverName': (config.sni?.isNotEmpty ?? false) ? config.sni : config.address,
          'allowInsecure': config.allowInsecure && pin.isEmpty,
          if (pin.isNotEmpty) 'pinnedPeerCertSha256': certificatePins(pin),
        },
        'hysteriaSettings': {
          'version': 2,
          'auth': config.password ?? '',
        },
        if (salamander || hopping)
          'finalmask': {
            'udp': [
              // Xray-core ≥ v26.9.9: port hopping — UDP-маска udphop (раньше
              // quicParams.udpHop). Маска с собственным дозвоном обязана быть
              // первой. Новый сокет + случайный порт раз в 30 с — как в Hysteria.
              if (hopping)
                {
                  'type': 'udphop',
                  'settings': {
                    'mode': 'intervalLocal,intervalRemote',
                    'remotePorts': config.hopPorts,
                  },
                },
              if (salamander)
                {
                  'type': 'salamander',
                  'settings': {'password': config.obfsPassword},
                },
            ],
          },
      };
    }
    return {
      'network': _networkName(config.transport),
      'security': config.security.name,
      if (config.security == VpnSecurity.reality)
        'realitySettings': {
          'serverName': config.sni ?? '',
          'fingerprint': fingerprint ?? 'chrome',
          'publicKey': config.publicKey ?? '',
          'shortId': config.shortId ?? '',
          'spiderX': config.spiderX ?? '',
          if (config.postQuantumKey != null && config.postQuantumKey!.isNotEmpty)
            'mldsa65Verify': config.postQuantumKey,
        },
      if (config.security == VpnSecurity.tls)
        'tlsSettings': {
          'serverName': config.sni ?? '',
          'allowInsecure': config.allowInsecure && pin.isEmpty,
          if (pin.isNotEmpty) 'pinnedPeerCertSha256': certificatePins(pin),
          if (fingerprint != null && fingerprint.isNotEmpty)
            'fingerprint': fingerprint,
          if (config.alpn != null && config.alpn!.isNotEmpty)
            'alpn': config.alpn!.split(',').map((s) => s.trim()).toList(),
          // Ключ Xray-core — echConfigList; прежний echSettings молча игнорировался.
          if (config.ech != null && config.ech!.isNotEmpty)
            'echConfigList': config.ech,
        },
      if (_tcpHttpHeader(config))
        'tcpSettings': {
          'header': {
            'type': 'http',
            'request': {
              'path': _csv(config.wsPath ?? '/', fallback: '/'),
              'headers': {
                if (config.wsHost?.isNotEmpty ?? false) 'Host': _csv(config.wsHost!),
              },
            },
          },
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

  /// TCP с HTTP-маскировкой (`headerType=http`, у VMess — `type`). Полей в
  /// [VpnConfig] нет — читаем исходную ссылку. Без заголовка сервер рвёт соединение.
  static bool _tcpHttpHeader(VpnConfig config) {
    if (config.transport != VpnTransport.tcp || config.protocol == VpnProtocol.hysteria2) {
      return false;
    }
    final type = config.protocol == VpnProtocol.vmess
        ? VlessParser.vmessJson(config)['type']?.toString()
        : VlessParser.linkParams(config)['headerType'];
    return type?.trim().toLowerCase() == 'http';
  }

  static List<String> _csv(String value, {String? fallback}) {
    final items = [
      for (final v in value.split(',')) if (v.trim().isNotEmpty) v.trim(),
    ];
    return items.isEmpty && fallback != null ? [fallback] : items;
  }

  static String buildJson(VpnConfig config, VpnEngineOptions options) {
    return const JsonEncoder().convert(build(config, options));
  }

  static bool _isIpAddress(String host) {
    if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host)) return true;
    if (host.contains(':')) return true; // IPv6
    return false;
  }

  /// Merge app settings into a pre-built raw xray config from a managed subscription.
  ///
  /// Unlike [build], we preserve the server's outbound topology (load balancers,
  /// observatory, custom outbound tags). Only port/credentials, DNS, log and
  /// safe bypass rules (→ direct) are overlaid.
  static String mergeWithRaw(String rawConfig, VpnEngineOptions options) {
    try {
      final cfg = jsonDecode(rawConfig) as Map<String, dynamic>;

      // api/metrics с `listen` — gRPC (HandlerService.ListOutbounds: адреса, UUID,
      // ключи) и pprof на localhost без аутентификации для любого приложения.
      cfg..remove('api')..remove('metrics');

      // allowInsecure в xray v26 роняет старт всего конфига; без него узлы с
      // самоподписанным сертификатом отказывают только на рукопожатии.
      for (final o in (cfg['outbounds'] as List? ?? const []).whereType<Map<String, dynamic>>()) {
        (o['streamSettings']?['tlsSettings'] as Map?)?.remove('allowInsecure');
      }

      // Preserve the original socks inbound tag so server routing rules
      // (inboundTag: ["socks", "http"]) keep matching after we replace the inbound.
      final originalInbounds = List<dynamic>.from(cfg['inbounds'] as List? ?? []);
      final socksTag = originalInbounds
          .whereType<Map<String, dynamic>>()
          .where((i) => i['protocol'] == 'socks')
          .map((i) => i['tag'] as String?)
          .firstWhere((t) => t != null && t.isNotEmpty, orElse: () => null)
          ?? 'socks';

      cfg['inbounds'] = [
        {
          'tag': socksTag,
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
            'enabled': options.sniffingEnabled,
            if (options.sniffingEnabled) ...{
              'destOverride': ['http', 'tls', 'quic'],
              'routeOnly': true,
            },
          },
        },
      ];

      // DNS block is intentionally NOT replaced: managed configs carry their own DNS
      // routing configured for their outbound topology. Overriding it breaks dns-module
      // routing (no 'proxy' outbound exists in these configs) and causes DNS leaks.
      // User's custom DNS server and adblock settings do not apply to managed configs.
      cfg['log'] = _logBlock(options);

      _clampObservatoryInterval(cfg, options.obsProbeIntervalSec);
      _neutralizeDirectFallback(cfg);

      final appRules = <Map<String, dynamic>>[];

      // Adblock for managed configs: DNS-based blocking is unavailable (the DNS
      // block belongs to the server), so block ad domains via a routing rule to
      // the injected blackhole. Requires sniffing (routeOnly) for domain matching.
      if (options.routing.adBlockEnabled) {
        _ensureBlackholeOutbound(cfg);
        appRules.add({
          'type': 'field',
          'domain': [XrayDefaults.adBlockGeosite, 'geosite:win-spy'],
          'outboundTag': blackholeTag,
        });
      }

      // In direct DNS mode, intercept port 53 so it bypasses the tunnel.
      // In proxy DNS mode we leave DNS handling to the server config entirely.
      if (options.dnsMode == DnsMode.direct) {
        appRules.add({
          'type': 'field', 'port': '53', 'network': 'udp,tcp', 'outboundTag': 'direct',
        });
      }

      // Only inject rules that route to 'direct' — safe regardless of server outbound names.
      // onlySelected rules (→ 'proxy') are skipped: the server's own catch-all handles routing.
      final routing = options.routing;
      if (routing.direction == RoutingDirection.bypass) {
        appRules.addAll(_buildGeoRules(routing));
      } else if (routing.bypassLocal) {
        appRules.add({'type': 'field', 'ip': ['geoip:private'], 'outboundTag': 'direct'});
      }

      // No catch-all rule — the server's routing handles the remainder.

      if (appRules.isNotEmpty) {
        final serverRouting = cfg['routing'] as Map<String, dynamic>? ?? {};
        final serverRules = List<dynamic>.from(serverRouting['rules'] as List? ?? []);
        cfg['routing'] = {
          ...serverRouting,
          'rules': [...appRules, ...serverRules],
        };
      }

      return jsonEncode(cfg);
    } catch (e) {
      // Не отдаём конфиг как есть: в нём серверные inbounds (0.0.0.0, noauth).
      throw FormatException('Не удалось разобрать JSON-конфиг подписки: $e');
    }
  }

  /// Tag of the blackhole outbound injected into managed configs (fallback
  /// neutralization, adblock). Injected once by [_ensureBlackholeOutbound].
  static const blackholeTag = 'teapod-blackhole';

  /// Balancers in managed configs may declare `fallbackTag: "direct"` — when the
  /// leastLoad strategy has no qualified nodes (all marked dead, or the first
  /// seconds after start before observatory produced any probe results), xray
  /// would silently route user traffic OUTSIDE the VPN via the freedom outbound.
  /// That is a security leak: rewrite such fallbacks to the first proxy outbound
  /// matching the balancer's selector (fails via the VPN, works instantly on
  /// startup), or to a blackhole when no such outbound exists.
  static void _neutralizeDirectFallback(Map<String, dynamic> cfg) {
    final routing = cfg['routing'];
    if (routing is! Map<String, dynamic>) return;
    final balancers = routing['balancers'];
    if (balancers is! List) return;

    final outbounds = (cfg['outbounds'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final freedomTags = outbounds
        .where((o) => o['protocol'] == 'freedom')
        .map((o) => o['tag'] as String?)
        .whereType<String>()
        .toSet();

    for (final b in balancers.whereType<Map<String, dynamic>>()) {
      final fb = b['fallbackTag'];
      if (fb is! String || !freedomTags.contains(fb)) continue;
      final proxy = _firstSelectorOutbound(outbounds, b['selector']);
      if (proxy != null) {
        b['fallbackTag'] = proxy;
      } else {
        _ensureBlackholeOutbound(cfg);
        b['fallbackTag'] = blackholeTag;
      }
    }
  }

  /// First outbound tag matching a balancer selector (xray selectors are tag
  /// prefixes), skipping non-proxy protocols.
  static String? _firstSelectorOutbound(
    List<Map<String, dynamic>> outbounds,
    dynamic selector,
  ) {
    if (selector is! List) return null;
    const nonProxy = {'freedom', 'blackhole', 'dns', 'loopback'};
    final prefixes = selector.whereType<String>().toList();
    for (final o in outbounds) {
      final tag = o['tag'];
      if (tag is! String || nonProxy.contains(o['protocol'])) continue;
      if (prefixes.any(tag.startsWith)) return tag;
    }
    return null;
  }

  static void _ensureBlackholeOutbound(Map<String, dynamic> cfg) {
    final outbounds = cfg['outbounds'] as List<dynamic>? ?? (cfg['outbounds'] = <dynamic>[]);
    final exists = outbounds
        .whereType<Map<String, dynamic>>()
        .any((o) => o['tag'] == blackholeTag);
    if (!exists) {
      outbounds.add({'tag': blackholeTag, 'protocol': 'blackhole', 'settings': {}});
    }
  }

  /// Managed configs often ship aggressive observatory settings (e.g. probeInterval
  /// 30s with 20+ outbounds). On mobile that means a burst of concurrent TLS probes
  /// every interval: it saturates the LTE radio, drains battery and triggers
  /// server-side rate limiting that resets in-flight user connections. Clamp the
  /// probe interval to at least [minSec] (0 = keep the server's value).
  static void _clampObservatoryInterval(Map<String, dynamic> cfg, int minSec) {
    if (minSec <= 0) return;
    for (final key in ['observatory', 'burstObservatory']) {
      final obs = cfg[key];
      if (obs is! Map<String, dynamic>) continue;
      final raw = obs['probeInterval'];
      if (raw is String && _intervalToSeconds(raw) < minSec) {
        obs['probeInterval'] = '${minSec}s';
      }
    }
  }

  /// Parses xray duration strings ("30s", "5m", "1h"). Unknown formats → max int
  /// so we never touch values we cannot read.
  static int _intervalToSeconds(String v) {
    final m = RegExp(r'^(\d+)(s|m|h)?$').firstMatch(v.trim());
    if (m == null) return 1 << 30;
    final n = int.parse(m.group(1)!);
    switch (m.group(2)) {
      case 'h':
        return n * 3600;
      case 'm':
        return n * 60;
      default:
        return n;
    }
  }
}
