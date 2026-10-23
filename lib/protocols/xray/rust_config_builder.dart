import '../../core/constants/core_features.dart';
import 'dart:convert';
import 'dart:math';

import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/dns_config.dart';
import '../../core/models/routing_settings.dart';
import '../../core/models/vpn_config.dart';
import '../../core/models/xray_tuning.dart';
import 'xray_config_builder.dart';

/// Profiles xray-rust 0.8.1 runs through Android TUN: VLESS, Trojan, VMess
/// AEAD, Shadowsocks 2022 and Hysteria2, translated from the Go builder's
/// output into the subset `docs/config-compatibility.md` accepts.
///
/// TLS certificate pins win over `allowInsecure`: a profile with both is built
/// with `allowInsecure: false` and `pinnedPeerCertSha256`, so the server must
/// present exactly the pinned certificate — stricter than the request, and the
/// usual intent of such links (a self-signed server identified by its pin).
/// xray-rust, like current Xray-core, has no unverified mode, so
/// `allowInsecure` without a pin is rejected.
class RustConfigBuilder {
  static const visionFlows = {'xtls-rprx-vision', 'xtls-rprx-vision-udp443'};

  /// xray-rust 0.8.1 (`shadowsocks2022::Cipher`): SS2022 only, no AEAD-2017.
  static const ss2022Methods = {
    '2022-blake3-aes-128-gcm',
    '2022-blake3-aes-256-gcm',
    '2022-blake3-chacha20-poly1305',
  };

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
  static const _urlTransports = {
    'tcp',
    'raw',
    'ws',
    'websocket',
    'httpupgrade',
    'grpc',
    'xhttp',
    'splithttp',
  };

  static bool supports(VpnConfig config) => unsupportedReason(config) == null;

  static String? unsupportedReason(VpnConfig config) {
    if (config.rawXrayConfig != null) {
      return 'Импорт полного JSON в Rust-сборке пока недоступен.';
    }
    // Go вставляет fm из ссылки в streamSettings как есть; xray-rust принимает
    // лишь узкое подмножество FinalMask, которое собирает сам этот билдер.
    if (config.finalmask?.isNotEmpty ?? false) {
      return 'Параметр fm (finalmask) из ссылки Rust-сборка не применяет. Фрагментацию и шумы задай в настройках сети.';
    }
    return switch (config.protocol) {
      VpnProtocol.hysteria2 => _hysteria2UnsupportedReason(config),
      VpnProtocol.vless => _vlessUnsupportedReason(config),
      VpnProtocol.trojan => _trojanUnsupportedReason(config),
      VpnProtocol.vmess => _vmessUnsupportedReason(config),
      VpnProtocol.shadowsocks => _shadowsocksUnsupportedReason(config),
    };
  }

  static String? _vlessUnsupportedReason(VpnConfig config) {
    if (config.encryption != null && config.encryption != 'none') {
      return 'Rust-сборка пока принимает VLESS с encryption=none.';
    }
    if (!_isUuid(config.uuid)) {
      return 'UUID VLESS должен быть настоящим UUID: Rust-ядро не принимает произвольные строки.';
    }
    final params = _linkParams(config);
    final carrier = _carrierReason(
      config,
      declaredTransport: params['type'],
      headerType: params['headerType'],
    );
    if (carrier != null) return carrier;
    if (config.security != VpnSecurity.tls &&
        config.security != VpnSecurity.reality) {
      return 'Для VLESS в Rust-сборке выбери TLS или Reality.';
    }
    final flow = config.flow ?? '';
    if (flow.isNotEmpty && !visionFlows.contains(flow)) {
      return 'Неизвестный VLESS flow.';
    }
    // xray-rust 0.8.0 исправил Vision поверх обычного TLS на RAW; на WS,
    // HTTPUpgrade, gRPC и xHTTP Vision без VLESS-шифрования ядро по-прежнему
    // отвергает перед подключением, как и Xray-core.
    if (flow.isNotEmpty && config.transport != VpnTransport.tcp) {
      return 'Vision с encryption=none поддерживается только поверх TCP/RAW с TLS или Reality.';
    }
    return null;
  }

  static String? _trojanUnsupportedReason(VpnConfig config) {
    final password = config.password ?? '';
    if (password.isEmpty || utf8.encode(password).length > 4096) {
      return 'Пароль Trojan должен быть непустым и не длиннее 4096 байт.';
    }
    final params = _linkParams(config);
    final carrier = _carrierReason(
      config,
      declaredTransport: params['type'],
      headerType: params['headerType'],
    );
    if (carrier != null) return carrier;
    // xray-rust отвергает Trojan без TLS/Reality для публичного сервера.
    if (config.security != VpnSecurity.tls &&
        config.security != VpnSecurity.reality) {
      return 'Trojan в Rust-сборке работает только с TLS или Reality.';
    }
    return null;
  }

  static String? _vmessUnsupportedReason(VpnConfig config) {
    if (!_isUuid(config.uuid)) {
      return 'id VMess должен быть настоящим UUID: Rust-ядро не принимает произвольные строки.';
    }
    // aid из ссылки не применяется, как и в Go: alterId в конфиг не пишется,
    // клиент всегда говорит VMess AEAD, а сервер Xray/v2fly 4.28+ принимает
    // AEAD при любом своём alterId.
    final json = _vmessJson(config);
    // Парсер считает всё, кроме точного tls, отсутствием защиты: reality из
    // ссылки молча превратился бы в VMess без TLS.
    final rawTls = json['tls']?.toString() ?? '';
    final tls = rawTls.trim().toLowerCase();
    if (tls.isNotEmpty && tls != 'tls' && tls != 'none') {
      return 'VMess с security=$tls из ссылки Rust-сборка не поддерживает: доступны TLS и транспорт без шифрования.';
    }
    // «TLS» или « tls» парсер тоже не узнаёт: профиль ушёл бы на TLS-порт
    // голым VMess.
    if (tls == 'tls' && config.security != VpnSecurity.tls) {
      return 'VMess-ссылка задаёт tls=«$rawTls»: парсер понимает только точное «tls», и профиль ушёл бы без TLS. Исправь значение в ссылке.';
    }
    return _carrierReason(
      config,
      declaredTransport: json['net']?.toString(),
      headerType: json['type']?.toString(),
    );
  }

  static String? _shadowsocksUnsupportedReason(VpnConfig config) {
    final method = config.method ?? '';
    if (!ss2022Methods.contains(method)) {
      return 'Rust-ядро поддерживает только Shadowsocks 2022 (2022-blake3-aes-128-gcm, '
          '2022-blake3-aes-256-gcm, 2022-blake3-chacha20-poly1305). '
          'Метод «$method» не поддерживается.';
    }
    final keys = _ss2022KeyReason(method, config.password ?? '');
    if (keys != null) return keys;
    if (_linkParams(config)['plugin']?.trim().isNotEmpty ?? false) {
      return 'Плагины Shadowsocks (SIP003, plugin=…) Rust-сборка не поддерживает.';
    }
    if (config.ssPrefix?.isNotEmpty ?? false) {
      return 'Префикс Outline (prefix=…) для Shadowsocks Rust-сборка не поддерживает.';
    }
    return null;
  }

  /// Transport, TCP header and outer TLS/REALITY rules shared by the protocols
  /// on xray-rust's stream carriers (VLESS, Trojan, VMess).
  static String? _carrierReason(
    VpnConfig config, {
    String? declaredTransport,
    String? headerType,
  }) {
    final declared = declaredTransport?.trim().toLowerCase() ?? '';
    if (!_transports.contains(config.transport) ||
        (declared.isNotEmpty && !_urlTransports.contains(declared))) {
      return 'Транспорт не поддерживается. Доступны TCP/RAW, WebSocket, HTTPUpgrade, gRPC и xHTTP.';
    }
    // Парсер не читает headerType: без проверки TCP с HTTP-маскировкой молча
    // ушёл бы голым TCP. xray-rust принимает только header.type none.
    final header = headerType?.trim().toLowerCase() ?? '';
    if (config.transport == VpnTransport.tcp &&
        header.isNotEmpty &&
        header != 'none') {
      return 'TCP с HTTP-маскировкой (headerType=$header) Rust-ядро не поддерживает.';
    }
    if (config.security == VpnSecurity.reality &&
        (config.transport == VpnTransport.ws ||
            config.transport == VpnTransport.httpupgrade)) {
      return 'Reality поддерживается с TCP/RAW, gRPC и xHTTP. Для WebSocket/HTTPUpgrade нужен TLS.';
    }
    if (config.security == VpnSecurity.tls && _insecureWithoutPin(config)) {
      return _insecureReason;
    }
    if (config.ech?.isNotEmpty ?? false) {
      return 'ECH пока недоступен в Rust-сборке.';
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
    if (password.isEmpty ||
        utf8.encode(password).length > 8192 ||
        keys.length > 8 ||
        (chacha && keys.length != 1)) {
      return chacha
          ? 'Для $method нужен один ключ (без identity-ключей через двоеточие).'
          : 'Для $method допускается до 8 ключей через двоеточие.';
    }
    for (final key in keys) {
      final decoded = _strictBase64(key);
      if (decoded == null || decoded.length < keyLength) {
        return 'Ключ Shadowsocks 2022 ($method) должен быть base64 с паддингом не короче $keyLength байт.';
      }
    }
    return null;
  }

  /// Standard padded base64, as the `base64` crate's STANDARD engine decodes.
  static List<int>? _strictBase64(String value) {
    if (value.isEmpty ||
        value.length % 4 != 0 ||
        !RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(value)) {
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

  /// Query parameters of the profile's share link, including the base64 body
  /// of a SIP002 `ss://BASE64#name` link. Empty when the link is unreadable.
  static Map<String, String> _linkParams(VpnConfig config) {
    final raw = config.rawUri;
    if (raw == null) return const {};
    final hash = raw.indexOf('#');
    var main = hash >= 0 ? raw.substring(0, hash) : raw;
    if (config.protocol == VpnProtocol.shadowsocks && !main.contains('@')) {
      try {
        main = utf8.decode(base64Decode(_padBase64(main.substring(5))));
      } catch (_) {
        return const {};
      }
    }
    final query = main.indexOf('?');
    if (query < 0) return const {};
    try {
      return Uri.splitQueryString(main.substring(query + 1));
    } catch (_) {
      return const {};
    }
  }

  /// The v2 `vmess://BASE64(JSON)` body the parser read the profile from.
  static Map<String, dynamic> _vmessJson(VpnConfig config) {
    final raw = config.rawUri;
    if (raw == null || !raw.startsWith('vmess://')) return const {};
    try {
      final json = jsonDecode(
        utf8.decode(base64Decode(_padBase64(raw.substring('vmess://'.length)))),
      );
      return json is Map<String, dynamic> ? json : const {};
    } catch (_) {
      return const {};
    }
  }

  static String _padBase64(String s) =>
      s.length % 4 == 0 ? s : s + '=' * (4 - s.length % 4);

  /// xray-rust 0.7.0 caps a config at 250,000 domain matchers
  /// (MAX_CONFIG_DOMAIN_MATCHERS), shared by routing and DNS-outbound rules, and
  /// expands each geosite entry into one matcher. Ad blocking alone takes about
  /// 187k (category-ads-all 186,402 + win-spy 327 in the bundled Loyalsoldier
  /// 202609082347), so a GeoSite rule with one of these (cn 111,168,
  /// china-list 110,433) cannot be parsed and the VPN would not start.
  static const _largeGeositeCodes = {'cn', 'china-list', 'category-ads-all'};

  static const _insecureReason =
      'Rust не поддерживает allowInsecure без pinSHA256. Используй действительный TLS-сертификат или укажи pinSHA256 сертификата сервера.';

  static bool _hasPin(VpnConfig config) =>
      config.pinSHA256?.trim().isNotEmpty ?? false;

  static bool _insecureWithoutPin(VpnConfig config) =>
      config.allowInsecure && !_hasPin(config);

  /// xray-rust 0.8.1: Hysteria2 over stock QUIC TLS (h3), default BBR, with
  /// optional FinalMask Salamander and `quicParams.udpHop` in Xray-core
  /// v26.7.28's spelling — exactly what the Go builder writes. Brutal,
  /// bandwidth and other QUIC overrides and sockopt stay rejected by the core.
  static String? _hysteria2UnsupportedReason(VpnConfig config) {
    // Парсер берёт пароль только у obfs=salamander: другой тип или пустой
    // пароль Go молча отбрасывает и подключается без обфускации.
    final obfs = _linkParams(config)['obfs']?.trim() ?? '';
    if (obfs.isNotEmpty && obfs != 'none' && obfs != 'salamander') {
      return 'Обфускация Hysteria2 «$obfs» не поддерживается: Rust-ядро знает только Salamander.';
    }
    final salamander = config.obfsPassword ?? '';
    if (obfs == 'salamander' && salamander.isEmpty) {
      return 'Для Salamander (obfs=salamander) нужен obfs-password.';
    }
    if (salamander.isNotEmpty &&
        (utf8.encode(salamander).length < 4 ||
            utf8.encode(salamander).length > 4096)) {
      return 'Пароль Salamander (obfs-password) должен содержать от 4 до 4096 байт.';
    }
    final hop = config.hopPorts ?? '';
    if (hop.isNotEmpty && _expandedPortCount(hop) > 65535) {
      return 'Список портов для port hopping слишком длинный: Rust-ядро принимает до 65535 портов.';
    }
    final auth = config.password ?? '';
    if (auth.isEmpty ||
        utf8.encode(auth).length > 4096 ||
        auth.codeUnits.any((c) => c < 0x20 || c == 0x7f)) {
      return 'Пароль Hysteria2 должен быть непустым, не длиннее 4096 байт и без управляющих символов.';
    }
    if (_insecureWithoutPin(config)) return _insecureReason;
    if (config.ech?.isNotEmpty ?? false) {
      return 'ECH пока недоступен в Rust-сборке.';
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

  static Map<String, dynamic> build(
    VpnConfig config,
    VpnEngineOptions options,
  ) {
    final reason = unsupportedReason(config);
    if (reason != null) throw FormatException(reason);
    if ((!CoreFeatures.rust.supports(CoreFeature.proxyOnly) &&
            options.proxyOnly) ||
        options.httpPort != 0) {
      throw const FormatException(
        'В Rust-пробнике доступен только режим VPN (TUN).',
      );
    }
    // Go не применяет Mux к Hysteria2 (QUIC сам мультиплексирует потоки),
    // значит и здесь он не мешает.
    final hysteria2 = config.protocol == VpnProtocol.hysteria2;
    if (!CoreFeatures.rust.supports(CoreFeature.mux) &&
        options.mux.enabled &&
        !hysteria2) {
      throw const FormatException(
        'Mux недоступен в Rust-сборке: выключи его в настройках сети.',
      );
    }
    if (!CoreFeatures.rust.supports(CoreFeature.customMtu) &&
        options.mtu != 1500) {
      throw const FormatException(
        'Rust-сборка работает с MTU 1500: верни это значение в настройках сети.',
      );
    }
    final fragment = _fragmentMask(config, options.fragment);
    final noise = _noiseMask(config, options.noise);
    if (options.routing.isActive &&
        !options.sniffingEnabled &&
        (options.routing.geositeEnabled ||
            options.routing.domainEnabled ||
            options.routing.sitesEnabled ||
            options.routing.ruServicesEnabled)) {
      throw const FormatException(
        'Включи определение доменов для GeoSite и доменных правил.',
      );
    }
    if (options.routing.adBlockEnabled &&
        options.routing.isActive &&
        options.routing.geositeEnabled &&
        options.routing.geositeCodes.any(
          (c) => _largeGeositeCodes.contains(c.trim().toLowerCase()),
        )) {
      throw const FormatException(
        'Блокировка рекламы (~187 тыс. доменов) вместе с большой категорией GeoSite '
        '(cn, china-list, category-ads-all) превышает лимит Rust-ядра в 250 тыс. '
        'доменных правил. Отключи одно из двух.',
      );
    }

    // Reuse the existing profile and domain-routing translation, then replace
    // the Go-specific inbound and policy. Native TUN traffic never uses SOCKS.
    final result = XrayConfigBuilder.build(config, options);
    result.remove('policy');
    if (options.dnsMode == DnsMode.direct) _routeDnsDirect(result, options);
    // Resolve for IP rules only. Domain-only routing can pass the name to
    // the server (every supported protocol carries domain destinations)
    // without an extra client-side DNS round trip for every new host.
    result['routing']['domainStrategy'] =
        options.routing.isActive &&
            (options.routing.geoEnabled || options.routing.bypassLocal)
        ? 'IPIfNonMatch'
        : 'AsIs';
    // Rust 0.6 restores domain identity from FakeDNS before TUN routing.
    // Its TUN TCP sniffer alone does not classify ordinary real-IP targets.
    if (options.routing.isActive &&
        (options.routing.geositeEnabled ||
            options.routing.domainEnabled ||
            options.routing.sitesEnabled ||
            options.routing.ruServicesEnabled)) {
      (result['dns'] as Map<String, dynamic>)['fakeIp'] = {
        'enabled': true,
        'ipv4Pool': '198.18.0.0/15',
        'poolSize': 4096,
        'ttl': 300,
      };
    }
    _adaptDnsServers(result['dns'] as Map<String, dynamic>);

    final inbounds = result['inbounds'] as List<dynamic>;
    final socks = inbounds.single as Map<String, dynamic>;
    socks['listen'] = '127.0.0.1';
    // `udp` как в Go; xray-rust его лишь разбирает, UDP SOCKS при выключенном
    // UDP гасит правило из _blockTunUdp.
    socks['settings'] = {'auth': 'noauth', 'udp': options.enableUdp};
    inbounds.insert(0, {
      'tag': 'tun-in',
      'protocol': 'tun',
      'sniffing': Map<String, dynamic>.from(socks['sniffing'] as Map),
    });
    // Loopback SOCKS is retained for the app's IP check and heartbeat only.
    final outbounds = result['outbounds'] as List<dynamic>;
    // Fragmentation and noise move from Go's freedom dialer into FinalMask:
    // xray-rust's freedom accepts only `fragment` (not `domainStrategy` or
    // `noises`) and Hysteria rejects sockopt.
    outbounds.removeWhere((dynamic out) => out['tag'] == 'dialer-out');
    if (options.routing.adBlockEnabled) _blockAdsInDnsOutbound(result);
    final rules = (result['routing'] as Map)['rules'] as List<dynamic>;
    for (final dynamic rule in rules) {
      final tags = rule['inboundTag'];
      if (tags is List && tags.contains('socks-in')) {
        rule['inboundTag'] = ['tun-in', 'socks-in'];
      }
    }
    // A catch-all rule matches before IPIfNonMatch can resolve a restored
    // domain. Use the core's default outbound instead, leaving the second
    // routing pass available for GeoIP when GeoSite did not match.
    rules.removeLast();
    if (!_blockTunUdp(rules, options)) {
      outbounds.removeWhere((dynamic out) => out['protocol'] == 'blackhole');
    }
    final proxy = outbounds.first as Map<String, dynamic>;
    final stream = proxy['streamSettings'] as Map<String, dynamic>;
    stream.remove('sockopt');
    // xray-rust складывает Host из headers в host с предупреждением об
    // устаревшем поле; пустой Host и без того означает serverName/адрес.
    final ws = stream['wsSettings'] as Map?;
    if (ws != null) {
      final host = (ws.remove('headers') as Map?)?['Host'] as String? ?? '';
      if (host.isNotEmpty) ws['host'] = host;
    }
    if (config.transport == VpnTransport.xhttp ||
        config.transport == VpnTransport.splithttp) {
      stream['network'] = 'xhttp';
      stream.remove('splithttpSettings');
      stream['xhttpSettings'] = {
        'host': config.wsHost ?? '',
        'path': config.wsPath ?? '/',
        'mode': config.xhttpMode ?? 'auto',
        if (config.xhttpExtra != null) 'extra': config.xhttpExtra,
      };
    }
    // pinnedPeerCertSha256 и allowInsecure: false при пине уже выставил
    // XrayConfigBuilder — тот же ключ читают оба ядра.
    final tls = stream['tlsSettings'] as Map<String, dynamic>?;
    if (hysteria2 && tls != null) {
      // QUIC TLS не маскируется под браузер, ALPN Hysteria2 — только h3,
      // и ядро подставляет его само.
      tls.remove('fingerprint');
      tls.remove('alpn');
    }
    if (config.protocol == VpnProtocol.vmess) {
      final user = proxy['settings']['vnext'][0]['users'][0] as Map;
      user['security'] = _vmessCipher(_vmessJson(config));
    }
    if (fragment != null || noise != null) {
      // Salamander и udpHop Go уже записал; шум идёт после Salamander, то есть
      // сырым, как пакеты freedom под обфускацией в Go.
      final mask = <String, dynamic>{
        ...?stream['finalmask'] as Map?,
        if (fragment != null) 'tcp': [fragment],
      };
      if (noise != null) {
        mask['udp'] = <dynamic>[...?mask['udp'] as List?, noise];
      }
      stream['finalmask'] = mask;
    }
    if (options.routing.direction == RoutingDirection.onlySelected) {
      final direct = outbounds.singleWhere(
        (dynamic out) => out['tag'] == 'direct',
      );
      outbounds.remove(direct);
      outbounds.insert(0, direct);
    }
    return result;
  }

  /// Go отбрасывает UDP/443 (и весь UDP при выключенном переключателе) в
  /// tun2socks до xray. Здесь то же делает правило TUN → blackhole сразу после
  /// DNS-правил: порт 53 уже ушёл в dns-out, а DNS-модуль ядра (`dns-module`)
  /// и сам транспорт к серверу (QUIC Hysteria2, UDP Shadowsocks) не трогаются.
  /// Blackhole `none` молча гасит UDP-поток (без ICMP «порт недоступен»,
  /// которым отвечает Go) до 60 с тишины. xray-rust 0.8.1 разбирает `udp`
  /// у SOCKS, но UDP ASSOCIATE принимает всё равно, поэтому выключенный UDP
  /// закрывает правилом и SOCKS; QUIC, как и в Go, блокируется только в TUN.
  /// Returns whether a rule was added.
  static bool _blockTunUdp(List<dynamic> rules, VpnEngineOptions options) {
    if (options.enableUdp && !options.blockQuic) return false;
    final at =
        rules.lastIndexWhere((dynamic r) => r['outboundTag'] == 'dns-out') + 1;
    if (at == 0) throw StateError('DNS rule not found');
    rules.insert(at, <String, dynamic>{
      'type': 'field',
      'inboundTag': options.enableUdp ? ['tun-in'] : ['tun-in', 'socks-in'],
      'network': 'udp',
      if (options.enableUdp) 'port': '443',
      'outboundTag': 'block',
    });
    return true;
  }

  static bool _isXhttpH3(VpnConfig config) =>
      (config.transport == VpnTransport.xhttp ||
          config.transport == VpnTransport.splithttp) &&
      config.security == VpnSecurity.tls &&
      (config.alpn ?? '').split(',').map((s) => s.trim()).join(',') == 'h3';

  static (int, int) _range(String value) {
    final parts = value.trim().split('-').map((p) => int.parse(p.trim()));
    return (parts.first, parts.last);
  }

  /// FinalMask `tcp` fragment for the app's fragmentation, or null where Go's
  /// freedom fragment does not act either: Hysteria2 and xHTTP h3 are QUIC,
  /// and `tlshello` leaves a first write that is not a TLS handshake record
  /// (Shadowsocks, VMess without TLS) untouched. Invalid settings are not
  /// applied in either build; the settings screen says so.
  static Map<String, dynamic>? _fragmentMask(
    VpnConfig config,
    FragmentSettings f,
  ) {
    if (!f.enabled || !f.isValid) return null;
    if (config.protocol == VpnProtocol.hysteria2 || _isXhttpH3(config)) {
      return null;
    }
    if (f.packets.trim() != 'tlshello') {
      throw const FormatException(
        'Rust-ядро режет только TLS ClientHello: в поле «Пакеты» фрагментации укажи tlshello.',
      );
    }
    if (config.security == VpnSecurity.none) return null;
    final length = _range(f.length);
    final delay = _range(f.interval);
    if (length.$2 > 16384) {
      throw const FormatException(
        'Длина куска фрагментации в Rust-ядре — от 1 до 16384 байт.',
      );
    }
    if (delay.$2 > 1000) {
      throw const FormatException(
        'Пауза фрагментации в Rust-ядре — не больше 1000 мс.',
      );
    }
    if (config.xhttpExtra?['downloadSettings'] != null) {
      throw const FormatException(
        'Фрагментацию ClientHello Rust-ядро не применяет к xHTTP с отдельным downloadSettings. Фрагментация — общая настройка: выключи её в настройках сети, чтобы подключиться к этому профилю.',
      );
    }
    final settings = <String, dynamic>{
      'packets': 'tlshello',
      'length': f.length.trim(),
      'delay': f.interval.trim(),
    };
    // xray-rust рвёт соединение, если план нарезки превышает 4096 кусков или
    // 10 с пауз; у Go таких пределов нет. maxSplit ограничивает число кусков
    // так, чтобы даже 16-КиБ ClientHello из кусков минимальной длины уложился,
    // а последний кусок забрал остаток. Обычный ClientHello (~2 КиБ) при
    // разумных настройках до предела не доходит и режется как в Go.
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
  static Map<String, dynamic>? _noiseMask(VpnConfig config, NoiseSettings n) {
    if (!n.enabled || !n.isValid) return null;
    if (config.protocol != VpnProtocol.hysteria2 && !_isXhttpH3(config)) {
      if (config.protocol == VpnProtocol.shadowsocks) {
        throw const FormatException(
          'Шумы перед UDP Shadowsocks Rust-ядро не отправляет (только для Hysteria2 и xHTTP поверх HTTP/3). Шумы — общая настройка: выключи их в настройках сети, чтобы подключиться к этому профилю.',
        );
      }
      return null;
    }
    final delay = n.delay.trim();
    if (_range(delay).$2 > 1000) {
      throw const FormatException(
        'Пауза шума в Rust-ядре — не больше 1000 мс.',
      );
    }
    final packet = n.packet.trim();
    final int bytes;
    switch (n.type) {
      case NoiseType.rand:
        bytes = _range(packet).$2;
      case NoiseType.str:
        bytes = utf8.encode(packet).length;
      case NoiseType.hex:
        if (packet.length.isOdd ||
            !RegExp(r'^[0-9a-fA-F]+$').hasMatch(packet)) {
          throw const FormatException(
            'Шум HEX должен состоять из пар шестнадцатеричных цифр.',
          );
        }
        bytes = packet.length ~/ 2;
      case NoiseType.base64:
        final decoded = _strictBase64(packet);
        if (decoded == null) {
          throw const FormatException(
            'Шум BASE64 должен быть стандартным base64 с паддингом.',
          );
        }
        bytes = decoded.length;
    }
    if (bytes > 4096) {
      throw const FormatException(
        'Пакет шума в Rust-ядре — не больше 4096 байт.',
      );
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

  /// Go в режиме «напрямую» отдаёт порт 53 в freedom (до своего TUN-DNS
  /// 1.1.1.1) и резолвит сам через `localhost`. Здесь приложения спрашивают
  /// якорь 198.18.0.1, который freedom не достанет, а `localhost` для xray-rust —
  /// DNS-сервер с именем localhost:53, не системный резолвер (его при StaticOnly
  /// у ядра нет). Поэтому, как и в режиме «через VPN», запросы приложений
  /// принимает DNS-outbound и отвечает через DNS-модуль с выбранным сервером,
  /// но сам модуль (`dns-module`, и для своих поисков ядра) ходит в direct —
  /// мимо туннеля, защищёнными сокетами.
  static void _routeDnsDirect(
    Map<String, dynamic> result,
    VpnEngineOptions options,
  ) {
    result['dns'] = XrayConfigBuilder.buildResolverDnsBlock(options);
    final rules = (result['routing'] as Map)['rules'] as List<dynamic>;
    final goRule = rules.indexWhere(
      (dynamic r) =>
          r['port'] == '53' &&
          r['outboundTag'] == 'direct' &&
          r['inboundTag'] == null,
    );
    if (goRule < 0) throw StateError('Go direct-DNS rule not found');
    rules.replaceRange(goRule, goRule + 1, <Map<String, dynamic>>[
      {
        'type': 'field',
        'inboundTag': ['dns-module'],
        'outboundTag': 'direct',
      },
      {
        'type': 'field',
        'inboundTag': ['socks-in'],
        'port': '53',
        'network': 'udp,tcp',
        'outboundTag': 'dns-out',
      },
    ]);
  }

  /// Go отвечает на рекламные домены пустым NOERROR: DNS-сервер
  /// `rcode://success` со списком domains. xray-rust такой сервер не принимает,
  /// то же делает правило Return у DNS-outbound, через который идут DNS-запросы
  /// приложений (и с FakeDNS, и в режиме «напрямую»). Домены — те же, что у Go.
  static void _blockAdsInDnsOutbound(Map<String, dynamic> result) {
    final servers = (result['dns'] as Map)['servers'] as List<dynamic>;
    final adServer = servers.singleWhere(
      (dynamic s) => s is Map && s['address'] == 'rcode://success',
    );
    servers.remove(adServer);
    final outbounds = result['outbounds'] as List<dynamic>;
    final dnsOut = outbounds.indexWhere(
      (dynamic out) => out['protocol'] == 'dns',
    );
    // Go пишет dns-out литералом Map<String, String> — собираем заново.
    outbounds[dnsOut] = <String, dynamic>{
      ...outbounds[dnsOut] as Map,
      'settings': {
        'rules': [
          {'action': 'return', 'rCode': 0, 'domain': adServer['domains']},
        ],
      },
    };
  }

  /// xray-rust reads a DoT server's port only from its `tls://` URL and ignores
  /// the object's `port`, so a custom DoT port would silently become 853.
  /// A plain server keeps `port`, but its IPv6 literal must be unbracketed.
  static final _dotAuthorityWithPort =
      RegExp(r'^tls://(\[[^\]]*\]|[^:\[\]]+):\d+$');

  static void _adaptDnsServers(Map<String, dynamic> dns) {
    for (final dynamic server in dns['servers'] as List<dynamic>) {
      if (server is! Map) continue;
      final address = server['address'] as String;
      if (address.startsWith('tls://') && server['port'] is int) {
        final port = server.remove('port');
        // DnsServerConfig оставляет `]:port` у IPv6 в скобках; второй порт
        // xray-rust отвергает, поэтому порт из URL сохраняем как есть.
        if (!_dotAuthorityWithPort.hasMatch(address)) {
          server['address'] = '$address:$port';
        }
      } else if (address.startsWith('[') && address.endsWith(']')) {
        server['address'] = address.substring(1, address.length - 1);
      }
    }
  }

  static String buildJson(VpnConfig config, VpnEngineOptions options) =>
      jsonEncode(build(config, options));

  /// Candidate check for switchConfig (`XrayEngine.measureOutbound`): the
  /// profile's proxy outbound, exactly as [build] writes it for the VPN, in a
  /// config Android starts as a temporary core beside the running one. It has
  /// no TUN, routing, FakeDNS or DNS module: `probeOutboundUrl` dials the proxy
  /// leaf directly and passes the target name to the server. xray-rust starts
  /// only with an inbound, so a loopback SOCKS listens on an ephemeral port and
  /// never collides with the VPN's SOCKS port. Android pins the server name
  /// into `dns.hosts` before the start, as for the VPN. Throws
  /// [FormatException] where [build] does.
  static Map<String, dynamic> buildProbe(
    VpnConfig config,
    VpnEngineOptions options,
  ) {
    final outbounds = build(config, options)['outbounds'] as List<dynamic>;
    final proxy = outbounds.singleWhere((dynamic o) => o['tag'] == 'proxy');
    return {
      'inbounds': [
        {
          'tag': 'probe-in',
          'protocol': 'socks',
          'listen': '127.0.0.1',
          'port': 0,
          'settings': {'auth': 'noauth', 'udp': false},
        },
      ],
      'outbounds': [proxy],
      'dns': {'hosts': <String, dynamic>{}},
    };
  }

  static String buildProbeJson(VpnConfig config, VpnEngineOptions options) =>
      jsonEncode(buildProbe(config, options));
}
