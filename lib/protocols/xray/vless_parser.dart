import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../core/models/vpn_config.dart';

class VlessParser {
  static VpnConfig? parseUri(String uri) {
    if (uri.startsWith('vless://')) return _parseVless(uri);
    if (uri.startsWith('vmess://')) return _parseVmess(uri);
    if (uri.startsWith('trojan://')) return _parseTrojan(uri);
    if (uri.startsWith('ss://')) return _parseShadowsocks(uri);
    return null;
  }

  // vless://uuid@host:port?params#name
  static VpnConfig? _parseVless(String uri) {
    try {
      final withoutScheme = uri.substring('vless://'.length);
      final hashIdx = withoutScheme.indexOf('#');
      final name = hashIdx >= 0
          ? Uri.decodeComponent(withoutScheme.substring(hashIdx + 1))
          : 'VLESS Server';
      final main =
          hashIdx >= 0 ? withoutScheme.substring(0, hashIdx) : withoutScheme;

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

      return VpnConfig(
        id: const Uuid().v4(),
        name: name.isEmpty ? '$host:$port' : name,
        protocol: VpnProtocol.vless,
        address: host,
        port: port,
        uuid: userInfo,
        security: security,
        transport: transport,
        sni: params['sni'] ?? params['serverName'],
        wsPath: Uri.decodeComponent(params['path'] ?? '/'),
        wsHost: params['host'],
        grpcServiceName: params['serviceName'],
        fingerprint: params['fp'],
        publicKey: params['pbk'],
        shortId: params['sid'],
        spiderX: params['spx'] != null
            ? Uri.decodeComponent(params['spx']!)
            : null,
        postQuantumKey: params['pqv'],
        flow: params['flow'],
        encryption: params['encryption'] ?? 'none',
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
      final name = json['ps'] as String? ?? '$host:$port';

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
      final name = hashIdx >= 0
          ? Uri.decodeComponent(withoutScheme.substring(hashIdx + 1))
          : 'Trojan Server';
      final main =
          hashIdx >= 0 ? withoutScheme.substring(0, hashIdx) : withoutScheme;

      final atIdx = main.lastIndexOf('@');
      if (atIdx < 0) return null;
      final password = main.substring(0, atIdx);
      final hostPart = main.substring(atIdx + 1);

      final qIdx = hostPart.indexOf('?');
      final hostPort = qIdx >= 0 ? hostPart.substring(0, qIdx) : hostPart;
      final queryStr = qIdx >= 0 ? hostPart.substring(qIdx + 1) : '';

      final (host, port) = _parseHostPort(hostPort, 443);
      final params = Uri.splitQueryString(queryStr);

      return VpnConfig(
        id: const Uuid().v4(),
        name: name.isEmpty ? '$host:$port' : name,
        protocol: VpnProtocol.trojan,
        address: host,
        port: port,
        uuid: '',
        password: password,
        security: VpnSecurity.tls,
        transport: _parseTransport(params['type'] ?? 'tcp'),
        sni: params['sni'] ?? params['peer'],
        wsPath: params['path'],
        wsHost: params['host'],
        fingerprint: params['fp'],
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
      final name = hashIdx >= 0
          ? Uri.decodeComponent(withoutScheme.substring(hashIdx + 1))
          : 'Shadowsocks Server';
      final main =
          hashIdx >= 0 ? withoutScheme.substring(0, hashIdx) : withoutScheme;

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

        String decoded;
        try {
          decoded = utf8.decode(base64Decode(_padBase64(userInfo)));
        } catch (_) {
          decoded = userInfo;
        }

        final colonIdx = decoded.indexOf(':');
        method = decoded.substring(0, colonIdx);
        password = decoded.substring(colonIdx + 1);
        (host, port) = _parseHostPort(hostPortClean, 8388);
      } else {
        final decoded =
            utf8.decode(base64Decode(_padBase64(main)));
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
              ssPrefix = prefixBytes
                  .map((b) => b.toRadixString(16).padLeft(2, '0'))
                  .join();
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

  static (String, int) _parseHostPort(String hostPort, int defaultPort) {
    if (hostPort.startsWith('[')) {
      // IPv6
      final closeBracket = hostPort.indexOf(']');
      final host = hostPort.substring(1, closeBracket);
      final rest = hostPort.substring(closeBracket + 1);
      final port = rest.startsWith(':')
          ? int.tryParse(rest.substring(1)) ?? defaultPort
          : defaultPort;
      return (host, port);
    }
    final colonIdx = hostPort.lastIndexOf(':');
    if (colonIdx < 0) return (hostPort, defaultPort);
    final host = hostPort.substring(0, colonIdx);
    final port = int.tryParse(hostPort.substring(colonIdx + 1)) ?? defaultPort;
    return (host, port);
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
