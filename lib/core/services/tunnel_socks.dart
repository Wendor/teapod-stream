import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:socks5_proxy/exceptions.dart';
import 'package:socks5_proxy/socks.dart';

/// Локальный SOCKS-инбаунд активного туннеля. Само приложение исключено из TUN,
/// поэтому без него собственные загрузки (подписки, гео-базы) идут мимо VPN (#150).
class TunnelSocks {
  final int port;
  final String user;
  final String password;

  const TunnelSocks(this.port, this.user, this.password);

  /// Учётные данные SOCKS: при пустом [user] — без авторизации.
  ProxySettings get proxySettings => ProxySettings(
        InternetAddress.loopbackIPv4,
        port,
        username: user.isNotEmpty ? user : null,
        password: user.isNotEmpty ? password : null,
      );

  /// Направить [client] через туннель. TLS поверх SOCKS поднимает фабрика соединений —
  /// `badCertificateCallback` клиента туда не доходит, проверку передают в
  /// [onBadCertificate] с хостом фактического соединения (после редиректа — новым).
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

  /// Сбой связи (туннель мёртв), а не ответ сервера: только его есть смысл повторять напрямую.
  static bool isTransportError(Object e) =>
      e is SocketException ||
      e is TimeoutException ||
      e is TlsException ||
      e is HttpException ||
      e is http.ClientException ||
      e is SocksClientException ||
      e is ByteReaderException;

  /// Через туннель, при сбое связи — напрямую: обновлять подписку часто приходится как раз
  /// при мёртвом туннеле. Ответ сервера (HTTP-ошибка, сертификат) напрямую не повторяется —
  /// туннель работает, а запрос ушёл бы мимо VPN.
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
