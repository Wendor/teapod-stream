import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../core/models/vpn_config.dart';
import '../parsers/amnezia_key_parser.dart';
import '../parsers/naive_parser.dart';
import '../parsers/ssh_parser.dart';
import '../parsers/wireguard_parser.dart';

Map<String, dynamic>? _parseExtra(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = Uri.decodeComponent(raw);
    final json = jsonDecode(decoded);
    return json is Map<String, dynamic> ? json : null;
  } catch (_) {
    return null;
  }
}

class VlessParser {
  static VpnConfig? parseUri(String uri) {
    uri = uri.trim();
    // Chat/Markdown exports may escape URI punctuation. Only undo the
    // punctuation escapes, preserving percent-encoded path/query values.
    if (uri.startsWith(r'vless\://')) {
      uri = uri.replaceAllMapped(RegExp(r'\\([:@_])'), (m) => m[1]!);
    }
    if (WireGuardParser.isConf(uri)) {
      try {
        return WireGuardParser.parseConf(uri);
      } on FormatException {
        return null;
      }
    }
    if (uri.startsWith('wireguard://') || uri.startsWith('wg://')) return WireGuardParser.parseUri(uri);
    if (uri.startsWith('vpn://')) return AmneziaKeyParser.parse(uri);
    if (uri.startsWith('ssh://')) return SshParser.parseUri(uri);
    if (uri.startsWith('naive+https://') || uri.startsWith('naive+quic://')) return NaiveParser.parseUri(uri);
    if (uri.startsWith('vless://')) return _parseVless(uri);
    if (uri.startsWith('vmess://')) return _parseVmess(uri);
    if (uri.startsWith('trojan://')) return _parseTrojan(uri);
    if (uri.startsWith('ss://')) return _parseShadowsocks(uri);
    if (uri.startsWith('hy2://') || uri.startsWith('hysteria2://')) return _parseHysteria2(uri);
    return null;
  }

  static String _cleanName(String name) {
    return name.replaceFirst(RegExp(r'^[\s\-\—\–]+'), '');
  }

  static String _decodeName(String raw) {
    try {
      return _cleanName(Uri.decodeComponent(raw));
    } catch (_) {
      return _cleanName(raw);
    }
  }

  // vless://uuid@host:port?params#name
  static VpnConfig? _parseVless(String uri) {
    try {
      final withoutScheme = uri.substring('vless://'.length);
      final hashIdx = withoutScheme.indexOf('#');
      final name = hashIdx >= 0 ? _decodeName(withoutScheme.substring(hashIdx + 1)) : 'VLESS Server';
      final main = hashIdx >= 0 ? withoutScheme.substring(0, hashIdx) : withoutScheme;

      final atIdx = main.lastIndexOf('@');
      if (atIdx < 0) return null;
      final userInfo = main.substring(0, atIdx);
      final hostPart = main.substring(atIdx + 1);

      final qIdx = hostPart.indexOf('?');
      final hostPort = qIdx >= 0 ? hostPart.substring(0, qIdx) : hostPart;
      final queryStr = qIdx >= 0 ? hostPart.substring(qIdx + 1) : '';

      final (host, port) = _parseHostPort(hostPort, 443);
      final params = Uri.splitQueryString(queryStr);

      final security = _parseSecurity(params['security'] ?? 'none');
      final transport = _parseTransport(params['type'] ?? 'tcp');
      final allowInsecure = _parseInsecure(params);
      final pinSHA256 = params['pinSHA256'];

      return VpnConfig(
        id: const Uuid().v4(),
        name: name.isEmpty ? '$host:$port' : name,
        protocol: VpnProtocol.vless,
        address: host,
        port: port,
        uuid: userInfo,
        security: security,
        transport: transport,
        allowInsecure: allowInsecure,
        pinSHA256: pinSHA256,
        sni: params['sni'] ?? params['serverName'],
        wsPath: params['path'] ?? '/',
        wsHost: params['host'],
        grpcServiceName: params['serviceName'],
        fingerprint: params['fp'],
        publicKey: params['pbk'],
        shortId: params['sid'],
        spiderX: params['spx'],
        postQuantumKey: params['pqv'],
        flow: params['flow'],
        encryption: params['encryption'] ?? 'none',
        xhttpMode: params['mode'],
        xhttpExtra:
            _parseExtra(params['extra']) ??
            (params['x_padding_bytes'] == null ? null : {'xPaddingBytes': params['x_padding_bytes']}),
        finalmask: _parseExtra(params['fm']),
        alpn: params['alpn'],
        ech: params['ech'],
        createdAt: DateTime.now(),
        rawUri: uri,
      );
    } catch (e) {
      return null;
    }
  }

  // vmess://base64(json)
  static VpnConfig? _parseVmess(String uri) {
    try {
      final encoded = uri.substring('vmess://'.length);
      final decoded = utf8.decode(base64Decode(_padBase64(encoded)));
      final json = jsonDecode(decoded) as Map<String, dynamic>;

      final port = int.tryParse(json['port']?.toString() ?? '443') ?? 443;
      final host = json['add'] as String? ?? '';
      final rawName = json['ps'] as String? ?? '$host:$port';
      final name = _cleanName(rawName);

      final net = json['net'] as String? ?? 'tcp';
      final tls = json['tls'] as String? ?? '';

      return VpnConfig(
        id: const Uuid().v4(),
        name: name,
        protocol: VpnProtocol.vmess,
        address: host,
        port: port,
        uuid: json['id'] as String? ?? '',
        security: tls == 'tls' ? VpnSecurity.tls : VpnSecurity.none,
        transport: _parseTransport(net),
        sni: json['sni'] as String?,
        wsPath: json['path'] as String?,
        wsHost: json['host'] as String?,
        grpcServiceName: json['path'] as String?,
        alterId: json['aid']?.toString() ?? '0',
        xhttpMode: json['mode'] as String?,
        xhttpExtra: json['extra'] is Map<String, dynamic> ? json['extra'] as Map<String, dynamic> : null,
        createdAt: DateTime.now(),
        rawUri: uri,
      );
    } catch (e) {
      return null;
    }
  }

  // trojan://password@host:port?params#name
  static VpnConfig? _parseTrojan(String uri) {
    try {
      final withoutScheme = uri.substring('trojan://'.length);
      final hashIdx = withoutScheme.indexOf('#');
      final name = hashIdx >= 0 ? _decodeName(withoutScheme.substring(hashIdx + 1)) : 'Trojan Server';
      final main = hashIdx >= 0 ? withoutScheme.substring(0, hashIdx) : withoutScheme;

      final atIdx = main.lastIndexOf('@');
      if (atIdx < 0) return null;
      // The password in the link is percent-encoded (trojan-gfw scheme; v2rayN/v2rayNG
      // decode it); a broken % leaves the string as is.
      final password = _decodeComponentOrRaw(main.substring(0, atIdx));
      final hostPart = main.substring(atIdx + 1);

      final qIdx = hostPart.indexOf('?');
      final hostPort = qIdx >= 0 ? hostPart.substring(0, qIdx) : hostPart;
      final queryStr = qIdx >= 0 ? hostPart.substring(qIdx + 1) : '';

      final (host, port) = _parseHostPort(hostPort, 443);
      final params = Uri.splitQueryString(queryStr);
      // Trojan defaults to TLS, but the link may set reality or none —
      // previously they silently turned into TLS, and pbk/sid, pinSHA256, alpn and ech
      // were lost. allowInsecure is still not read: without a pin the certificate
      // is verified as before.
      final security = switch (params['security']?.trim().toLowerCase()) {
        'reality' => VpnSecurity.reality,
        'none' => VpnSecurity.none,
        _ => VpnSecurity.tls,
      };

      return VpnConfig(
        id: const Uuid().v4(),
        name: name.isEmpty ? '$host:$port' : name,
        protocol: VpnProtocol.trojan,
        address: host,
        port: port,
        uuid: '',
        password: password,
        security: security,
        transport: _parseTransport(params['type'] ?? 'tcp'),
        pinSHA256: params['pinSHA256'],
        sni: params['sni'] ?? params['peer'],
        wsPath: params['path'],
        wsHost: params['host'],
        fingerprint: params['fp'],
        publicKey: params['pbk'],
        shortId: params['sid'],
        spiderX: params['spx'],
        postQuantumKey: params['pqv'],
        grpcServiceName: params['serviceName'],
        xhttpMode: params['mode'],
        xhttpExtra: _parseExtra(params['extra']),
        alpn: params['alpn'],
        ech: params['ech'],
        createdAt: DateTime.now(),
        rawUri: uri,
      );
    } catch (e) {
      return null;
    }
  }

  // ss://base64(method:password)@host:port[/?query][#name]  OR  ss://base64(method:password@host:port)[#name]
  static VpnConfig? _parseShadowsocks(String uri) {
    try {
      final withoutScheme = uri.substring('ss://'.length);
      final hashIdx = withoutScheme.indexOf('#');
      final name = hashIdx >= 0 ? _decodeName(withoutScheme.substring(hashIdx + 1)) : 'Shadowsocks Server';
      final main = hashIdx >= 0 ? withoutScheme.substring(0, hashIdx) : withoutScheme;

      String method, password, host;
      int port;

      String queryStr = '';

      if (main.contains('@')) {
        final atIdx = main.lastIndexOf('@');
        final userInfo = main.substring(0, atIdx);
        final hostPart = main.substring(atIdx + 1);

        // Strip query string and trailing slash from host:port
        final qIdx = hostPart.indexOf('?');
        final hostPortRaw = qIdx >= 0 ? hostPart.substring(0, qIdx) : hostPart;
        final hostPortClean = hostPortRaw.endsWith('/')
            ? hostPortRaw.substring(0, hostPortRaw.length - 1)
            : hostPortRaw;
        if (qIdx >= 0) queryStr = hostPart.substring(qIdx + 1);

        // SIP002: userinfo — base64url(method:password) or, for SS2022,
        // percent-encoded `method:password`. Previously the key's %2B/%3D/%3A
        // stayed in the password as is.
        final plainUserInfo = _decodeComponentOrRaw(userInfo);
        String decoded;
        try {
          decoded = utf8.decode(base64Decode(_padBase64(plainUserInfo)));
        } catch (_) {
          decoded = plainUserInfo;
        }

        final colonIdx = decoded.indexOf(':');
        method = decoded.substring(0, colonIdx);
        password = decoded.substring(colonIdx + 1);
        (host, port) = _parseHostPort(hostPortClean, 8388);
      } else {
        final decoded = utf8.decode(base64Decode(_padBase64(main)));
        final atIdx = decoded.lastIndexOf('@');
        if (atIdx < 0) return null;
        final userInfo = decoded.substring(0, atIdx);
        final hostPart = decoded.substring(atIdx + 1);
        final qIdx = hostPart.indexOf('?');
        final hostPortClean = qIdx >= 0 ? hostPart.substring(0, qIdx) : hostPart;
        if (qIdx >= 0) queryStr = hostPart.substring(qIdx + 1);
        final colonIdx = userInfo.indexOf(':');
        method = userInfo.substring(0, colonIdx);
        password = userInfo.substring(colonIdx + 1);
        (host, port) = _parseHostPort(hostPortClean, 8388);
      }

      // Parse Outline prefix bytes (raw percent-encoded bytes, not UTF-8 characters)
      String? ssPrefix;
      if (queryStr.isNotEmpty) {
        for (final param in queryStr.split('&')) {
          final eqIdx = param.indexOf('=');
          if (eqIdx < 0) continue;
          if (param.substring(0, eqIdx) == 'prefix') {
            final prefixBytes = _decodePercentBytes(param.substring(eqIdx + 1));
            if (prefixBytes.isNotEmpty) {
              ssPrefix = prefixBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
            }
            break;
          }
        }
      }

      return VpnConfig(
        id: const Uuid().v4(),
        name: name.isEmpty ? '$host:$port' : name,
        protocol: VpnProtocol.shadowsocks,
        address: host,
        port: port,
        uuid: '',
        method: method,
        password: password,
        security: VpnSecurity.none,
        transport: VpnTransport.tcp,
        ssPrefix: ssPrefix,
        createdAt: DateTime.now(),
        rawUri: uri,
      );
    } catch (e) {
      return null;
    }
  }

  // hy2://password@host:port?sni=...&obfs=salamander&obfs-password=...#name
  // Gecko: obfs=gecko&obfs-password=...[&minPacketSize=512&maxPacketSize=1200] (v2rayN names)
  // also handles hysteria2:// scheme
  static VpnConfig? _parseHysteria2(String uri) {
    try {
      final scheme = uri.startsWith('hysteria2://') ? 'hysteria2://' : 'hy2://';
      final withoutScheme = uri.substring(scheme.length);
      final hashIdx = withoutScheme.indexOf('#');
      final name = hashIdx >= 0 ? _decodeName(withoutScheme.substring(hashIdx + 1)) : 'Hysteria2 Server';
      final main = hashIdx >= 0 ? withoutScheme.substring(0, hashIdx) : withoutScheme;

      final atIdx = main.lastIndexOf('@');
      if (atIdx < 0) return null;
      final password = Uri.decodeComponent(main.substring(0, atIdx));
      final hostPart = main.substring(atIdx + 1);

      final qIdx = hostPart.indexOf('?');
      var hostPort = qIdx >= 0 ? hostPart.substring(0, qIdx) : hostPart;
      final queryStr = qIdx >= 0 ? hostPart.substring(qIdx + 1) : '';
      // The official link format is `host:port/?…`: the path isn't part of the port.
      final slashIdx = hostPort.indexOf('/');
      if (slashIdx >= 0) hostPort = hostPort.substring(0, slashIdx);

      final (host, portSpec) = _splitHostPortSpec(hostPort);
      final params = Uri.splitQueryString(queryStr);
      // Port hopping: a range/list instead of a port (`20000-30000`,
      // `443,5000-6000`) or `mport` from v2rayN. An unrecognized port is an import
      // error, not a silent 443: with a wrong port the profile simply won't connect.
      final ports = _parsePortSpec(portSpec, 443);
      if (ports == null) return null;
      final port = ports.$1;
      var hopPorts = ports.$2;
      final mport = params['mport']?.trim() ?? '';
      if (hopPorts == null && mport.isNotEmpty) {
        final hop = _parsePortSpec(mport, port);
        // An unrecognized mport (`20000:30000` from sing-box, garbage) doesn't break
        // the link: the main port is valid, we connect to it without hopping.
        if (hop != null && hop.$1 >= 1 && hop.$1 <= 65535 && (hop.$2 != null || hop.$1 != port)) {
          hopPorts = hop.$2 ?? '${hop.$1}';
        }
      }

      // Salamander and Gecko (Salamander plus packet fragmentation) share obfs-password; a Gecko link without a
      // password or with invalid packet sizes is an import error: the server drops unobfuscated packets.
      final obfs = params['obfs']?.trim() ?? '';
      final obfsPassword = obfs == 'salamander' || obfs == 'gecko' ? params['obfs-password'] : null;
      if (obfs == 'gecko' && ((obfsPassword?.isEmpty ?? true) || geckoSizes(params) == null)) return null;
      final allowInsecure = _parseInsecure(params);
      final pinSHA256 = params['pinSHA256'];

      return VpnConfig(
        id: const Uuid().v4(),
        name: name.isEmpty ? '$host:$port' : name,
        protocol: VpnProtocol.hysteria2,
        address: host,
        port: port,
        uuid: '',
        password: password,
        security: VpnSecurity.tls,
        transport: VpnTransport.tcp,
        allowInsecure: allowInsecure,
        pinSHA256: pinSHA256,
        sni: params['sni'],
        obfsPassword: obfsPassword,
        hopPorts: hopPorts,
        createdAt: DateTime.now(),
        rawUri: uri,
      );
    } catch (e) {
      return null;
    }
  }

  static String _decodeComponentOrRaw(String value) {
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return value;
    }
  }

  static bool _parseInsecure(Map<String, String> params) {
    final val = params['allowInsecure'] ?? params['insecure'];
    return val == '1' || val == 'true';
  }

  static (String, int) _parseHostPort(String hostPort, int defaultPort) {
    if (hostPort.startsWith('[')) {
      // IPv6
      final closeBracket = hostPort.indexOf(']');
      final host = hostPort.substring(1, closeBracket);
      final rest = hostPort.substring(closeBracket + 1);
      final port = rest.startsWith(':') ? int.tryParse(rest.substring(1)) ?? defaultPort : defaultPort;
      return (host, port);
    }
    final colonIdx = hostPort.lastIndexOf(':');
    if (colonIdx < 0) return (hostPort, defaultPort);
    final host = hostPort.substring(0, colonIdx);
    final port = int.tryParse(hostPort.substring(colonIdx + 1)) ?? defaultPort;
    return (host, port);
  }

  /// Host and the raw port string; IPv6 — in square brackets.
  static (String, String) _splitHostPortSpec(String hostPort) {
    if (hostPort.startsWith('[')) {
      final closeBracket = hostPort.indexOf(']');
      final rest = hostPort.substring(closeBracket + 1);
      return (hostPort.substring(1, closeBracket), rest.startsWith(':') ? rest.substring(1) : '');
    }
    final colonIdx = hostPort.lastIndexOf(':');
    if (colonIdx < 0) return (hostPort, '');
    return (hostPort.substring(0, colonIdx), hostPort.substring(colonIdx + 1));
  }

  static final _portRange = RegExp(r'^(\d{1,5})(?:-(\d{1,5}))?$');

  /// Hysteria2 port: a single number or a list of ports/ranges for port
  /// hopping. Returns the first port and the normalized list (null if
  /// there's one port); null — the string didn't parse. An empty string — [defaultPort].
  static (int, String?)? _parsePortSpec(String spec, int defaultPort) {
    final trimmed = spec.replaceAll(' ', '');
    if (trimmed.isEmpty) return (defaultPort, null);
    final single = int.tryParse(trimmed);
    // Single-port bounds are checked by VpnConfig.validate().
    if (single != null) return (single, null);
    final parts = trimmed.split(',');
    int? first;
    for (final part in parts) {
      final match = _portRange.firstMatch(part);
      if (match == null) return null;
      final from = int.parse(match[1]!);
      final to = match[2] == null ? from : int.parse(match[2]!);
      if (from < 1 || to > 65535 || from > to) return null;
      first ??= from;
    }
    return (first!, parts.join(','));
  }

  static VpnSecurity _parseSecurity(String s) {
    switch (s.toLowerCase()) {
      case 'tls':
        return VpnSecurity.tls;
      case 'reality':
        return VpnSecurity.reality;
      default:
        return VpnSecurity.none;
    }
  }

  static VpnTransport _parseTransport(String s) {
    switch (s.toLowerCase()) {
      case 'ws':
      case 'websocket':
        return VpnTransport.ws;
      case 'grpc':
        return VpnTransport.grpc;
      case 'h2':
      case 'http':
        return VpnTransport.http2;
      case 'quic':
        return VpnTransport.quic;
      case 'xhttp':
        return VpnTransport.xhttp;
      case 'httpupgrade':
        return VpnTransport.httpupgrade;
      case 'splithttp':
        return VpnTransport.splithttp;
      default:
        return VpnTransport.tcp;
    }
  }

  /// Query parameters of the profile's original link, including the base64 body of SIP002
  /// `ss://BASE64#name`. Empty if there's no link or it's unreadable. Needed by
  /// builders for fields [VpnConfig] doesn't have (headerType, obfs, plugin).
  /// Gecko packet sizes `(min, max)` of a Hysteria2 profile imported with `obfs=gecko`; null for Salamander
  /// or no obfuscation.
  static (int, int)? geckoPacketSize(VpnConfig config) {
    final params = linkParams(config);
    return params['obfs']?.trim() == 'gecko' ? geckoSizes(params) : null;
  }

  /// `minPacketSize` / `maxPacketSize` of a Gecko link, 512 / 1200 when absent (the Hysteria defaults); null when
  /// not numbers or outside `0 < min <= max <= 2048` (both cores refuse such a config).
  static (int, int)? geckoSizes(Map<String, String> params) {
    int? size(String key, int fallback) {
      final value = params[key]?.trim() ?? '';
      return value.isEmpty ? fallback : int.tryParse(value);
    }

    final min = size('minPacketSize', 512);
    final max = size('maxPacketSize', 1200);
    if (min == null || max == null || min <= 0 || min > max || max > 2048) return null;
    return (min, max);
  }

  static Map<String, String> linkParams(VpnConfig config) {
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

  /// `mux=on` / `mux=off` in the link: Mux for this server regardless of the global setting,
  /// over xhttp too (a server behind a GET-only CDN pads the download with Mux frames).
  /// null — no parameter or an unknown value.
  static bool? linkMux(VpnConfig config) => switch (linkParams(config)['mux']?.trim().toLowerCase()) {
    'on' || 'true' || '1' => true,
    'off' || 'false' || '0' => false,
    _ => null,
  };

  /// JSON body of `vmess://BASE64(JSON)` the profile was read from.
  static Map<String, dynamic> vmessJson(VpnConfig config) {
    final raw = config.rawUri;
    if (raw == null || !raw.startsWith('vmess://')) return const {};
    try {
      final json = jsonDecode(utf8.decode(base64Decode(_padBase64(raw.substring('vmess://'.length)))));
      return json is Map<String, dynamic> ? json : const {};
    } catch (_) {
      return const {};
    }
  }

  static String _padBase64(String s) {
    final mod = s.length % 4;
    if (mod == 0) return s;
    return s + '=' * (4 - mod);
  }

  // Decode percent-encoded string as raw bytes (not UTF-8 characters).
  // Handles sequences like %C2%A8 as two separate bytes [0xC2, 0xA8].
  static List<int> _decodePercentBytes(String encoded) {
    final bytes = <int>[];
    var i = 0;
    while (i < encoded.length) {
      final c = encoded[i];
      if (c == '%' && i + 2 < encoded.length) {
        final hex = encoded.substring(i + 1, i + 3);
        bytes.add(int.parse(hex, radix: 16));
        i += 3;
      } else if (c == '+') {
        bytes.add(0x20);
        i++;
      } else {
        bytes.add(c.codeUnitAt(0));
        i++;
      }
    }
    return bytes;
  }
}
