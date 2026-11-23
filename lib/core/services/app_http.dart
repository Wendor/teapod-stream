import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'tunnel_socks.dart';

/// A refused request or response: a non-https URL where https is required, a body over the limit.
/// Not a transport error, so [TunnelSocks.orDirect] doesn't retry it directly.
class AppHttpException implements Exception {
  final String message;
  const AppHttpException(this.message);

  @override
  String toString() => message;
}

/// A response whose body is still to be read. [body] applies the idle timeout and the size limit;
/// [close] releases the connection (always, in `finally`).
class AppHttpStream {
  final HttpClientResponse _response;
  final HttpClient _client;
  final Stream<List<int>> body;

  AppHttpStream._(this._response, this._client, this.body);

  int get statusCode => _response.statusCode;
  HttpHeaders get headers => _response.headers;

  /// With force: a connection with an unread body (error status, timeout) would otherwise stay open.
  void close() => _client.close(force: true);
}

/// A response read completely. [bytes] is empty unless the status is 2xx: the body of an error is not read
/// (it may never end).
class AppHttpResponse {
  final int statusCode;
  final HttpHeaders headers;
  final Uint8List bytes;

  const AppHttpResponse(this.statusCode, this.headers, this.bytes);

  String get body => utf8.decode(bytes, allowMalformed: true);
}

/// The app's own HTTP requests (subscriptions, geodata, updates, IP lookup, profile and bundle downloads).
/// The app is excluded from the VPN, so each request takes the tunnel's [TunnelSocks] when it is up.
/// One policy: a timeout for the connection and the response headers, an idle timeout while reading the body,
/// a body size limit, https only where asked (redirects included).
class AppHttp {
  static const timeout = Duration(seconds: 15);
  static const maxBytes = 10 * 1024 * 1024;
  static const _maxRedirects = 5;

  /// A client through [socks] (direct when null). Certificate checks go to [onBadCertificate] on both paths.
  static HttpClient client({
    TunnelSocks? socks,
    bool Function(X509Certificate cert, String host, int port)? onBadCertificate,
  }) {
    final client = HttpClient()..connectionTimeout = timeout;
    if (onBadCertificate != null) client.badCertificateCallback = onBadCertificate;
    socks?.apply(client, onBadCertificate: onBadCertificate);
    return client;
  }

  /// Sends [method] to [url] and returns the response with its body unread. Redirects are followed here, so
  /// [httpsOnly] holds for every hop. The caller closes the result.
  static Future<AppHttpStream> open(
    Uri url, {
    String method = 'GET',
    TunnelSocks? socks,
    Map<String, String> headers = const {},
    bool httpsOnly = false,
    int maxBytes = maxBytes,
    Duration timeout = timeout,
    Duration idleTimeout = timeout,
    bool Function(X509Certificate cert, String host, int port)? onBadCertificate,
  }) async {
    final client = AppHttp.client(socks: socks, onBadCertificate: onBadCertificate);
    try {
      var uri = url;
      for (var hop = 0; ; hop++) {
        if (httpsOnly && uri.scheme != 'https') throw AppHttpException('Only https is allowed: ${uri.scheme}');
        final request = await client.openUrl(method, uri).timeout(timeout);
        request.followRedirects = false;
        headers.forEach(request.headers.set);
        final response = await request.close().timeout(timeout);
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (response.isRedirect && location != null && hop < _maxRedirects) {
          response.listen(null).cancel().ignore();
          uri = uri.resolve(location);
          continue;
        }
        if (response.contentLength > maxBytes) throw AppHttpException('Response exceeds ${_mb(maxBytes)}');
        return AppHttpStream._(response, client, _limited(response, maxBytes, idleTimeout));
      }
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }

  /// GET [url] and read the body (2xx only) within the limits of [open].
  static Future<AppHttpResponse> get(
    Uri url, {
    TunnelSocks? socks,
    Map<String, String> headers = const {},
    bool httpsOnly = false,
    int maxBytes = maxBytes,
    bool Function(X509Certificate cert, String host, int port)? onBadCertificate,
  }) async {
    final response = await open(
      url,
      socks: socks,
      headers: headers,
      httpsOnly: httpsOnly,
      maxBytes: maxBytes,
      onBadCertificate: onBadCertificate,
    );
    try {
      final bytes = BytesBuilder(copy: false);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await for (final chunk in response.body) {
          bytes.add(chunk);
        }
      }
      return AppHttpResponse(response.statusCode, response.headers, bytes.takeBytes());
    } finally {
      response.close();
    }
  }

  static Stream<List<int>> _limited(Stream<List<int>> body, int maxBytes, Duration idleTimeout) async* {
    var total = 0;
    await for (final chunk in body.timeout(idleTimeout)) {
      total += chunk.length;
      if (total > maxBytes) throw AppHttpException('Response exceeds ${_mb(maxBytes)}');
      yield chunk;
    }
  }

  static String _mb(int bytes) => bytes % (1024 * 1024) == 0 ? '${bytes ~/ (1024 * 1024)} MB' : '$bytes bytes';
}
