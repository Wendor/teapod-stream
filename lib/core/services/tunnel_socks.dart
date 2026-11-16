import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:socks5_proxy/exceptions.dart';
import 'package:socks5_proxy/socks.dart';

/// Local SOCKS inbound of the active tunnel. The app itself is excluded from TUN,
/// so without it the app's own downloads (subscriptions, geo databases) bypass the VPN (#150).
class TunnelSocks {
  final int port;
  final String user;
  final String password;

  const TunnelSocks(this.port, this.user, this.password);

  /// SOCKS credentials: with an empty [user] — no authentication.
  ProxySettings get proxySettings => ProxySettings(
        InternetAddress.loopbackIPv4,
        port,
        username: user.isNotEmpty ? user : null,
        password: user.isNotEmpty ? password : null,
      );

  /// Route [client] through the tunnel. TLS over SOCKS is set up by the connection factory —
  /// the client's `badCertificateCallback` doesn't reach it, verification is passed to
  /// [onBadCertificate] with the host of the actual connection (after a redirect — the new one).
  void apply(HttpClient client,
      {bool Function(X509Certificate cert, String host, int port)? onBadCertificate}) {
    final proxies = [proxySettings];
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      final socket = SocksTCPClient.connect(
          proxies, InternetAddress(uri.host, type: InternetAddressType.unix), uri.port);
      if (uri.scheme != 'https') {
        return ConnectionTask.fromSocket(socket, () async => (await socket).close().ignore());
      }
      final secure = (await socket).secure(uri.host,
          onBadCertificate: onBadCertificate == null
              ? null
              : (cert) => onBadCertificate(cert, uri.host, uri.port));
      return ConnectionTask.fromSocket(secure, () async => (await secure).close().ignore());
    };
  }

  /// A connectivity failure (tunnel dead), not a server response: only that is worth retrying directly.
  static bool isTransportError(Object e) =>
      e is SocketException ||
      e is TimeoutException ||
      e is TlsException ||
      e is HttpException ||
      e is http.ClientException ||
      e is SocksClientException ||
      e is ByteReaderException;

  /// Through the tunnel, on a connectivity failure — directly: a subscription often has to be refreshed
  /// exactly when the tunnel is dead. A server response (HTTP error, certificate) isn't retried directly —
  /// the tunnel works, and the request would bypass the VPN.
  static Future<T> orDirect<T>(TunnelSocks? socks, Future<T> Function(TunnelSocks? socks) run) async {
    if (socks == null) return run(null);
    try {
      return await run(socks);
    } catch (e) {
      if (!isTransportError(e)) rethrow;
      return run(null);
    }
  }
}
