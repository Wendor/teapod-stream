import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../constants/app_constants.dart';
import '../models/vpn_config.dart';
import '../../protocols/xray/vless_parser.dart';

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

  /// DER (base64) принятого недоверенного сертификата: сохраняется в подписке как пин.
  final String? acceptedCertDer;

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
    this.acceptedCertDer,
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
  static const _maxBodyBytes = 10 * 1024 * 1024;

  /// Fetch and parse a subscription URL.
  ///
  /// If [allowSelfSigned] is false (default) and the server presents an
  /// untrusted certificate, throws [UntrustedCertificateException] with
  /// certificate details so the caller can decide whether to retry.
  /// If [allowSelfSigned] is true, certificate validation is skipped.
  /// [pinnedCertDer] — ранее принятый сертификат: только он проходит без проверки.
  /// If [hwidEnabled] is true, HWID headers are sent to support device limits.
  /// If [userAgent] is non-empty, it overrides the default User-Agent.
  Future<SubscriptionFetchResult> fetchSubscription(
    String url, {
    bool allowSelfSigned = false,
    String? pinnedCertDer,
    HwidDeviceInfo? hwid,
    String? userAgent,
  }) async {
    final uri = Uri.parse(url);
    final httpClient = HttpClient()..connectionTimeout = const Duration(seconds: 15);

    UntrustedCertificateException? certError;
    String? acceptedCert;

    httpClient.badCertificateCallback =
        (X509Certificate cert, String host, int port) {
      final der = base64.encode(cert.der);
      if (allowSelfSigned || der == pinnedCertDer) {
        acceptedCert = der;
        return true;
      }
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
      // Тайм-аут простоя и лимит размера: медленный или огромный ответ не должен
      // висеть вечно или съесть память.
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        bytes.add(chunk);
        if (bytes.length > _maxBodyBytes) throw Exception('Subscription body exceeds 10 MB');
      }
      body = utf8.decode(bytes.takeBytes());
    } on HandshakeException {
      if (certError != null) throw certError!;
      rethrow;
    } finally {
      // Без force соединение с непрочитанным телом (не-200, таймаут) живёт вечно.
      httpClient.close(force: true);
    }

    final meta = _parseHeaders(responseHeaders);

    body = body.trim();
    List<String> lines;
    final configs = <VpnConfig>[];

    // Detect pre-built xray JSON config array (managed subscription format).
    if (body.startsWith('[') || body.startsWith('{')) {
      try {
        final jsonData = jsonDecode(body);
        final items = jsonData is List ? jsonData : [jsonData];
        for (final item in items) {
          if (item is! Map<String, dynamic>) continue;
          final rawRemarks = item['remarks'] as String? ?? 'Server';
          final remarks = rawRemarks.replaceFirst(RegExp(r'^[\s\-\—\–]+'), '');
          final rawJson = jsonEncode(item);
          String address = '';
          int port = 0;
          final outbounds = item['outbounds'] as List<dynamic>? ?? [];
          for (final outbound in outbounds) {
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
          configs.add(VpnConfig(
            id: 'xray_${DateTime.now().millisecondsSinceEpoch}_${configs.length}',
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
        if (configs.isNotEmpty) {
          return SubscriptionFetchResult(
            configs: configs,
            profileTitle: meta.profileTitle,
            expireAt: meta.expireAt,
            uploadBytes: meta.uploadBytes,
            downloadBytes: meta.downloadBytes,
            totalBytes: meta.totalBytes,
            announce: meta.announce,
            announceUrl: meta.announceUrl,
            acceptedCertDer: acceptedCert,
            hwidStatus: meta.hwidStatus,
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
        final decodedLines = _splitLines(decoded);
        if (decodedLines.any(_isKnownUri)) lines = decodedLines;
      } catch (_) {
        // Not base64 either — keep the raw lines, the parser will skip them.
      }
    }

    for (final line in lines) {
      final trimmed = line.trim();
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
      acceptedCertDer: acceptedCert,
      hwidStatus: meta.hwidStatus,
    );
  }

  static List<String> _splitLines(String s) =>
      s.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();

  static const _uriSchemes = [
    'vless://', 'vmess://', 'trojan://', 'ss://', 'hy2://', 'hysteria2://',
    'wireguard://', 'wg://', 'ssh://', 'naive+https://', 'naive+quic://', 'vpn://',
  ];

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

  const _HeaderMeta({
    this.profileTitle,
    this.expireAt,
    this.uploadBytes,
    this.downloadBytes,
    this.totalBytes,
    this.announce,
    this.announceUrl,
    this.hwidStatus,
  });
}
