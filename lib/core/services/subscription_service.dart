import 'dart:convert';
import 'dart:io';
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
  Future<SubscriptionFetchResult> fetchSubscription(
    String url, {
    bool allowSelfSigned = false,
    HwidDeviceInfo? hwid,
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
      request.headers.set('User-Agent', AppConstants.subscriptionUserAgent);

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

    // Try base64 decode first.
    // Many providers wrap base64 output at 76 chars (RFC 2045), so strip all
    // whitespace before decoding — otherwise base64Decode throws and we fall
    // back to treating each 76-char chunk as a separate URI (→ 0 configs).
    try {
      final cleaned = body.replaceAll(RegExp(r'\s'), '');
      final padded = cleaned.padRight((cleaned.length + 3) ~/ 4 * 4, '=');
      final decoded = utf8.decode(base64Decode(padded));
      lines = decoded.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    } catch (_) {
      // Not base64 — treat as plain-text list of URIs.
      lines = body.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    }

    final configs = <VpnConfig>[];
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
      hwidStatus: meta.hwidStatus,
    );
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
