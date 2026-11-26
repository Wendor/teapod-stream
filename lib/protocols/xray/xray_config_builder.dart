import 'dart:convert';
import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/app_message.dart';
import '../../core/models/vpn_config.dart';
import '../../core/models/dns_config.dart';
import '../../core/models/routing_settings.dart';
import '../../core/models/xray_tuning.dart';
import '../../core/constants/routing_defaults.dart';
import '../../core/constants/xray_defaults.dart';
import '../../core/models/vpn_log_entry.dart' show LogLevel;
import '../../core/models/app_settings.dart' show DnsQueryStrategy, TlsFingerprint;
import '../../core/services/ip_lookup.dart';

class XrayConfigBuilder {
  /// Profiles xray-core v26 rejects at startup (`PrintRemovedFeatureError`
  /// and a broken pin): without the check they would fail with "xray failed to start" and
  /// end up among urltest candidates. null — the profile builds.
  static AppMessage? unsupportedReason(VpnConfig config) {
    if (config.protocol.hasProtocolSettings) return config.protocol.singBoxOnlyReason;
    if (config.rawXrayConfig != null) return null;
    if (config.transport == VpnTransport.http2 || config.transport == VpnTransport.quic) {
      return AppMessage.l10n((l) => l.xrayNoH2Quic);
    }
    if (config.protocol == VpnProtocol.shadowsocks && config.plugin != null) {
      return AppMessage.l10n((l) => l.xrayNoSsPlugins);
    }
    final pin = config.pinSHA256?.trim() ?? '';
    if (pin.isNotEmpty) {
      try {
        certificatePins(pin);
      } on FormatException catch (e) {
        return ReasonException.of(e);
      }
    }
    final tls = config.security == VpnSecurity.tls || config.protocol == VpnProtocol.hysteria2;
    if (tls && config.allowInsecure && pin.isEmpty) {
      return AppMessage.l10n((l) => l.xrayInsecure);
    }
    return null;
  }

  /// Tag of the app's SOCKS inbound.
  static const socksInTag = 'socks-in';

  /// The generated config, assembled from the named parts below. [RustConfigBuilder] takes the same parts
  /// by name, so reordering or adding a part here doesn't shift what it builds.
  static Map<String, dynamic> build(VpnConfig config, VpnEngineOptions options) => {
    'log': logBlock(options),
    'dns': buildDnsBlock(options),
    'inbounds': [socksInbound(options)],
    'outbounds': [
      proxyOutbound(config, options),
      if (_dialerApplies(config, options)) _buildDialerOutbound(config, options),
      directOutbound,
      dnsOutbound,
      blockOutbound,
    ],
    'routing': {
      'domainStrategy': 'IPIfNonMatch',
      'rules': [
        // QUIC blocking is handled at the TUN level by tun2socks, which replies
        // with an ICMP Port Unreachable so the browser falls back to TCP immediately.
        // No xray routing rule is needed: silently dropping UDP/443 here (blackhole)
        // would force browsers to wait ~55s for QUIC retransmission to time out,
        // and rerouting QUIC to 'direct' would leak the destination outside the tunnel.
        ...dnsRules(options),
        if (!options.enableUdp) _udpBlockRule(socksInTag, 'block'),
        ...geoRules(options.routing),
        ...diagnosticRules(options),
        catchAllRule(options.routing),
      ],
    },
    'policy': _policyBlock,
  };

  /// The SOCKS5 inbound tun2socks and the app's own checks connect to.
  static Map<String, dynamic> socksInbound(VpnEngineOptions options) => {
    'tag': socksInTag,
    'protocol': 'socks',
    'port': options.socksPort,
    'listen': XrayDefaults.socksListen,
    'settings': {
      'auth': options.socksUser.isNotEmpty ? 'password' : 'noauth',
      if (options.socksUser.isNotEmpty)
        'accounts': [
          {'user': options.socksUser, 'pass': options.socksPassword},
        ],
      // UDP ASSOCIATE is always needed: tun2socks sends app DNS through it.
      // Disabled UDP is cut by the _udpBlockRule rule (except port 53).
      'udp': true,
    },
    'sniffing': {
      'enabled': options.sniffingEnabled,
      if (options.sniffingEnabled) ...{
        'destOverride': ['http', 'tls', 'quic'],
        // routeOnly=true: sniffed domain is used for routing only — xray does NOT replace
        // the connection destination. Without this, xray re-resolves the domain and
        // redirects the connection to a different IP, breaking tun2socks and leaking DNS.
        'routeOnly': true,
      },
    },
  };

  static Map<String, dynamic> get directOutbound => {'tag': 'direct', 'protocol': 'freedom'};

  static Map<String, dynamic> get dnsOutbound => {'tag': 'dns-out', 'protocol': 'dns'};

  static Map<String, dynamic> get blockOutbound => {'tag': 'block', 'protocol': 'blackhole'};

  /// App DNS goes to xray's DNS module with the selected server. Its own sockets egress through the tunnel
  /// in proxy mode, or past it in direct mode (xray's process is excluded from the TUN) — as if there were
  /// no VPN. Port 53 from [inbounds] goes to `dns-out`.
  static List<Map<String, dynamic>> dnsRules(VpnEngineOptions options, {List<String> inbounds = const [socksInTag]}) =>
      [
        {
          'type': 'field',
          'inboundTag': ['dns-module'],
          'outboundTag': options.dnsMode == DnsMode.proxy ? 'proxy' : 'direct',
        },
        {'type': 'field', 'inboundTag': inbounds, 'port': '53', 'network': 'udp,tcp', 'outboundTag': 'dns-out'},
      ];

  /// In ONLY mode the catch-all routes to direct, so diagnostic hosts that aren't in the user's rules would
  /// bypass the proxy and may be blocked locally. Force them via proxy so heartbeat and IP detection always
  /// test the tunnel. The custom probe URL too: otherwise it would measure the direct internet, not the tunnel.
  static List<Map<String, dynamic>> diagnosticRules(VpnEngineOptions options) {
    if (options.routing.direction != RoutingDirection.onlySelected) return [];
    final probeHost = Uri.tryParse(options.heartbeat.url)?.host ?? '';
    return [
      {
        'type': 'field',
        'domain': [
          'full:cp.cloudflare.com',
          for (final h in IpLookupSource.hosts) 'full:$h',
          if (probeHost.isNotEmpty && !_isIpAddress(probeHost)) 'full:$probeHost',
        ],
        'outboundTag': 'proxy',
      },
      if (_isIpAddress(probeHost))
        {
          'type': 'field',
          'ip': [probeHost],
          'outboundTag': 'proxy',
        },
    ];
  }

  /// The last rule: everything else from the SOCKS inbound.
  static Map<String, dynamic> catchAllRule(RoutingSettings routing) => {
    'type': 'field',
    'inboundTag': [socksInTag],
    'outboundTag': routing.direction == RoutingDirection.onlySelected ? 'direct' : 'proxy',
  };

  static Map<String, dynamic> get _policyBlock => {
    'levels': {
      '0': {
        'handshake': XrayDefaults.handshakeTimeout,
        'connIdle': XrayDefaults.connIdleTimeout,
        'uplinkOnly': XrayDefaults.uplinkOnlyTimeout,
        'downlinkOnly': XrayDefaults.downlinkOnlyTimeout,
      },
    },
    'system': {'statsInboundUplink': false, 'statsInboundDownlink': false},
  };

  /// Access log (a line per connection: JNI → logcat + log file, essentially
  /// browsing history on disk) — debug only. xray writes dial errors
  /// to the info-level error log, so they stay.
  static Map<String, dynamic> logBlock(VpnEngineOptions options) => {
    'loglevel': options.logLevel.name,
    if (options.logLevel != LogLevel.debug) 'access': 'none',
  };

  static List<Map<String, dynamic>> geoRules(RoutingSettings routing) {
    if (!routing.isActive) return [];

    final rules = <Map<String, dynamic>>[];

    // Private IPs always bypass regardless of direction
    if (routing.bypassLocal) {
      rules.add({
        'type': 'field',
        'ip': ['geoip:private'],
        'outboundTag': 'direct',
      });
    }

    if (!routing.geoEnabled &&
        !routing.domainEnabled &&
        !routing.geositeEnabled &&
        !routing.sitesEnabled &&
        !routing.ruServicesEnabled) {
      return rules;
    }

    final selectedOut = routing.direction == RoutingDirection.bypass ? 'direct' : 'proxy';

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
      rules.add({'type': 'field', 'domain': RoutingDefaults.ruServicesDomains, 'outboundTag': selectedOut});
    }

    return rules;
  }

  static String _queryStrategy(DnsQueryStrategy s) => switch (s) {
    DnsQueryStrategy.ipv4Only => 'UseIPv4',
    DnsQueryStrategy.ipv6Only => 'UseIPv6',
    DnsQueryStrategy.auto => 'UseIP',
  };

  static Map<String, dynamic> buildDnsBlock(VpnEngineOptions options) {
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
        'domains': [for (final code in options.adBlockCodes) 'geosite:$code'],
      });
    }

    final hosts = <String, String>{};
    if (server.domain != null && server.fallbackIp != null) {
      hosts[server.domain!] = server.fallbackIp!;
    } else if (server.type == DnsType.doh || server.type == DnsType.dot) {
      // Bootstrap for domain-based custom DoH/DoT: without a static hosts entry,
      // xray can't resolve the server hostname (circular dependency).
      final host = server.type == DnsType.doh ? (Uri.tryParse(server.address)?.host ?? '') : server.address;
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

  /// Tag of the helper freedom outbound the proxy dials the server
  /// through: fragmentation (TCP) and noise (UDP) live there.
  static const _dialerTag = 'dialer-out';

  /// Fragment splits the TCP stream — not applicable to hysteria2 (QUIC over UDP).
  static bool _fragmentApplies(VpnConfig config, VpnEngineOptions options) =>
      options.fragment.enabled && options.fragment.isValid && config.protocol != VpnProtocol.hysteria2;

  /// Noise is written only to the UDP leg (`proxy/freedom`: the non-TCP branch), i.e.
  /// it really works for Hysteria2 and the QUIC transport. Harmless for TCP.
  static bool _noiseApplies(VpnEngineOptions options) => options.noise.enabled && options.noise.isValid;

  static bool _dialerApplies(VpnConfig config, VpnEngineOptions options) =>
      _fragmentApplies(config, options) || _noiseApplies(options);

  /// Mux is useless over hysteria2 (QUIC multiplexes itself). The global setting skips xhttp: it has
  /// its own xmux, and Xray's xhttp inbounds refuse TCP inside Mux. `mux=on|off` in the link
  /// overrides both for one server ([VpnConfig.mux]).
  static bool _muxApplies(VpnConfig config, VpnEngineOptions options) {
    if (config.protocol == VpnProtocol.hysteria2) return false;
    return config.mux ?? (options.mux.enabled && config.transport != VpnTransport.xhttp);
  }

  /// TCP_USER_TIMEOUT: a connection where DPI silently drops packets breaks after
  /// 30 s of unacknowledged data instead of hanging in retransmission until tcp_retries2.
  static const _tcpUserTimeoutMs = 30000;

  static Map<String, dynamic> _buildDialerOutbound(VpnConfig config, VpnEngineOptions options) {
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
          'fragment': {'packets': f.packets.trim(), 'length': f.length.trim(), 'interval': f.interval.trim()},
        if (_noiseApplies(options))
          'noises': [
            {'type': n.type.name, 'packet': n.packet.trim(), 'delay': n.delay.trim()},
          ],
      },
    };
  }

  /// XTLS Vision is incompatible with TCP mux: the server drops mux connections with TCP requests
  /// (see proxy/vless/outbound). Only the XUDP branch is kept — `concurrency: -1`.
  static Map<String, dynamic> _buildMux(VpnConfig config, MuxSettings mux) {
    final vision = config.flow?.contains('xtls-rprx-vision') ?? false;
    return {
      'enabled': true,
      'concurrency': vision ? -1 : mux.concurrency,
      'xudpConcurrency': mux.xudpConcurrency,
      'xudpProxyUDP443': mux.xudpProxyUDP443.name,
    };
  }

  static Map<String, dynamic> proxyOutbound(VpnConfig config, VpnEngineOptions options) {
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
                {'id': config.uuid, 'encryption': config.encryption ?? 'none', 'flow': config.flow ?? ''},
              ],
            },
          ],
        };
      case VpnProtocol.vmess:
        return {
          'vnext': [
            {
              'address': config.address,
              'port': config.port,
              'users': [
                {'id': config.uuid, 'security': 'auto'},
              ],
            },
          ],
        };
      case VpnProtocol.trojan:
        return {
          'servers': [
            {'address': config.address, 'port': config.port, 'password': config.password ?? ''},
          ],
        };
      case VpnProtocol.shadowsocks:
        return {
          'servers': [
            {
              'address': config.address,
              'port': config.port,
              'method': config.method ?? 'chacha20-ietf-poly1305',
              'password': config.password ?? '',
            },
          ],
        };
      case VpnProtocol.hysteria2:
        return {'version': 2, 'address': config.address, 'port': config.port};
      case VpnProtocol.wireguard || VpnProtocol.ssh || VpnProtocol.naive:
        throw ReasonException(config.protocol.singBoxOnlyReason);
    }
  }

  // xray uses "h2" for HTTP/2, not the enum name "http2".
  static String _networkName(VpnTransport t) => t == VpnTransport.http2 ? 'h2' : t.name;

  /// `pinnedPeerCertSha256`: SHA-256 of the full DER certificate in hex, comma-separated.
  /// `pinSHA256` from the link — hex (with or without colons) or base64 of 32 bytes.
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
        throw ReasonException(AppMessage.l10n((l) => l.xrayPinFormat));
      }
    }
    return pins.join(',');
  }

  static Map<String, dynamic> _buildStreamSettings(VpnConfig config, TlsFingerprint fp) {
    // Global override from app settings; defaultFp — the value from the config.
    final fingerprint = fp.xrayValue ?? config.fingerprint;
    // A pin beats allowInsecure: only this certificate is accepted.
    final pin = config.pinSHA256?.trim() ?? '';
    if (config.protocol == VpnProtocol.hysteria2) {
      final salamander = config.obfsPassword?.isNotEmpty ?? false;
      // Gecko is Xray's salamander mask with a packetSize range.
      final gecko = config.geckoPacketSize;
      final hopping = config.hopPorts?.isNotEmpty ?? false;
      return {
        'network': 'hysteria',
        'security': 'tls',
        'tlsSettings': {
          // hysteria-dialer in xray doesn't call WithDestination: with an empty serverName
          // the SNI is taken from the auth request URL and becomes the literal "hysteria".
          'serverName': (config.sni?.isNotEmpty ?? false) ? config.sni : config.address,
          'allowInsecure': config.allowInsecure && pin.isEmpty,
          if (pin.isNotEmpty) 'pinnedPeerCertSha256': certificatePins(pin),
        },
        'hysteriaSettings': {'version': 2, 'auth': config.password ?? ''},
        if (salamander || hopping)
          'finalmask': {
            'udp': [
              // Xray-core ≥ v26.9.9: port hopping is the udphop UDP mask (previously
              // quicParams.udpHop). A mask with its own dialing must come
              // first. A new socket + random port every 30 s — as in Hysteria.
              if (hopping)
                {
                  'type': 'udphop',
                  'settings': {'mode': 'intervalLocal,intervalRemote', 'remotePorts': config.hopPorts},
                },
              if (salamander)
                {
                  'type': 'salamander',
                  'settings': {
                    'password': config.obfsPassword,
                    if (gecko != null) 'packetSize': '${gecko.$1}-${gecko.$2}',
                  },
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
          if (fingerprint != null && fingerprint.isNotEmpty) 'fingerprint': fingerprint,
          if (config.alpn != null && config.alpn!.isNotEmpty)
            'alpn': config.alpn!.split(',').map((s) => s.trim()).toList(),
          // The Xray-core key is echConfigList; the old echSettings was silently ignored.
          if (config.ech != null && config.ech!.isNotEmpty) 'echConfigList': config.ech,
        },
      if (config.tcpHttpHeader)
        'tcpSettings': {
          'header': {
            'type': 'http',
            'request': {
              'path': _csv(config.wsPath ?? '/', fallback: '/'),
              'headers': {if (config.wsHost?.isNotEmpty ?? false) 'Host': _csv(config.wsHost!)},
            },
          },
        },
      if (config.transport == VpnTransport.ws)
        'wsSettings': {
          'path': config.wsPath ?? '/',
          'headers': {'Host': config.wsHost ?? ''},
        },
      if (config.transport == VpnTransport.grpc) 'grpcSettings': {'serviceName': config.grpcServiceName ?? ''},
      if (config.transport == VpnTransport.xhttp)
        'xhttpSettings': {
          'path': config.wsPath ?? '/',
          if (config.wsHost != null && config.wsHost!.isNotEmpty) 'host': config.wsHost,
          if (config.xhttpMode != null && config.xhttpMode!.isNotEmpty) 'mode': config.xhttpMode,
          if (config.xhttpExtra != null && config.xhttpExtra!.isNotEmpty) 'extra': config.xhttpExtra,
        },
      if (config.transport == VpnTransport.splithttp)
        'splithttpSettings': {
          'path': config.wsPath ?? '/',
          if (config.wsHost != null && config.wsHost!.isNotEmpty) 'host': config.wsHost,
        },
      if (config.transport == VpnTransport.httpupgrade)
        'httpupgradeSettings': {
          'path': config.wsPath ?? '/',
          if (config.wsHost != null && config.wsHost!.isNotEmpty) 'host': config.wsHost,
        },
      if (config.finalmask != null && config.finalmask!.isNotEmpty) 'finalmask': config.finalmask,
    };
  }

  static List<String> _csv(String value, {String? fallback}) {
    final items = [
      for (final v in value.split(','))
        if (v.trim().isNotEmpty) v.trim(),
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
  /// observatory, custom outbound tags). Only the sections in [_managedTopLevelKeys] are
  /// kept; port/credentials, log and safe bypass rules (→ direct) are overlaid.
  static String mergeWithRaw(String rawConfig, VpnEngineOptions options) {
    try {
      final cfg = jsonDecode(rawConfig) as Map<String, dynamic>;

      // Only the sections a client config needs. Everything else (api/metrics: unauthenticated
      // gRPC and pprof on localhost; reverse; env; geodata; transport) is dropped. Exact
      // spelling only: xray matches keys case-insensitively, so `Inbounds` would override ours.
      cfg.removeWhere((key, _) => !_managedTopLevelKeys.contains(key));

      for (final o in (cfg['outbounds'] as List? ?? const []).whereType<Map<String, dynamic>>()) {
        // allowInsecure in xray v26 breaks startup of the whole config; without it nodes with
        // a self-signed certificate fail only at the handshake.
        (o['streamSettings']?['tlsSettings'] as Map?)?.remove('allowInsecure');
        _dropReverse(o);
      }

      // Preserve the original socks inbound tag so server routing rules
      // (inboundTag: ["socks", "http"]) keep matching after we replace the inbound.
      final originalInbounds = List<dynamic>.from(cfg['inbounds'] as List? ?? []);
      final socksTag =
          originalInbounds
              .whereType<Map<String, dynamic>>()
              .where((i) => i['protocol'] == 'socks')
              .map((i) => i['tag'] as String?)
              .firstWhere((t) => t != null && t.isNotEmpty, orElse: () => null) ??
          'socks';

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
                {'user': options.socksUser, 'pass': options.socksPassword},
              ],
            // UDP ASSOCIATE is always needed: tun2socks sends app DNS through it.
            // Disabled UDP is cut by the _udpBlockRule rule (except port 53).
            'udp': true,
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
      cfg['log'] = logBlock(options);

      _clampObservatoryInterval(cfg, options.obsProbeIntervalSec);
      _neutralizeDirectFallback(cfg);

      final appRules = <Map<String, dynamic>>[];

      // Adblock for managed configs: DNS-based blocking is unavailable (the DNS
      // block belongs to the server), so block ad domains via a routing rule to
      // the injected blackhole. Requires sniffing (routeOnly) for domain matching.
      if (options.routing.adBlockEnabled) {
        appRules.add({
          'type': 'field',
          'domain': [for (final code in options.adBlockCodes) 'geosite:$code'],
          'outboundTag': _ensureBlackholeOutbound(cfg),
        });
      }

      // In direct DNS mode, intercept port 53 so it bypasses the tunnel.
      // In proxy DNS mode we leave DNS handling to the server config entirely.
      if (options.dnsMode == DnsMode.direct) {
        appRules.add({'type': 'field', 'port': '53', 'network': 'udp,tcp', 'outboundTag': 'direct'});
      }

      if (!options.enableUdp) {
        appRules.add(_udpBlockRule(socksTag, _ensureBlackholeOutbound(cfg)));
      }

      // Only inject rules that route to 'direct' — safe regardless of server outbound names.
      // onlySelected rules (→ 'proxy') are skipped: the server's own catch-all handles routing.
      final routing = options.routing;
      if (routing.direction == RoutingDirection.bypass) {
        appRules.addAll(geoRules(routing));
      } else if (routing.bypassLocal) {
        appRules.add({
          'type': 'field',
          'ip': ['geoip:private'],
          'outboundTag': 'direct',
        });
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
      // Don't pass the config as is: it has server inbounds (0.0.0.0, noauth).
      throw ReasonException(AppMessage.l10n((l) => l.xrayRawJsonParse('$e')));
    }
  }

  /// Top-level sections kept from a managed config; `inbounds` and `log` are then replaced.
  static const _managedTopLevelKeys = {
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

  /// Removes `reverse` from outbound settings (the VLESS simplified style and `vnext` users) at any
  /// depth. xray matches keys in any letter case, so `Settings`, `Vnext` and `Reverse` count too.
  static void _dropReverse(Map<String, dynamic> outbound) {
    void walk(Object? node) {
      if (node is Map<String, dynamic>) {
        node.removeWhere((key, _) => key.toLowerCase() == 'reverse');
        node.values.forEach(walk);
      } else if (node is List) {
        node.forEach(walk);
      }
    }

    for (final e in outbound.entries) {
      if (e.key.toLowerCase() == 'settings') walk(e.value);
    }
  }

  /// Disabled UDP: all UDP from the socks inbound, except DNS to port 53, goes to blackhole.
  static Map<String, dynamic> _udpBlockRule(String inbound, String outbound) => {
    'type': 'field',
    'inboundTag': [inbound],
    'network': 'udp',
    'port': '1-52,54-65535',
    'outboundTag': outbound,
  };

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

    final outbounds = (cfg['outbounds'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>().toList();
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
        b['fallbackTag'] = _ensureBlackholeOutbound(cfg);
      }
    }
  }

  /// First outbound tag matching a balancer selector (xray selectors are tag
  /// prefixes), skipping non-proxy protocols.
  static String? _firstSelectorOutbound(List<Map<String, dynamic>> outbounds, dynamic selector) {
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

  /// Tag of the blackhole outbound. If [blackholeTag] is taken by a server outbound
  /// of another protocol, it stays as is (server rules may point to it),
  /// and the blackhole gets a free tag with a suffix.
  static String _ensureBlackholeOutbound(Map<String, dynamic> cfg) {
    final outbounds = cfg['outbounds'] as List<dynamic>? ?? (cfg['outbounds'] = <dynamic>[]);
    final byTag = {
      for (final o in outbounds.whereType<Map<String, dynamic>>())
        if (o['tag'] case final String t) t: o['protocol'],
    };
    var tag = blackholeTag;
    for (var i = 2; byTag.containsKey(tag) && byTag[tag] != 'blackhole'; i++) {
      tag = '$blackholeTag-$i';
    }
    if (!byTag.containsKey(tag)) outbounds.add({'tag': tag, 'protocol': 'blackhole', 'settings': <String, dynamic>{}});
    return tag;
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
