import 'dart:io';

/// Локальный HTTP(S)-сервер на 127.0.0.1 для тестов сетевого кода без моков.
/// В файлах с `TestWidgetsFlutterBinding` нужно `HttpOverrides.global = null`:
/// биндинг подменяет HttpClient заглушкой, отвечающей 400.
class LocalServer {
  final HttpServer _server;
  final bool _secure;

  Future<void> Function(HttpRequest req) handler = (r) async {
    r.response.statusCode = HttpStatus.notFound;
    await r.response.close();
  };

  /// Заголовки последних запросов, по порядку.
  final requests = <HttpHeaders>[];
  final paths = <String>[];

  LocalServer._(this._server, this._secure) {
    _server.listen((r) async {
      requests.add(r.headers);
      paths.add(r.uri.toString());
      await handler(r);
    });
  }

  static Future<LocalServer> start({SecurityContext? tls}) async {
    final server = tls == null
        ? await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
        : await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, tls);
    return LocalServer._(server, tls != null);
  }

  /// Контекст с самоподписанным сертификатом `localhost`/`127.0.0.1` из test/fixtures.
  static SecurityContext selfSignedContext() => SecurityContext()
    ..useCertificateChain('test/fixtures/localhost_cert.pem')
    ..usePrivateKey('test/fixtures/localhost_key.pem');

  int get port => _server.port;

  String url([String path = '/']) => '${_secure ? 'https' : 'http'}://127.0.0.1:$port$path';

  /// Каждый запрос получает [body] с [status] и [headers].
  void serve(Object body, {int status = 200, Map<String, String> headers = const {}}) {
    handler = (r) async {
      r.response.statusCode = status;
      headers.forEach(r.response.headers.set);
      if (body is List<int>) {
        r.response.add(body);
      } else {
        r.response.write(body);
      }
      await r.response.close();
    };
  }

  Future<void> close() => _server.close(force: true);
}

/// Перенаправляет все запросы `HttpClient.getUrl` (например, к api.github.com)
/// на локальный сервер: `HttpOverrides.runWithHttpOverrides(body, RedirectHttpOverrides(port))`.
class RedirectHttpOverrides extends HttpOverrides {
  final int port;
  RedirectHttpOverrides(this.port);

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _RedirectClient(super.createHttpClient(context), port);
}

class _RedirectClient implements HttpClient {
  final HttpClient inner;
  final int port;
  _RedirectClient(this.inner, this.port);

  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      inner.getUrl(url.replace(scheme: 'http', host: '127.0.0.1', port: port));

  @override
  void close({bool force = false}) => inner.close(force: force);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
