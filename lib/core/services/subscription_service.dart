import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../constants/app_constants.dart';
import '../models/vpn_config.dart';
import 'app_http.dart';
import 'tunnel_socks.dart';
import '../../protocols/xray/vless_parser.dart';

/// Thrown when the subscription server presents an untrusted TLS certificate. [der] (base64) is the certificate
/// that was presented: once the user accepts it, the retry pins exactly this one (`pinnedCertDer`).
class UntrustedCertificateException implements Exception {
  final String host;
  final String subject;
  final String issuer;
  final String der;

  const UntrustedCertificateException({
    required this.host,
    required this.subject,
    required this.issuer,
    required this.der,
  });

  /// SHA-256 of the certificate, `AB:CD:…`: what the user compares with the server's.
  String get sha256Fingerprint =>
      sha256(base64.decode(der)).map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');

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

  /// DER (base64) of the pinned certificate the server presented: stored in the subscription as its pin.
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

  const HwidStatus({required this.isActive, required this.notSupported, required this.maxDevicesReached});
}

class HwidDeviceInfo {
  final String deviceId;
  final String deviceModel;
  final int osVersion;

  const HwidDeviceInfo({required this.deviceId, required this.deviceModel, required this.osVersion});

  Map<String, dynamic> toJson() => {'deviceId': deviceId, 'deviceModel': deviceModel, 'osVersion': osVersion};
}

class SubscriptionService {
  /// Fetch and parse a subscription URL.
  ///
  /// An untrusted certificate throws [UntrustedCertificateException] with its details so the caller can ask the
  /// user — only for the host of [url]; an untrusted certificate after a redirect to another host is a plain error.
  /// [pinnedCertDer] — the certificate the user accepted (base64 DER): only it, and only from the host of [url],
  /// passes without verification.
  /// If [hwidEnabled] is true, HWID headers are sent to support device limits.
  /// If [userAgent] is non-empty, it overrides the default User-Agent.
  Future<SubscriptionFetchResult> fetchSubscription(
    String url, {
    String? pinnedCertDer,
    HwidDeviceInfo? hwid,
    String? userAgent,
    TunnelSocks? socks,
  }) => TunnelSocks.orDirect(
    socks,
    (s) => _fetch(url, pinnedCertDer: pinnedCertDer, hwid: hwid, userAgent: userAgent, socks: s),
  );

  Future<SubscriptionFetchResult> _fetch(
    String url, {
    required String? pinnedCertDer,
    required HwidDeviceInfo? hwid,
    required String? userAgent,
    required TunnelSocks? socks,
  }) async {
    final uri = Uri.parse(url);
    UntrustedCertificateException? certError;
    String? acceptedCert;

    bool onBadCertificate(X509Certificate cert, String host, int port) {
      // A redirect to another host is never trusted and never offered to the user: accepting it couldn't be
      // retried, since the pin belongs to the subscription host only.
      if (host != uri.host) return false;
      final der = base64.encode(cert.der);
      if (pinnedCertDer != null && der == pinnedCertDer) {
        acceptedCert = der;
        return true;
      }
      certError = UntrustedCertificateException(host: host, subject: cert.subject, issuer: cert.issuer, der: der);
      return false;
    }

    final ua = userAgent?.trim() ?? '';
    final AppHttpResponse response;
    try {
      response = await AppHttp.get(
        uri,
        socks: socks,
        onBadCertificate: onBadCertificate,
        headers: {
          'User-Agent': ua.isNotEmpty ? ua : AppConstants.subscriptionUserAgent,
          if (hwid != null) ...{
            'X-Hwid': hwid.deviceId,
            'X-Device-Os': 'Android',
            'X-Device-Model': hwid.deviceModel,
            'X-Ver-Os': hwid.osVersion.toString(),
          },
        },
      );
    } on AppHttpException {
      if (certError != null) throw certError!;
      rethrow;
    }
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch subscription: ${response.statusCode}');
    }
    final responseHeaders = response.headers;
    var body = response.body;

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
          configs.add(
            VpnConfig(
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
            ),
          );
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
        final decoded = utf8.decode(base64Decode(padded), allowMalformed: true);
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

  static List<String> _splitLines(String s) => s.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();

  static const _uriSchemes = [
    'vless://',
    'vmess://',
    'trojan://',
    'ss://',
    'hy2://',
    'hysteria2://',
    'wireguard://',
    'wg://',
    'ssh://',
    'naive+https://',
    'naive+quic://',
    'vpn://',
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

/// SHA-256 (FIPS 180-4) of [data]: the certificate fingerprint shown to the user. No hashing package is a dependency.
Uint8List sha256(List<int> data) {
  const k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, //
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];
  final h = <int>[0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
  int rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;

  final padLen = (data.length + 9 + 63) ~/ 64 * 64;
  final msg = Uint8List(padLen)
    ..setAll(0, data)
    ..[data.length] = 0x80;
  ByteData.sublistView(msg).setUint64(padLen - 8, data.length * 8);
  final view = ByteData.sublistView(msg);
  final w = List<int>.filled(64, 0);
  for (var off = 0; off < padLen; off += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] = view.getUint32(off + i * 4);
    }
    for (var i = 16; i < 64; i++) {
      final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }
    var [a, b, c, d, e, f, g, hh] = h;
    for (var i = 0; i < 64; i++) {
      final t1 = (hh + (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) + ((e & f) ^ (~e & g)) + k[i] + w[i]) & 0xffffffff;
      final t2 = ((rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c))) & 0xffffffff;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
    }
    final v = [a, b, c, d, e, f, g, hh];
    for (var i = 0; i < 8; i++) {
      h[i] = (h[i] + v[i]) & 0xffffffff;
    }
  }
  final out = ByteData(32);
  for (var i = 0; i < 8; i++) {
    out.setUint32(i * 4, h[i]);
  }
  return out.buffer.asUint8List();
}
