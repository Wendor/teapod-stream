// Based on RustConfigBuilder from PR #152 (vivatfreedom).
import 'dart:convert';
import 'dart:math';

import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/routing_settings.dart';
import '../../core/models/vpn_config.dart';
import '../../core/models/xray_tuning.dart';
import 'vless_parser.dart';
import 'xray_config_builder.dart';
import '../../l10n/l10n.dart';

/// Profiles xray-rust 0.8.1 runs through Android TUN: VLESS, Trojan, VMess
/// AEAD, Shadowsocks 2022 and Hysteria2, assembled from the Go builder's
/// named parts into the subset `docs/config-compatibility.md` accepts.
///
/// TLS certificate pins win over `allowInsecure`: a profile with both is built
/// with `allowInsecure: false` and `pinnedPeerCertSha256`, so the server must
/// present exactly the pinned certificate — stricter than the request, and the
/// usual intent of such links (a self-signed server identified by its pin).
/// xray-rust, like current Xray-core, has no unverified mode, so
/// `allowInsecure` without a pin is rejected.
class RustConfigBuilder {
  static const visionFlows = {'xtls-rprx-vision', 'xtls-rprx-vision-udp443'};

  /// xray-rust 0.9.0 (`shadowsocks2022::Cipher`): SS2022 only, no AEAD-2017.
  static const ss2022Methods = {'2022-blake3-aes-128-gcm', '2022-blake3-aes-256-gcm', '2022-blake3-chacha20-poly1305'};

  /// VMess AEAD body ciphers (`vmess::Cipher`). The core refuses `none`,
  /// `zero` and CFB; a link's other `scy` is sent as `auto`, as Go always does.
  static const vmessCiphers = {'auto', 'aes-128-gcm', 'chacha20-poly1305'};

  static const _transports = {
    VpnTransport.tcp,
    VpnTransport.ws,
    VpnTransport.httpupgrade,
    VpnTransport.grpc,
    VpnTransport.xhttp,
    VpnTransport.splithttp,
  };
  static const _urlTransports = {'tcp', 'raw', 'ws', 'websocket', 'httpupgrade', 'grpc', 'xhttp', 'splithttp'};

  static bool supports(VpnConfig config) => unsupportedReason(config) == null;

  static String? unsupportedReason(VpnConfig config) {
    if (config.protocol.hasProtocolSettings) return config.protocol.singBoxOnlyReason;
    if (config.rawXrayConfig != null) {
      return L10n.current.rustNoRawJson;
    }
    // Go inserts fm from the link into streamSettings as is; xray-rust accepts
    // only a narrow subset of FinalMask, which this builder assembles itself.
    if (config.finalmask?.isNotEmpty ?? false) {
      return L10n.current.rustNoFinalmask;
    }
    if (config.protocol != VpnProtocol.hysteria2 && (VlessParser.linkMux(config) ?? false)) {
      return L10n.current.rustLinkMux;
    }
    return switch (config.protocol) {
      VpnProtocol.hysteria2 => _hysteria2UnsupportedReason(config),
      VpnProtocol.vless => _vlessUnsupportedReason(config),
      VpnProtocol.trojan => _trojanUnsupportedReason(config),
      VpnProtocol.vmess => _vmessUnsupportedReason(config),
      VpnProtocol.shadowsocks => _shadowsocksUnsupportedReason(config),
      VpnProtocol.wireguard || VpnProtocol.ssh || VpnProtocol.naive => config.protocol.singBoxOnlyReason,
    };
  }

  static String? _vlessUnsupportedReason(VpnConfig config) {
    if (config.encryption != null && config.encryption != 'none') {
      return L10n.current.rustVlessEncryption;
    }
    if (!_isUuid(config.uuid)) {
      return L10n.current.rustVlessUuid;
    }
    final params = VlessParser.linkParams(config);
    final carrier = _carrierReason(config, declaredTransport: params['type'], headerType: params['headerType']);
    if (carrier != null) return carrier;
    if (config.security != VpnSecurity.tls && config.security != VpnSecurity.reality) {
      return L10n.current.rustVlessSecurity;
    }
    final flow = config.flow ?? '';
    if (flow.isNotEmpty && !visionFlows.contains(flow)) {
      return L10n.current.rustVlessFlow;
    }
    // xray-rust 0.8.0 fixed Vision over plain TLS on RAW; on WS,
    // HTTPUpgrade, gRPC and xHTTP the core still rejects Vision without VLESS encryption
    // before connecting, as Xray-core does.
    if (flow.isNotEmpty && config.transport != VpnTransport.tcp) {
      return L10n.current.rustVision;
    }
    return null;
  }

  static String? _trojanUnsupportedReason(VpnConfig config) {
    final password = config.password ?? '';
    if (password.isEmpty || utf8.encode(password).length > 4096) {
      return L10n.current.rustTrojanPassword;
    }
    final params = VlessParser.linkParams(config);
    final carrier = _carrierReason(config, declaredTransport: params['type'], headerType: params['headerType']);
    if (carrier != null) return carrier;
    // xray-rust rejects Trojan without TLS/Reality for a public server.
    if (config.security != VpnSecurity.tls && config.security != VpnSecurity.reality) {
      return L10n.current.rustTrojanSecurity;
    }
    return null;
  }

  static String? _vmessUnsupportedReason(VpnConfig config) {
    if (!_isUuid(config.uuid)) {
      return L10n.current.rustVmessId;
    }
    // aid from the link isn't applied, as in Go: alterId isn't written to the config,
    // the client always speaks VMess AEAD, and an Xray/v2fly 4.28+ server accepts
    // AEAD with any alterId of its own.
    final json = VlessParser.vmessJson(config);
    // The parser treats anything but an exact tls as no security: reality from
    // the link would silently turn into VMess without TLS.
    final rawTls = json['tls']?.toString() ?? '';
    final tls = rawTls.trim().toLowerCase();
    if (tls.isNotEmpty && tls != 'tls' && tls != 'none') {
      return L10n.current.rustVmessSecurity(tls);
    }
    // "TLS" or " tls" isn't recognized by the parser either: the profile would hit the TLS port
    // with bare VMess.
    if (tls == 'tls' && config.security != VpnSecurity.tls) {
      return L10n.current.rustVmessTls(rawTls);
    }
    return _carrierReason(config, declaredTransport: json['net']?.toString(), headerType: json['type']?.toString());
  }

  static String? _shadowsocksUnsupportedReason(VpnConfig config) {
    final method = config.method ?? '';
    if (!ss2022Methods.contains(method)) {
      return L10n.current.rustSsMethod(method);
    }
    final keys = _ss2022KeyReason(method, config.password ?? '');
    if (keys != null) return keys;
    if (VlessParser.linkParams(config)['plugin']?.trim().isNotEmpty ?? false) {
      return L10n.current.rustSsPlugin;
    }
    if (config.ssPrefix?.isNotEmpty ?? false) {
      return L10n.current.rustSsPrefix;
    }
    return null;
  }

  /// Transport, TCP header and outer TLS/REALITY rules shared by the protocols
  /// on xray-rust's stream carriers (VLESS, Trojan, VMess).
  static String? _carrierReason(VpnConfig config, {String? declaredTransport, String? headerType}) {
    final declared = declaredTransport?.trim().toLowerCase() ?? '';
    if (!_transports.contains(config.transport) || (declared.isNotEmpty && !_urlTransports.contains(declared))) {
      return L10n.current.rustTransport;
    }
    // The parser doesn't read headerType: without the check TCP with HTTP camouflage would silently
    // go out as bare TCP. xray-rust accepts only header.type none.
    final header = headerType?.trim().toLowerCase() ?? '';
    if (config.transport == VpnTransport.tcp && header.isNotEmpty && header != 'none') {
      return L10n.current.rustTcpHeader(header);
    }
    if (config.security == VpnSecurity.reality &&
        (config.transport == VpnTransport.ws || config.transport == VpnTransport.httpupgrade)) {
      return L10n.current.rustReality;
    }
    if (config.security == VpnSecurity.tls && _insecureWithoutPin(config)) {
      return _insecureReason;
    }
    if (config.ech?.isNotEmpty ?? false) {
      return L10n.current.rustEch;
    }
    return null;
  }

  /// The link's AEAD `scy` (v2 JSON field), which `vmess::Cipher::parse`
  /// accepts. Go always sends `auto`, and the server reads the body cipher
  /// from the request header, so any other value (`none`, `zero`, CFB, or
  /// none given) is sent as `auto` too.
  static String _vmessCipher(Map<String, dynamic> json) {
    final scy = json['scy']?.toString().trim().toLowerCase() ?? '';
    return vmessCiphers.contains(scy) ? scy : 'auto';
  }

  /// `shadowsocks2022::Method::new`: colon-separated padded standard base64
  /// keys, each at least the cipher's key length (longer keys are hashed),
  /// at most eight AES identity keys, one ChaCha key, 8192 encoded bytes.
  static String? _ss2022KeyReason(String method, String password) {
    final keyLength = method == '2022-blake3-aes-128-gcm' ? 16 : 32;
    final keys = password.split(':');
    final chacha = method == '2022-blake3-chacha20-poly1305';
    if (password.isEmpty || utf8.encode(password).length > 8192 || keys.length > 8 || (chacha && keys.length != 1)) {
      return chacha ? L10n.current.rustSsOneKey(method) : L10n.current.rustSsMaxKeys(method);
    }
    for (final key in keys) {
      final decoded = _strictBase64(key);
      if (decoded == null || decoded.length < keyLength) {
        return L10n.current.rustSsKey(method, keyLength);
      }
    }
    return null;
  }

  /// Standard padded base64, as the `base64` crate's STANDARD engine decodes.
  static List<int>? _strictBase64(String value) {
    if (value.isEmpty || value.length % 4 != 0 || !RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(value)) {
      return null;
    }
    try {
      return base64.decode(value);
    } on FormatException {
      return null;
    }
  }

  static final _uuid = RegExp(
    r'^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|[0-9a-fA-F]{32})$',
  );

  static bool _isUuid(String value) => _uuid.hasMatch(value.trim());

  /// xray-rust 0.7.0 caps a config at 250,000 domain matchers
  /// (MAX_CONFIG_DOMAIN_MATCHERS), shared by routing and DNS-outbound rules, and
  /// expands each geosite entry into one matcher. Ad blocking alone takes about
  /// 187k (category-ads-all 186,402 + win-spy 327 in the bundled Loyalsoldier
  /// 202609082347), so a GeoSite rule with one of these (cn 111,168,
  /// china-list 110,433) cannot be parsed and the VPN would not start.
  static const largeGeositeCodes = {'cn', 'china-list', 'category-ads-all'};

  static String get _insecureReason => L10n.current.rustInsecure;

  static bool _hasPin(VpnConfig config) => config.pinSHA256?.trim().isNotEmpty ?? false;

  static bool _insecureWithoutPin(VpnConfig config) => config.allowInsecure && !_hasPin(config);

  /// xray-rust 0.9.0: Hysteria2 over stock QUIC TLS (h3), default BBR, with
  /// optional FinalMask Salamander and `quicParams.udpHop` in Xray-core
  /// v26.7.28's spelling (the Go builder's `udphop` mask is converted back). Brutal,
  /// bandwidth and other QUIC overrides and sockopt stay rejected by the core.
  static String? _hysteria2UnsupportedReason(VpnConfig config) {
    // The parser takes the password only for obfs=salamander: another type or an empty
    // password Go silently drops and connects without obfuscation.
    final obfs = VlessParser.linkParams(config)['obfs']?.trim() ?? '';
    if (obfs.isNotEmpty && obfs != 'none' && obfs != 'salamander') {
      return L10n.current.rustHy2Obfs(obfs);
    }
    final salamander = config.obfsPassword ?? '';
    if (obfs == 'salamander' && salamander.isEmpty) {
      return L10n.current.rustSalamanderNoPassword;
    }
    if (salamander.isNotEmpty && (utf8.encode(salamander).length < 4 || utf8.encode(salamander).length > 4096)) {
      return L10n.current.rustSalamanderPassword;
    }
    final hop = config.hopPorts ?? '';
    if (hop.isNotEmpty && _expandedPortCount(hop) > 65535) {
      return L10n.current.rustPortHopping;
    }
    final auth = config.password ?? '';
    if (auth.isEmpty || utf8.encode(auth).length > 4096 || auth.codeUnits.any((c) => c < 0x20 || c == 0x7f)) {
      return L10n.current.rustHy2Password;
    }
    if (_insecureWithoutPin(config)) return _insecureReason;
    if (config.ech?.isNotEmpty ?? false) {
      return L10n.current.rustEch;
    }
    return null;
  }

  /// Ports in a normalized hop list (`443,5000-6000`), duplicates included,
  /// as `parse_quic_udp_hop_ports` expands them.
  static int _expandedPortCount(String ports) {
    var count = 0;
    for (final part in ports.split(',')) {
      final bounds = part.split('-').map((p) => int.tryParse(p.trim()) ?? 0);
      count += bounds.last - bounds.first + 1;
    }
    return count;
  }

  static Map<String, dynamic> build(VpnConfig config, VpnEngineOptions options) {
    final reason = unsupportedReason(config);
    if (reason != null) throw FormatException(reason);
    if (options.proxyOnly) {
      throw FormatException(L10n.current.rustTunOnly);
    }
    // Go doesn't apply Mux to Hysteria2 (QUIC multiplexes streams itself),
    // so it doesn't get in the way here either.
    final hysteria2 = config.protocol == VpnProtocol.hysteria2;
    if (options.mux.enabled && !hysteria2) {
      throw FormatException(L10n.current.rustMux);
    }
    if (options.mtu != 1500) {
      throw FormatException(L10n.current.rustMtu);
    }
    final fragment = fragmentMask(config, options.fragment);
    final noise = noiseMask(config, options.noise);
    if (options.routing.isActive &&
        !options.sniffingEnabled &&
        (options.routing.geositeEnabled ||
            options.routing.domainEnabled ||
            options.routing.sitesEnabled ||
            options.routing.ruServicesEnabled)) {
      throw FormatException(L10n.current.rustSniffing);
    }
    if (options.routing.adBlockEnabled &&
        options.routing.isActive &&
        options.routing.geositeEnabled &&
        options.routing.geositeCodes.any((c) => largeGeositeCodes.contains(c.trim().toLowerCase()))) {
      throw FormatException(L10n.current.rustAdBlockLimit);
    }

    // Composed from the Go builder's parts by name; its policy, dialer-out, SOCKS UDP rule and catch-all
    // aren't taken. Native TUN traffic never uses SOCKS.
    final routing = options.routing;
    final dns = XrayConfigBuilder.buildDnsBlock(options);
    // Rust 0.6 restores domain identity from FakeDNS before TUN routing.
    // Its TUN TCP sniffer alone does not classify ordinary real-IP targets.
    if (routing.isActive &&
        (routing.geositeEnabled || routing.domainEnabled || routing.sitesEnabled || routing.ruServicesEnabled)) {
      dns['fakeIp'] = {'enabled': true, 'ipv4Pool': '198.18.0.0/15', 'poolSize': 4096, 'ttl': 300};
    }
    _adaptDnsServers(dns);
    final adDomains = routing.adBlockEnabled ? _takeAdBlockDomains(dns) : null;

    final socks = XrayConfigBuilder.socksInbound(options);
    socks['listen'] = '127.0.0.1';
    // `udp` as in Go; xray-rust only parses it, SOCKS UDP with UDP disabled
    // is killed by the rule from _tunUdpRule.
    // xray-rust ≥ 0.9.0: SOCKS inbound password (RFC 1929), Xray format.
    socks['settings'] = options.socksUser.isNotEmpty && options.socksPassword.isNotEmpty
        ? {
            'auth': 'password',
            'accounts': [
              {'user': options.socksUser, 'pass': options.socksPassword},
            ],
            'udp': options.enableUdp,
          }
        : {'auth': 'noauth', 'udp': options.enableUdp};

    final proxy = XrayConfigBuilder.proxyOutbound(config, options);
    final stream = proxy['streamSettings'] as Map<String, dynamic>;
    // Fragmentation and noise move from Go's freedom dialer into FinalMask:
    // xray-rust's freedom accepts only `fragment` (not `domainStrategy` or
    // `noises`) and Hysteria rejects sockopt.
    stream.remove('sockopt');
    // xray-rust moves Host from headers into host with a warning about
    // the deprecated field; an empty Host means serverName/address anyway.
    final ws = stream['wsSettings'] as Map?;
    if (ws != null) {
      final host = (ws.remove('headers') as Map?)?['Host'] as String? ?? '';
      if (host.isNotEmpty) ws['host'] = host;
    }
    if (config.transport == VpnTransport.xhttp || config.transport == VpnTransport.splithttp) {
      stream['network'] = 'xhttp';
      stream.remove('splithttpSettings');
      stream['xhttpSettings'] = {
        'host': config.wsHost ?? '',
        'path': config.wsPath ?? '/',
        'mode': config.xhttpMode ?? 'auto',
        if (config.xhttpExtra != null) 'extra': config.xhttpExtra,
      };
    }
    // pinnedPeerCertSha256 and allowInsecure: false with a pin were already set by
    // XrayConfigBuilder — both cores read the same key.
    final tls = stream['tlsSettings'] as Map<String, dynamic>?;
    if (hysteria2 && tls != null) {
      // QUIC TLS isn't disguised as a browser, the Hysteria2 ALPN is only h3,
      // and the core fills it in itself.
      tls.remove('fingerprint');
      tls.remove('alpn');
    }
    if (config.protocol == VpnProtocol.vmess) {
      final user = proxy['settings']['vnext'][0]['users'][0] as Map;
      user['security'] = _vmessCipher(VlessParser.vmessJson(config));
    }
    _legacyUdpHop(stream);
    if (fragment != null || noise != null) {
      // Go already wrote Salamander and udpHop; noise goes after Salamander, i.e.
      // raw, like freedom packets under obfuscation in Go.
      final mask = <String, dynamic>{
        ...?(stream['finalmask'] as Map<String, dynamic>?),
        if (fragment != null) 'tcp': [fragment],
      };
      if (noise != null) {
        mask['udp'] = <dynamic>[...?mask['udp'] as List?, noise];
      }
      stream['finalmask'] = mask;
    }

    final tunUdpRule = _tunUdpRule(options);
    // No catch-all rule: it would match before IPIfNonMatch can resolve a restored
    // domain. Unmatched traffic goes to the core's default (first) outbound instead,
    // leaving the second routing pass available for GeoIP when GeoSite did not match.
    final onlySelected = routing.direction == RoutingDirection.onlySelected;
    return {
      'log': XrayConfigBuilder.logBlock(options),
      'dns': dns,
      'inbounds': [
        {'tag': 'tun-in', 'protocol': 'tun', 'sniffing': Map<String, dynamic>.from(socks['sniffing'] as Map)},
        // Loopback SOCKS is retained for the app's IP check and heartbeat only.
        socks,
      ],
      'outbounds': [
        if (onlySelected) XrayConfigBuilder.directOutbound,
        proxy,
        if (!onlySelected) XrayConfigBuilder.directOutbound,
        {
          ...XrayConfigBuilder.dnsOutbound,
          if (adDomains != null)
            'settings': {
              'rules': [
                {'action': 'return', 'rCode': 0, 'domain': adDomains},
              ],
            },
        },
        if (tunUdpRule != null) XrayConfigBuilder.blockOutbound,
      ],
      'routing': {
        // Resolve for IP rules only. Domain-only routing can pass the name to
        // the server (every supported protocol carries domain destinations)
        // without an extra client-side DNS round trip for every new host.
        'domainStrategy': routing.isActive && (routing.geoEnabled || routing.bypassLocal) ? 'IPIfNonMatch' : 'AsIs',
        'rules': [
          ...XrayConfigBuilder.dnsRules(options, inbounds: ['tun-in', XrayConfigBuilder.socksInTag]),
          ?tunUdpRule,
          ...XrayConfigBuilder.geoRules(routing),
          ...XrayConfigBuilder.diagnosticRules(options),
        ],
      },
    };
  }

  /// Go drops UDP/443 in tun2socks before xray, and disabled UDP — with a
  /// socks-in → blackhole rule (except port 53). Here a TUN → blackhole rule right after
  /// the DNS rules does the same: port 53 has already gone to dns-out, and the core's DNS module (`dns-module`)
  /// and the transport to the server itself (QUIC Hysteria2, UDP Shadowsocks) aren't touched.
  /// Blackhole `none` silently kills the UDP flow (without the ICMP "port unreachable"
  /// Go answers with) until 60 s of silence. xray-rust 0.8.1 parses `udp`
  /// for SOCKS but accepts UDP ASSOCIATE anyway, so disabled UDP
  /// also closes SOCKS with a rule; QUIC, as in Go, is blocked only in TUN.
  /// null — nothing to block.
  static Map<String, dynamic>? _tunUdpRule(VpnEngineOptions options) {
    if (options.enableUdp && !options.blockQuic) return null;
    return {
      'type': 'field',
      'inboundTag': options.enableUdp ? ['tun-in'] : ['tun-in', XrayConfigBuilder.socksInTag],
      'network': 'udp',
      if (options.enableUdp) 'port': '443',
      'outboundTag': 'block',
    };
  }

  static bool _isXhttpH3(VpnConfig config) =>
      (config.transport == VpnTransport.xhttp || config.transport == VpnTransport.splithttp) &&
      config.security == VpnSecurity.tls &&
      (config.alpn ?? '').split(',').map((s) => s.trim()).join(',') == 'h3';

  static (int, int) _range(String value) {
    final parts = value.trim().split('-').map((p) => int.parse(p.trim()));
    return (parts.first, parts.last);
  }

  /// xray-rust 0.9.0 knows port hopping only as `quicParams.udpHop`
  /// (Xray-core v26.7.28), while the Go builder writes the `udphop` UDP mask (v26.9.9+).
  static void _legacyUdpHop(Map<String, dynamic> stream) {
    final mask = stream['finalmask'] as Map?;
    final udp = [...?mask?['udp'] as List?];
    final hop = udp.where((dynamic m) => m['type'] == 'udphop').firstOrNull;
    if (hop == null) return;
    udp.remove(hop);
    stream['finalmask'] = <String, dynamic>{
      if (udp.isNotEmpty) 'udp': udp,
      'quicParams': {
        'udpHop': {'ports': hop['settings']['remotePorts']},
      },
    };
  }

  /// FinalMask `tcp` fragment for the app's fragmentation, or null where Go's
  /// freedom fragment does not act either: Hysteria2 and xHTTP h3 are QUIC,
  /// and `tlshello` leaves a first write that is not a TLS handshake record
  /// (Shadowsocks, VMess without TLS) untouched. Invalid settings are not
  /// applied in either build; the settings screen says so.
  static Map<String, dynamic>? fragmentMask(VpnConfig config, FragmentSettings f) {
    if (!f.enabled || !f.isValid) return null;
    if (config.protocol == VpnProtocol.hysteria2 || _isXhttpH3(config)) {
      return null;
    }
    if (f.packets.trim() != 'tlshello') {
      throw FormatException(L10n.current.rustFragmentPackets);
    }
    if (config.security == VpnSecurity.none) return null;
    final length = _range(f.length);
    final delay = _range(f.interval);
    if (length.$2 > 16384) {
      throw FormatException(L10n.current.rustFragmentLength);
    }
    if (delay.$2 > 1000) {
      throw FormatException(L10n.current.rustFragmentDelay);
    }
    if (config.xhttpExtra?['downloadSettings'] != null) {
      throw FormatException(L10n.current.rustFragmentXhttp);
    }
    final settings = <String, dynamic>{'packets': 'tlshello', 'length': f.length.trim(), 'delay': f.interval.trim()};
    // xray-rust drops the connection if the split plan exceeds 4096 chunks or
    // 10 s of pauses; Go has no such limits. maxSplit caps the number of chunks
    // so that even a 16 KiB ClientHello of minimum-length chunks fits,
    // and the last chunk takes the remainder. A normal ClientHello (~2 KiB) with
    // reasonable settings never reaches the limit and is split as in Go.
    final worst = (16384 + length.$1 - 1) ~/ length.$1;
    final cap = delay.$2 == 0 ? 4096 : min(4096, 10000 ~/ delay.$2);
    if (worst > cap) settings['maxSplit'] = cap;
    return {'type': 'fragment', 'settings': settings};
  }

  /// FinalMask UDP noise for the app's noise settings, or null where Go's
  /// freedom noise touches no UDP socket either: VLESS, Trojan and VMess carry
  /// UDP inside their TCP transport. xray-rust sends noise only before
  /// Hysteria2 and xHTTP h3 QUIC; Shadowsocks UDP goes to the server as plain
  /// datagrams that Go would prefix with noise, so it is refused.
  static Map<String, dynamic>? noiseMask(VpnConfig config, NoiseSettings n) {
    if (!n.enabled || !n.isValid) return null;
    if (config.protocol != VpnProtocol.hysteria2 && !_isXhttpH3(config)) {
      if (config.protocol == VpnProtocol.shadowsocks) {
        throw FormatException(L10n.current.rustNoiseSs);
      }
      return null;
    }
    final delay = n.delay.trim();
    if (_range(delay).$2 > 1000) {
      throw FormatException(L10n.current.rustNoiseDelay);
    }
    final packet = n.packet.trim();
    final int bytes;
    switch (n.type) {
      case NoiseType.rand:
        bytes = _range(packet).$2;
      case NoiseType.str:
        bytes = utf8.encode(packet).length;
      case NoiseType.hex:
        if (packet.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(packet)) {
          throw FormatException(L10n.current.rustNoiseHex);
        }
        bytes = packet.length ~/ 2;
      case NoiseType.base64:
        final decoded = _strictBase64(packet);
        if (decoded == null) {
          throw FormatException(L10n.current.rustNoiseBase64);
        }
        bytes = decoded.length;
    }
    if (bytes > 4096) {
      throw FormatException(L10n.current.rustNoisePacket);
    }
    return {
      'type': 'noise',
      'settings': {
        'reset': 0,
        'noise': [
          n.type == NoiseType.rand
              ? {'rand': packet, 'delay': delay}
              : {'type': n.type.name, 'packet': packet, 'delay': delay},
        ],
      },
    };
  }

  /// Go answers ad domains with an empty NOERROR: a DNS server
  /// `rcode://success` with a domains list. xray-rust doesn't accept such a server,
  /// so it is taken out of [dns] and its domains go to a Return rule on the DNS outbound
  /// that carries app DNS queries (both with FakeDNS and in "direct" mode).
  static Object? _takeAdBlockDomains(Map<String, dynamic> dns) {
    final servers = dns['servers'] as List<dynamic>;
    final adServer = servers.singleWhere((dynamic s) => s is Map && s['address'] == 'rcode://success') as Map;
    servers.remove(adServer);
    return adServer['domains'];
  }

  /// xray-rust reads a DoT server's port only from its `tls://` URL and ignores
  /// the object's `port`, so a custom DoT port would silently become 853.
  /// A plain server keeps `port`, but its IPv6 literal must be unbracketed.
  static final _dotAuthorityWithPort = RegExp(r'^tls://(\[[^\]]*\]|[^:\[\]]+):\d+$');

  static void _adaptDnsServers(Map<String, dynamic> dns) {
    for (final dynamic server in dns['servers'] as List<dynamic>) {
      if (server is! Map) continue;
      final address = server['address'] as String;
      if (address.startsWith('tls://') && server['port'] is int) {
        final port = server.remove('port');
        // DnsServerConfig keeps `]:port` for bracketed IPv6; xray-rust rejects
        // a second port, so the port from the URL is kept as is.
        if (!_dotAuthorityWithPort.hasMatch(address)) {
          server['address'] = '$address:$port';
        }
      } else if (address.startsWith('[') && address.endsWith(']')) {
        server['address'] = address.substring(1, address.length - 1);
      }
    }
  }

  static String buildJson(VpnConfig config, VpnEngineOptions options) => jsonEncode(build(config, options));

  /// Candidate check for switchConfig (`XrayEngine.measureOutbound`): the
  /// profile's proxy outbound, exactly as [build] writes it for the VPN, in a
  /// config Android starts as a temporary core beside the running one. It has
  /// no TUN, routing, FakeDNS or DNS module: `probeOutboundUrl` dials the proxy
  /// leaf directly and passes the target name to the server. xray-rust starts
  /// only with an inbound, so a loopback SOCKS with a one-time password listens on
  /// an ephemeral port and never collides with the VPN's SOCKS port. Android pins the server name
  /// into `dns.hosts` before the start, as for the VPN. Throws
  /// [FormatException] where [build] does.
  static Map<String, dynamic> buildProbe(VpnConfig config, VpnEngineOptions options) {
    final outbounds = build(config, options)['outbounds'] as List<dynamic>;
    final proxy = outbounds.singleWhere((dynamic o) => o['tag'] == 'proxy');
    // A one-time password: probeOutboundUrl bypasses the inbound, and without it any
    // app that found the port could exit through the candidate and learn its IP.
    final rnd = Random.secure();
    String token() => [for (var i = 0; i < 16; i++) rnd.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
    return {
      'inbounds': [
        {
          'tag': 'probe-in',
          'protocol': 'socks',
          'listen': '127.0.0.1',
          'port': 0,
          'settings': {
            'auth': 'password',
            'accounts': [
              {'user': token(), 'pass': token()},
            ],
            'udp': false,
          },
        },
      ],
      'outbounds': [proxy],
      'dns': {'hosts': <String, dynamic>{}},
    };
  }

  static String buildProbeJson(VpnConfig config, VpnEngineOptions options) => jsonEncode(buildProbe(config, options));
}
