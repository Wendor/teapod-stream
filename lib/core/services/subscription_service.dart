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

class SubscriptionService {
  /// Fetch and parse a subscription URL.
  ///
  /// If [allowSelfSigned] is false (default) and the server presents an
  /// untrusted certificate, throws [UntrustedCertificateException] with
  /// certificate details so the caller can decide whether to retry.
  /// If [allowSelfSigned] is true, certificate validation is skipped.
  Future<List<VpnConfig>> fetchSubscription(
    String url, {
    bool allowSelfSigned = false,
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
    try {
      final request = await httpClient.getUrl(uri);
      request.headers.set('User-Agent', AppConstants.subscriptionUserAgent);
      final response =
          await request.close().timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch subscription: ${response.statusCode}');
      }

      body = await response.transform(utf8.decoder).join();
    } on HandshakeException {
      if (certError != null) throw certError!;
      rethrow;
    } finally {
      httpClient.close();
    }

    body = body.trim();
    List<String> lines;

    // Try base64 decode first
    try {
      final padded = body.padRight((body.length + 3) ~/ 4 * 4, '=');
      final decoded = utf8.decode(base64Decode(padded));
      lines = decoded.split('\n').where((l) => l.trim().isNotEmpty).toList();
    } catch (_) {
      lines = body.split('\n').where((l) => l.trim().isNotEmpty).toList();
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
    return configs;
  }
}
