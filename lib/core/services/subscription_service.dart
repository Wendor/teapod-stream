import 'dart:convert';
import 'dart:io';
import '../constants/app_constants.dart';
import '../models/vpn_config.dart';
import '../../protocols/xray/vless_parser.dart';
import 'subscription_routing_parser.dart';

/// Thrown when the subscription server presents an untrusted TLS certificate.
class UntrustedCertificateException implements Exception {
  final String host;
  final String subject;
  final String issuer;

  const UntrustedCertificateException({
    required this.host,
    required this.subject,
    required this.issuer,
  });

  @override
  String toString() => 'UntrustedCertificateException: $host — $subject (issued by $issuer)';
}

class SubscriptionFetchResult {
  final List<VpnConfig> configs;
  final String? profileTitle;
  final DateTime? expireAt;
  final int? uploadBytes;
  final int? downloadBytes;
  final int? totalBytes;
  final String? announce;
  final String? announceUrl;
  final HwidStatus? hwidStatus;
  final String? routingJson;

  const SubscriptionFetchResult({
    required this.configs,
    this.profileTitle,
    this.expireAt,
    this.uploadBytes,
    this.downloadBytes,
    this.totalBytes,
    this.announce,
    this.announceUrl,
    this.hwidStatus,
    this.routingJson,
  });
}

class HwidStatus {
  final bool isActive;
  final bool notSupported;
  final bool maxDevicesReached;

  const HwidStatus({
    required this.isActive,
    required this.notSupported,
    required this.maxDevicesReached,
  });
}

class HwidDeviceInfo {
  final String deviceId;
  final String deviceModel;
  final int osVersion;

  const HwidDeviceInfo({
    required this.deviceId,
    required this.deviceModel,
    required this.osVersion,
  });

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'deviceModel': deviceModel,
    'osVersion': osVersion,
  };
}

class SubscriptionService {
  /// Fetch and parse a subscription URL.
  ///
  /// If [allowSelfSigned] is false (default) and the server presents an
  /// untrusted certificate, throws [UntrustedCertificateException] with
  /// certificate details so the caller can decide whether to retry.
  /// If [allowSelfSigned] is true, certificate validation is skipped.
  /// If [hwidEnabled] is true, HWID headers are sent to support device limits.
  /// If [userAgent] is non-empty, it overrides the default User-Agent.
  Future<SubscriptionFetchResult> fetchSubscription(
    String url, {
    bool allowSelfSigned = false,
    HwidDeviceInfo? hwid,
    String? userAgent,
  }) async {
    final uri = Uri.parse(url);
    final httpClient = HttpClient();

    UntrustedCertificateException? certError;

    httpClient.badCertificateCallback =
        (X509Certificate cert, String host, int port) {
      if (allowSelfSigned) return true;
      certError = UntrustedCertificateException(
        host: host,
        subject: cert.subject,
        issuer: cert.issuer,
      );
      return false;
    };

    String body;
    HttpHeaders responseHeaders;
    try {
      final request = await httpClient.getUrl(uri);
      final ua = userAgent?.trim() ?? '';
      request.headers.set('User-Agent', ua.isNotEmpty ? ua : AppConstants.subscriptionUserAgent);

      if (hwid != null) {
        request.headers.set('X-Hwid', hwid.deviceId);
        request.headers.set('X-Device-Os', 'Android');
        request.headers.set('X-Device-Model', hwid.deviceModel);
        request.headers.set('X-Ver-Os', hwid.osVersion.toString());
      }

      final response =
          await request.close().timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch subscription: ${response.statusCode}');
      }

      responseHeaders = response.headers;
      body = await response.transform(utf8.decoder).join();
    } on HandshakeException {
      if (certError != null) throw certError!;
      rethrow;
    } finally {
      httpClient.close();
    }

    final meta = _parseHeaders(responseHeaders);

    body = body.trim();
    List<String> lines;
    final configs = <VpnConfig>[];
    List<Map<String, dynamic>>? detectedRules;

    if (meta.routing != null) {
      detectedRules = SubscriptionRoutingParser.parse(meta.routing);
    }

    // Try fetching remote ruleset URL if header provided and no inline rules yet
    final ua = userAgent?.trim() ?? '';
    if (detectedRules == null && meta.rulesetUrl != null && meta.rulesetUrl!.startsWith('http')) {
      try {
        final rulesReq = await httpClient.getUrl(Uri.parse(meta.rulesetUrl!));
        rulesReq.headers.set('User-Agent', ua.isNotEmpty ? ua : AppConstants.subscriptionUserAgent);
        final rulesResp = await rulesReq.close().timeout(const Duration(seconds: 10));
        if (rulesResp.statusCode == 200) {
          final rulesBody = await rulesResp.transform(utf8.decoder).join();
          detectedRules = SubscriptionRoutingParser.parse(rulesBody);
        }
      } catch (_) {
        // Best effort
      }
    }

    // Detect pre-built JSON config (sing-box, Xray multi-outbound, or managed array).
    if (body.startsWith('[') || body.startsWith('{')) {
      try {
        final jsonData = jsonDecode(body);
        final rulesFromJson = SubscriptionRoutingParser.parse(jsonData);
        if (rulesFromJson != null && rulesFromJson.isNotEmpty) {
          detectedRules = [...?detectedRules, ...rulesFromJson];
        }

        final extracted = _extractConfigsFromJson(jsonData);
        if (extracted.isNotEmpty) {
          configs.addAll(extracted);
          return SubscriptionFetchResult(
            configs: configs,
            profileTitle: meta.profileTitle,
            expireAt: meta.expireAt,
            uploadBytes: meta.uploadBytes,
            downloadBytes: meta.downloadBytes,
            totalBytes: meta.totalBytes,
            announce: meta.announce,
            announceUrl: meta.announceUrl,
            hwidStatus: meta.hwidStatus,
            routingJson: detectedRules != null && detectedRules.isNotEmpty
                ? jsonEncode(detectedRules)
                : null,
          );
        }
      } catch (_) {
        // Not valid JSON — fall through to standard URI parsing.
      }
    }

    // Plain-text URI list takes priority: a body that already contains known
    // URI schemes is never base64 (guards against text that happens to decode).
    lines = _splitLines(body);
    if (!lines.any(_isKnownUri)) {
      // Try base64. Many providers wrap output at 76 chars (RFC 2045), so strip
      // all whitespace before decoding — otherwise base64Decode throws and each
      // 76-char chunk would be treated as a separate URI (→ 0 configs).
      try {
        final cleaned = body.replaceAll(RegExp(r'\s'), '');
        final padded = cleaned.padRight((cleaned.length + 3) ~/ 4 * 4, '=');
        final decoded = utf8.decode(base64Decode(padded));
        if (decoded.trim().startsWith('[') || decoded.trim().startsWith('{')) {
          try {
            final jsonDecoded = jsonDecode(decoded);
            final rulesFromJson = SubscriptionRoutingParser.parse(jsonDecoded);
            if (rulesFromJson != null && rulesFromJson.isNotEmpty) {
              detectedRules = [...?detectedRules, ...rulesFromJson];
            }
            final extracted = _extractConfigsFromJson(jsonDecoded);
            if (extracted.isNotEmpty) {
              configs.addAll(extracted);
              return SubscriptionFetchResult(
                configs: configs,
                profileTitle: meta.profileTitle,
                expireAt: meta.expireAt,
                uploadBytes: meta.uploadBytes,
                downloadBytes: meta.downloadBytes,
                totalBytes: meta.totalBytes,
                announce: meta.announce,
                announceUrl: meta.announceUrl,
                hwidStatus: meta.hwidStatus,
                routingJson: detectedRules != null && detectedRules.isNotEmpty
                    ? jsonEncode(detectedRules)
                    : null,
              );
            }
          } catch (_) {}
        }
        final decodedLines = _splitLines(decoded);
        if (decodedLines.any(_isKnownUri)) lines = decodedLines;
      } catch (_) {
        // Not base64 either — keep the raw lines, the parser will skip them.
      }
    }

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('routing://') ||
          trimmed.startsWith('rules://') ||
          trimmed.startsWith('ruleset://') ||
          trimmed.startsWith('rule://') ||
          trimmed.startsWith('sub-rule://')) {
        final rules = SubscriptionRoutingParser.parse(trimmed);
        if (rules != null && rules.isNotEmpty) {
          detectedRules = [...?detectedRules, ...rules];
        }
        continue;
      }
      try {
        final config = VlessParser.parseUri(trimmed);
        if (config != null) configs.add(config);
      } catch (_) {
        // Skip unparseable lines
      }
    }

    return SubscriptionFetchResult(
      configs: configs,
      profileTitle: meta.profileTitle,
      expireAt: meta.expireAt,
      uploadBytes: meta.uploadBytes,
      downloadBytes: meta.downloadBytes,
      totalBytes: meta.totalBytes,
      announce: meta.announce,
      announceUrl: meta.announceUrl,
      hwidStatus: meta.hwidStatus,
      routingJson: detectedRules != null && detectedRules.isNotEmpty
          ? jsonEncode(detectedRules)
          : null,
    );
  }

  /// Extracts VpnConfig instances from JSON (sing-box, Xray multi-outbound, or managed arrays).
  static List<VpnConfig> _extractConfigsFromJson(dynamic jsonData) {
    final results = <VpnConfig>[];

    if (jsonData is Map<String, dynamic>) {
      // 1. sing-box or Xray configuration with outbounds
      if (jsonData.containsKey('outbounds') && jsonData['outbounds'] is List) {
        final outbounds = jsonData['outbounds'] as List<dynamic>;
        for (var i = 0; i < outbounds.length; i++) {
          final ob = outbounds[i];
          if (ob is! Map<String, dynamic>) continue;
          final cfg = _parseOutboundMap(ob, i);
          if (cfg != null) results.add(cfg);
        }
      }
      // 2. Clash JSON with proxies
      if (results.isEmpty && jsonData.containsKey('proxies') && jsonData['proxies'] is List) {
        final proxies = jsonData['proxies'] as List<dynamic>;
        for (var i = 0; i < proxies.length; i++) {
          final p = proxies[i];
          if (p is! Map<String, dynamic>) continue;
          final cfg = _parseClashProxy(p, i);
          if (cfg != null) results.add(cfg);
        }
      }
    } else if (jsonData is List) {
      for (var i = 0; i < jsonData.length; i++) {
        final item = jsonData[i];
        if (item is Map<String, dynamic>) {
          // Could be a single outbound
          final cfg = _parseOutboundMap(item, i);
          if (cfg != null) {
            results.add(cfg);
            continue;
          }
          // Could be a managed Xray config object with remarks and outbounds
          if (item.containsKey('outbounds') && item['outbounds'] is List) {
            final subOuts = item['outbounds'] as List<dynamic>;
            final rawRemarks = item['remarks'] as String? ?? 'Server $i';
            final remarks = rawRemarks.replaceFirst(RegExp(r'^[\s\-\—\–]+'), '');
            final rawJson = jsonEncode(item);
            String address = '';
            int port = 0;
            for (final outbound in subOuts) {
              if (outbound is! Map<String, dynamic>) continue;
              final tag = outbound['tag'] as String? ?? '';
              if (tag == 'direct' || tag == 'block' || tag.isEmpty) continue;
              final settings = outbound['settings'] as Map<String, dynamic>?;
              final vnext = settings?['vnext'] as List<dynamic>?;
              if (vnext != null && vnext.isNotEmpty) {
                final srv = vnext.first as Map<String, dynamic>;
                address = srv['address'] as String? ?? '';
                port = srv['port'] as int? ?? 0;
                break;
              }
              final servers = settings?['servers'] as List<dynamic>?;
              if (servers != null && servers.isNotEmpty) {
                final srv = servers.first as Map<String, dynamic>;
                address = srv['address'] as String? ?? '';
                port = srv['port'] as int? ?? 0;
                break;
              }
            }
            results.add(VpnConfig(
              id: 'xray_${DateTime.now().millisecondsSinceEpoch}_$i',
              name: remarks,
              protocol: VpnProtocol.vless,
              address: address.isEmpty ? 'managed' : address,
              port: port > 0 ? port : 443,
              uuid: '',
              security: VpnSecurity.none,
              transport: VpnTransport.tcp,
              createdAt: DateTime.now(),
              rawXrayConfig: rawJson,
            ));
          }
        } else if (item is String) {
          final cfg = VlessParser.parseUri(item.trim());
          if (cfg != null) results.add(cfg);
        }
      }
    }

    return results;
  }

  /// Parses a sing-box or Xray outbound map into a VpnConfig.
  static VpnConfig? _parseOutboundMap(Map<String, dynamic> ob, int index) {
    final rawTag = (ob['tag'] ?? ob['name'] ?? 'Server $index').toString();
    final tag = rawTag.replaceFirst(RegExp(r'^[\s\-\—\–]+'), '');
    final type = (ob['type'] ?? ob['protocol'] ?? '').toString().toLowerCase().trim();

    if (type == 'direct' || type == 'block' || type == 'dns' || type == 'freedom' || type == 'blackhole') {
      return null;
    }

    // 1. Try sing-box format: { "type": "vless", "server": "...", "server_port": 443, ... }
    final server = ob['server'] as String?;
    final serverPort = (ob['server_port'] as num?)?.toInt();
    if (server != null && server.isNotEmpty && serverPort != null && serverPort > 0) {
      final tls = ob['tls'] as Map<String, dynamic>?;
      final tlsEnabled = tls?['enabled'] == true;
      final reality = tls?['reality'] as Map<String, dynamic>?;
      final realityEnabled = reality?['enabled'] == true;
      final serverName = tls?['server_name'] as String?;
      final insecure = tls?['insecure'] == true;

      final transportMap = ob['transport'] as Map<String, dynamic>?;
      final transType = (transportMap?['type'] as String? ?? '').toLowerCase();
      VpnTransport transport = VpnTransport.tcp;
      String? wsPath;
      String? wsHost;
      String? grpcService;
      if (transType == 'ws') {
        transport = VpnTransport.ws;
        wsPath = transportMap?['path'] as String?;
        final headers = transportMap?['headers'] as Map<String, dynamic>?;
        wsHost = headers?['Host'] as String? ?? headers?['host'] as String?;
      } else if (transType == 'grpc') {
        transport = VpnTransport.grpc;
        grpcService = transportMap?['service_name'] as String?;
      } else if (transType == 'http' || transType == 'h2') {
        transport = VpnTransport.http2;
      }

      VpnSecurity security = VpnSecurity.none;
      if (realityEnabled) {
        security = VpnSecurity.reality;
      } else if (tlsEnabled) {
        security = VpnSecurity.tls;
      }

      if (type == 'vless') {
        return VpnConfig(
          id: 'sb_${DateTime.now().millisecondsSinceEpoch}_$index',
          name: tag,
          protocol: VpnProtocol.vless,
          address: server,
          port: serverPort,
          uuid: ob['uuid'] as String? ?? '',
          flow: ob['flow'] as String?,
          security: security,
          sni: serverName,
          publicKey: reality?['public_key'] as String?,
          shortId: reality?['short_id'] as String?,
          transport: transport,
          wsPath: wsPath,
          wsHost: wsHost,
          grpcServiceName: grpcService,
          allowInsecure: insecure,
          createdAt: DateTime.now(),
        );
      } else if (type == 'vmess') {
        return VpnConfig(
          id: 'sb_${DateTime.now().millisecondsSinceEpoch}_$index',
          name: tag,
          protocol: VpnProtocol.vmess,
          address: server,
          port: serverPort,
          uuid: ob['uuid'] as String? ?? '',
          security: security,
          sni: serverName,
          transport: transport,
          wsPath: wsPath,
          wsHost: wsHost,
          grpcServiceName: grpcService,
          allowInsecure: insecure,
          createdAt: DateTime.now(),
        );
      } else if (type == 'trojan') {
        return VpnConfig(
          id: 'sb_${DateTime.now().millisecondsSinceEpoch}_$index',
          name: tag,
          protocol: VpnProtocol.trojan,
          address: server,
          port: serverPort,
          uuid: '',
          password: ob['password'] as String? ?? '',
          security: security,
          sni: serverName,
          transport: transport,
          wsPath: wsPath,
          wsHost: wsHost,
          grpcServiceName: grpcService,
          allowInsecure: insecure,
          createdAt: DateTime.now(),
        );
      } else if (type == 'shadowsocks' || type == 'ss') {
        return VpnConfig(
          id: 'sb_${DateTime.now().millisecondsSinceEpoch}_$index',
          name: tag,
          protocol: VpnProtocol.shadowsocks,
          address: server,
          port: serverPort,
          uuid: '',
          password: ob['password'] as String? ?? '',
          method: ob['method'] as String? ?? 'chacha20-ietf-poly1305',
          security: VpnSecurity.none,
          transport: VpnTransport.tcp,
          createdAt: DateTime.now(),
        );
      } else if (type == 'hysteria2' || type == 'hy2') {
        return VpnConfig(
          id: 'sb_${DateTime.now().millisecondsSinceEpoch}_$index',
          name: tag,
          protocol: VpnProtocol.hysteria2,
          address: server,
          port: serverPort,
          uuid: '',
          password: ob['password'] as String? ?? '',
          security: VpnSecurity.tls,
          sni: serverName,
          allowInsecure: insecure,
          transport: VpnTransport.tcp,
          createdAt: DateTime.now(),
        );
      }
    }

    // 2. Try Xray outbound format: { "protocol": "vless", "settings": { "vnext": [...] }, "streamSettings": {...} }
    final settings = ob['settings'] as Map<String, dynamic>?;
    final stream = ob['streamSettings'] as Map<String, dynamic>?;
    String xAddress = '';
    int xPort = 0;
    String xUuid = '';
    String? xFlow;
    String? xPassword;
    String? xMethod;

    final vnext = settings?['vnext'] as List<dynamic>?;
    if (vnext != null && vnext.isNotEmpty) {
      final srv = vnext.first as Map<String, dynamic>;
      xAddress = srv['address'] as String? ?? '';
      xPort = srv['port'] as int? ?? 0;
      final users = srv['users'] as List<dynamic>?;
      if (users != null && users.isNotEmpty) {
        final u = users.first as Map<String, dynamic>;
        xUuid = u['id'] as String? ?? '';
        xFlow = u['flow'] as String?;
      }
    }

    final servers = settings?['servers'] as List<dynamic>?;
    if (servers != null && servers.isNotEmpty) {
      final srv = servers.first as Map<String, dynamic>;
      xAddress = srv['address'] as String? ?? '';
      xPort = srv['port'] as int? ?? 0;
      xPassword = srv['password'] as String?;
      xMethod = srv['method'] as String?;
    }

    if (xAddress.isNotEmpty && xPort > 0) {
      final netStr = stream?['network'] as String? ?? 'tcp';
      final secStr = stream?['security'] as String? ?? 'none';
      final tlsObj = stream?['tlsSettings'] as Map<String, dynamic>?;
      final realityObj = stream?['realitySettings'] as Map<String, dynamic>?;
      final wsObj = stream?['wsSettings'] as Map<String, dynamic>?;
      final grpcObj = stream?['grpcSettings'] as Map<String, dynamic>?;

      VpnSecurity sec = VpnSecurity.none;
      if (secStr == 'reality') {
        sec = VpnSecurity.reality;
      } else if (secStr == 'tls') {
        sec = VpnSecurity.tls;
      }

      final trans = switch (netStr) {
        'ws' => VpnTransport.ws,
        'grpc' => VpnTransport.grpc,
        'h2' || 'http' => VpnTransport.http2,
        _ => VpnTransport.tcp,
      };

      final proto = switch (type) {
        'vless' => VpnProtocol.vless,
        'vmess' => VpnProtocol.vmess,
        'trojan' => VpnProtocol.trojan,
        'shadowsocks' => VpnProtocol.shadowsocks,
        'hysteria2' || 'hysteria' => VpnProtocol.hysteria2,
        _ => VpnProtocol.vless,
      };

      return VpnConfig(
        id: 'xout_${DateTime.now().millisecondsSinceEpoch}_$index',
        name: tag,
        protocol: proto,
        address: xAddress,
        port: xPort,
        uuid: xUuid,
        flow: xFlow,
        password: xPassword,
        method: xMethod,
        security: sec,
        sni: realityObj?['serverName'] as String? ?? tlsObj?['serverName'] as String?,
        publicKey: realityObj?['publicKey'] as String?,
        shortId: realityObj?['shortId'] as String?,
        transport: trans,
        wsPath: wsObj?['path'] as String?,
        wsHost: (wsObj?['headers'] as Map<String, dynamic>?)?['Host'] as String?,
        grpcServiceName: grpcObj?['serviceName'] as String?,
        createdAt: DateTime.now(),
      );
    }

    return null;
  }

  /// Parses Clash proxy map into VpnConfig.
  static VpnConfig? _parseClashProxy(Map<String, dynamic> p, int index) {
    final name = (p['name'] ?? 'Clash $index').toString();
    final type = (p['type'] ?? '').toString().toLowerCase().trim();
    final server = p['server'] as String? ?? '';
    final port = (p['port'] as num?)?.toInt() ?? 0;
    if (server.isEmpty || port <= 0) return null;

    final tls = p['tls'] == true;
    final sni = p['sni'] as String? ?? p['servername'] as String?;
    final realityOpts = p['reality-opts'] as Map<String, dynamic>?;
    final reality = realityOpts != null;

    VpnSecurity sec = VpnSecurity.none;
    if (reality) {
      sec = VpnSecurity.reality;
    } else if (tls) {
      sec = VpnSecurity.tls;
    }

    final net = (p['network'] as String? ?? '').toLowerCase();
    VpnTransport trans = VpnTransport.tcp;
    String? wsPath;
    String? wsHost;
    String? grpcName;
    if (net == 'ws') {
      trans = VpnTransport.ws;
      final wsOpts = p['ws-opts'] as Map<String, dynamic>?;
      wsPath = wsOpts?['path'] as String?;
      final h = wsOpts?['headers'] as Map<String, dynamic>?;
      wsHost = h?['Host'] as String? ?? h?['host'] as String?;
    } else if (net == 'grpc') {
      trans = VpnTransport.grpc;
      final gOpts = p['grpc-opts'] as Map<String, dynamic>?;
      grpcName = gOpts?['grpc-service-name'] as String?;
    }

    if (type == 'vless') {
      return VpnConfig(
        id: 'clash_${DateTime.now().millisecondsSinceEpoch}_$index',
        name: name,
        protocol: VpnProtocol.vless,
        address: server,
        port: port,
        uuid: p['uuid'] as String? ?? '',
        flow: p['flow'] as String?,
        security: sec,
        sni: sni,
        publicKey: realityOpts?['public-key'] as String?,
        shortId: realityOpts?['short-id'] as String?,
        transport: trans,
        wsPath: wsPath,
        wsHost: wsHost,
        grpcServiceName: grpcName,
        createdAt: DateTime.now(),
      );
    } else if (type == 'ss') {
      return VpnConfig(
        id: 'clash_${DateTime.now().millisecondsSinceEpoch}_$index',
        name: name,
        protocol: VpnProtocol.shadowsocks,
        address: server,
        port: port,
        uuid: '',
        method: p['cipher'] as String? ?? 'chacha20-ietf-poly1305',
        password: p['password'] as String? ?? '',
        security: VpnSecurity.none,
        transport: VpnTransport.tcp,
        createdAt: DateTime.now(),
      );
    } else if (type == 'vmess') {
      return VpnConfig(
        id: 'clash_${DateTime.now().millisecondsSinceEpoch}_$index',
        name: name,
        protocol: VpnProtocol.vmess,
        address: server,
        port: port,
        uuid: p['uuid'] as String? ?? '',
        security: sec,
        sni: sni,
        transport: trans,
        wsPath: wsPath,
        wsHost: wsHost,
        grpcServiceName: grpcName,
        createdAt: DateTime.now(),
      );
    } else if (type == 'trojan') {
      return VpnConfig(
        id: 'clash_${DateTime.now().millisecondsSinceEpoch}_$index',
        name: name,
        protocol: VpnProtocol.trojan,
        address: server,
        port: port,
        uuid: '',
        password: p['password'] as String? ?? '',
        security: sec,
        sni: sni,
        transport: trans,
        wsPath: wsPath,
        wsHost: wsHost,
        grpcServiceName: grpcName,
        createdAt: DateTime.now(),
      );
    } else if (type == 'hysteria2' || type == 'hy2') {
      return VpnConfig(
        id: 'clash_${DateTime.now().millisecondsSinceEpoch}_$index',
        name: name,
        protocol: VpnProtocol.hysteria2,
        address: server,
        port: port,
        uuid: '',
        password: p['password'] as String? ?? '',
        security: VpnSecurity.tls,
        sni: sni,
        transport: VpnTransport.tcp,
        createdAt: DateTime.now(),
      );
    }

    return null;
  }

  static List<String> _splitLines(String s) =>
      s.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();

  static const _uriSchemes = ['vless://', 'vmess://', 'trojan://', 'ss://', 'hy2://', 'hysteria2://'];

  static bool _isKnownUri(String line) {
    final t = line.trim();
    return _uriSchemes.any(t.startsWith);
  }

  _HeaderMeta _parseHeaders(HttpHeaders headers) {
    String? profileTitle;
    DateTime? expireAt;
    int? uploadBytes;
    int? downloadBytes;
    int? totalBytes;
    String? announce;
    String? announceUrl;
    HwidStatus? hwidStatus;
    String? routing;
    String? rulesetUrl;

    final hwidActive = headers.value('x-hwid-active');
    final hwidNotSupported = headers.value('x-hwid-not-supported');
    final hwidMaxDevices = headers.value('x-hwid-max-devices-reached');

    if (hwidActive != null || hwidNotSupported != null || hwidMaxDevices != null) {
      hwidStatus = HwidStatus(
        isActive: hwidActive == 'true',
        notSupported: hwidNotSupported == 'true',
        maxDevicesReached: hwidMaxDevices == 'true',
      );
    }

    // profile-title: plain text or "base64:<encoded>"
    final rawTitle = headers.value('profile-title');
    if (rawTitle != null) {
      profileTitle = _decodeHeaderValue(rawTitle);
    }

    // Check for routing headers: profile-routing, x-routing, routing, x-rules, profile-rules
    for (final name in ['profile-routing', 'x-routing', 'routing', 'x-rules', 'profile-rules']) {
      final v = headers.value(name);
      if (v != null && v.isNotEmpty) {
        routing = _decodeHeaderValue(v);
        break;
      }
    }

    // Check for remote ruleset url headers: ruleset-url, profile-ruleset, x-ruleset-url, routing-url, x-routing-url
    for (final name in ['ruleset-url', 'profile-ruleset', 'x-ruleset-url', 'routing-url', 'x-routing-url']) {
      final v = headers.value(name);
      if (v != null && v.trim().isNotEmpty) {
        rulesetUrl = _decodeHeaderValue(v.trim());
        break;
      }
    }

    // subscription-userinfo: upload=N; download=N; total=N; expire=N
    final userInfo = headers.value('subscription-userinfo');
    if (userInfo != null) {
      for (final part in userInfo.split(';')) {
        final kv = part.trim().split('=');
        if (kv.length != 2) continue;
        final key = kv[0].trim();
        final val = int.tryParse(kv[1].trim());
        if (val == null) continue;
        switch (key) {
          case 'upload':
            uploadBytes = val;
          case 'download':
            downloadBytes = val;
          case 'total':
            if (val > 0) totalBytes = val;
          case 'expire':
            if (val > 0) expireAt = DateTime.fromMillisecondsSinceEpoch(val * 1000);
        }
      }
    }

    // announce: plain text or "base64:<encoded>"
    final rawAnnounce = headers.value('announce');
    if (rawAnnounce != null) {
      announce = _decodeHeaderValue(rawAnnounce);
    }

    // announce-url
    announceUrl = headers.value('announce-url');

    return _HeaderMeta(
      profileTitle: profileTitle,
      expireAt: expireAt,
      uploadBytes: uploadBytes,
      downloadBytes: downloadBytes,
      totalBytes: totalBytes,
      announce: announce,
      announceUrl: announceUrl,
      hwidStatus: hwidStatus,
      routing: routing,
      rulesetUrl: rulesetUrl,
    );
  }

  /// Decodes a header value that may be prefixed with "base64:".
  String _decodeHeaderValue(String value) {
    if (value.startsWith('base64:')) {
      try {
        final encoded = value.substring(7);
        final padded = encoded.padRight((encoded.length + 3) ~/ 4 * 4, '=');
        return utf8.decode(base64Decode(padded));
      } catch (_) {
        return value.substring(7);
      }
    }
    return value;
  }
}

class _HeaderMeta {
  final String? profileTitle;
  final DateTime? expireAt;
  final int? uploadBytes;
  final int? downloadBytes;
  final int? totalBytes;
  final String? announce;
  final String? announceUrl;
  final HwidStatus? hwidStatus;
  final String? routing;
  final String? rulesetUrl;

  const _HeaderMeta({
    this.profileTitle,
    this.expireAt,
    this.uploadBytes,
    this.downloadBytes,
    this.totalBytes,
    this.announce,
    this.announceUrl,
    this.hwidStatus,
    this.routing,
    this.rulesetUrl,
  });
}
