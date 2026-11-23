import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/services/app_http.dart';
import 'package:teapodstream/core/services/tunnel_socks.dart';

import '../helpers/local_server.dart';

void main() {
  late LocalServer server;

  setUp(() async => server = await LocalServer.start());
  tearDown(() => server.close());

  test('GET reads the body and sends the headers', () async {
    server.serve('hello', headers: {'x-a': 'b'});
    final r = await AppHttp.get(Uri.parse(server.url('/p')), headers: {'User-Agent': 'T'});
    expect((r.statusCode, r.body, r.headers.value('x-a')), (200, 'hello', 'b'));
    expect(server.requests.single.value('user-agent'), 'T');
  });

  test('the body of an error status is not read', () async {
    server.serve('error page', status: 500);
    final r = await AppHttp.get(Uri.parse(server.url()));
    expect(r.statusCode, 500);
    expect(r.bytes, isEmpty);
  });

  test('redirects are followed with the same headers', () async {
    server.handler = (r) async {
      if (r.uri.path == '/a') {
        r.response.statusCode = HttpStatus.found;
        r.response.headers.set('location', '/b');
      } else {
        r.response.write('b');
      }
      await r.response.close();
    };
    final r = await AppHttp.get(Uri.parse(server.url('/a')), headers: {'Range': 'bytes=1-'});
    expect(r.body, 'b');
    expect(server.paths, ['/a', '/b']);
    expect(server.requests.last.value('range'), 'bytes=1-');
  });

  group('size limit', () {
    test('a declared length over the limit is refused before the body', () async {
      final release = Completer<void>();
      addTearDown(release.complete);
      server.handler = (r) async {
        r.response.contentLength = 2000;
        r.response.write('x');
        await r.response.flush();
        await release.future;
      };
      await expectLater(
        AppHttp.get(Uri.parse(server.url()), maxBytes: 1000),
        throwsA(isA<AppHttpException>().having((e) => e.message, 'message', contains('1000 bytes'))),
      );
    });

    test('a chunked body is cut at the limit', () async {
      server.handler = (r) async {
        for (var i = 0; i < 4; i++) {
          r.response.write('x' * 500);
          await r.response.flush();
        }
        await r.response.close();
      };
      await expectLater(AppHttp.get(Uri.parse(server.url()), maxBytes: 1000), throwsA(isA<AppHttpException>()));
    });

    test('is not a transport error: no direct retry', () {
      expect(TunnelSocks.isTransportError(const AppHttpException('x')), isFalse);
    });
  });

  test('a stalled body ends with a timeout', () async {
    final release = Completer<void>();
    addTearDown(release.complete);
    server.handler = (r) async {
      r.response.write('start');
      await r.response.flush();
      await release.future;
      await r.response.close();
    };
    final r = await AppHttp.open(Uri.parse(server.url()), idleTimeout: const Duration(milliseconds: 200));
    try {
      await expectLater(r.body.drain<void>(), throwsA(isA<TimeoutException>()));
    } finally {
      r.close();
    }
  });

  group('certificates', () {
    late LocalServer tls;
    setUp(() async => tls = await LocalServer.start(tls: LocalServer.selfSignedContext()));
    tearDown(() => tls.close());

    test('a rejected certificate is not a transport error', () async {
      tls.serve('secure');
      Object? error;
      try {
        await AppHttp.get(Uri.parse(tls.url()), onBadCertificate: (_, _, _) => false);
      } catch (e) {
        error = e;
      }
      expect(error, isA<AppHttpException>());
      expect(TunnelSocks.isTransportError(error!), isFalse);
      expect(tls.paths, isEmpty);
    });

    test('without a callback the default rejection is the same', () async {
      await expectLater(AppHttp.get(Uri.parse(tls.url())), throwsA(isA<AppHttpException>()));
    });

    test('a refused connection stays a transport error', () async {
      final port = tls.port;
      await tls.close();
      Object? error;
      try {
        await AppHttp.get(Uri.parse('https://127.0.0.1:$port/'));
      } catch (e) {
        error = e;
      }
      expect(TunnelSocks.isTransportError(error!), isTrue);
    });
  });

  test('closing a shared client ends the requests still running on it', () async {
    server.handler = (r) async {
      r.response.write('start');
      await r.response.flush();
      await Future<void>.delayed(const Duration(seconds: 10));
      await r.response.close();
    };
    final client = AppHttp.client();
    final pending = AppHttp.get(Uri.parse(server.url()), client: client);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    client.close(force: true);
    await expectLater(pending.timeout(const Duration(seconds: 2)), throwsA(isNot(isA<TimeoutException>())));
  });

  group('https only', () {
    test('plain http is refused without a request', () async {
      await expectLater(AppHttp.get(Uri.parse(server.url()), httpsOnly: true), throwsA(isA<AppHttpException>()));
      expect(server.paths, isEmpty);
    });

    test('https passes, a redirect to http is refused', () async {
      final tls = await LocalServer.start(tls: LocalServer.selfSignedContext());
      addTearDown(tls.close);
      tls.handler = (r) async {
        if (r.uri.path == '/ok') {
          r.response.write('secure');
        } else {
          r.response.statusCode = HttpStatus.movedPermanently;
          r.response.headers.set('location', server.url('/plain'));
        }
        await r.response.close();
      };
      bool trust(X509Certificate cert, String host, int port) => true;
      final ok = await AppHttp.get(Uri.parse(tls.url('/ok')), httpsOnly: true, onBadCertificate: trust);
      expect(ok.body, 'secure');
      await expectLater(
        AppHttp.get(Uri.parse(tls.url('/go')), httpsOnly: true, onBadCertificate: trust),
        throwsA(isA<AppHttpException>()),
      );
      expect(server.paths, isEmpty);
    });
  });
}
