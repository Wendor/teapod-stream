import 'dart:io';
import 'package:socks5_proxy/socks.dart';

/// Локальный SOCKS-инбаунд активного туннеля. Само приложение исключено из TUN,
/// поэтому без него собственные загрузки (подписки, гео-базы) идут мимо VPN (#150).
class TunnelSocks {
  final int port;
  final String user;
  final String password;

  const TunnelSocks(this.port, this.user, this.password);

  /// Направить [client] через туннель. TLS поверх SOCKS поднимает фабрика соединений —
  /// `badCertificateCallback` клиента туда не доходит, проверку передают в [onBadCertificate].
  void apply(HttpClient client, {bool Function(X509Certificate cert)? onBadCertificate}) =>
      SocksTCPClient.assignToHttpClientWithSecureOptions(
        client,
        [
          ProxySettings(
            InternetAddress.loopbackIPv4,
            port,
            username: user.isNotEmpty ? user : null,
            password: user.isNotEmpty ? password : null,
          ),
        ],
        onBadCertificate: onBadCertificate,
      );

  /// Через туннель, при сбое — напрямую: обновлять подписку часто приходится как раз
  /// при мёртвом туннеле. Ошибки, для которых [keep] true, напрямую не повторяются.
  static Future<T> orDirect<T>(
    TunnelSocks? socks,
    Future<T> Function(TunnelSocks? socks) run, {
    bool Function(Object error)? keep,
  }) async {
    if (socks == null) return run(null);
    try {
      return await run(socks);
    } catch (e) {
      if (keep?.call(e) ?? false) rethrow;
      return run(null);
    }
  }
}
