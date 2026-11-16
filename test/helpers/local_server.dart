import 'dart:io';

/// Local HTTP(S) server on 127.0.0.1 for testing network code without mocks.
/// Files with `TestWidgetsFlutterBinding` need `HttpOverrides.global = null`:
/// the binding replaces HttpClient with a stub that answers 400.
class LocalServer {
  final HttpServer _server;
  final bool _secure;

  Future<void> Function(HttpRequest req) handler = (r) async {
    r.response.statusCode = HttpStatus.notFound;
    await r.response.close();
  };

  /// Headers of the latest requests, in order.
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

  /// Context with the self-signed `localhost`/`127.0.0.1` certificate from test/fixtures.
  static SecurityContext selfSignedContext() => SecurityContext()
    ..useCertificateChain('test/fixtures/localhost_cert.pem')
    ..usePrivateKey('test/fixtures/localhost_key.pem');

  int get port => _server.port;

  String url([String path = '/']) => '${_secure ? 'https' : 'http'}://127.0.0.1:$port$path';

  /// Each request gets [body] with [status] and [headers].
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

/// Redirects all `HttpClient.getUrl` requests (e.g. to api.github.com)
/// to the local server: `HttpOverrides.runWithHttpOverrides(body, RedirectHttpOverrides(port))`.
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
