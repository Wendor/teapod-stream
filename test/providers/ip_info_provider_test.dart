import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teapodstream/core/constants/app_constants.dart';
import 'package:teapodstream/providers/ip_info_provider.dart';

/// Минимальный SOCKS5 (user/pass) сервер: после CONNECT сам отвечает на HTTP-запрос.
class _Socks5 {
  final ServerSocket _server;
  final String httpBody;
  final auth = <(String, String)>[];
  final targets = <String>[];

  _Socks5._(this._server, this.httpBody) {
    _server.listen(_handle);
  }

  static Future<_Socks5> start(String httpBody) async =>
      _Socks5._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0), httpBody);

  int get port => _server.port;

  Future<void> close() => _server.close();

  Future<void> _handle(Socket s) async {
    final buf = <int>[];
    final waiters = <(int, Completer<List<int>>)>[];
    void pump() {
      while (waiters.isNotEmpty && buf.length >= waiters.first.$1) {
        final (n, c) = waiters.removeAt(0);
        c.complete(buf.sublist(0, n));
        buf.removeRange(0, n);
      }
    }

    s.listen((d) {
      buf.addAll(d);
      pump();
    }, onError: (_) {});
    Future<List<int>> take(int n) {
      final c = Completer<List<int>>();
      waiters.add((n, c));
      pump();
      return c.future;
    }

    final greet = await take(2);
    await take(greet[1]);
    s.add([5, 2]);
    await take(1);
    final user = utf8.decode(await take((await take(1))[0]));
    final pass = utf8.decode(await take((await take(1))[0]));
    auth.add((user, pass));
    s.add([1, 0]);
    final req = await take(4);
    final host = switch (req[3]) {
      1 => (await take(4)).join('.'),
      3 => utf8.decode(await take((await take(1))[0])),
      _ => '?',
    };
    final port = await take(2);
    targets.add('$host:${port[0] << 8 | port[1]}');
    s.add([5, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
    // Ждём конец HTTP-заголовков и отвечаем.
    while (!latin1.decode(buf).contains('\r\n\r\n')) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    s.add(utf8.encode('HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n'
        'Content-Length: ${utf8.encode(httpBody).length}\r\nConnection: close\r\n\r\n$httpBody'));
    await s.flush();
    await s.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Map<String, Object?> nativeState;
  late ProviderContainer c;

  setUp(() {
    // Биндинг подменяет HttpClient заглушкой (400) — нужен настоящий.
    HttpOverrides.global = null;
    nativeState = {'state': 'disconnected'};
    messenger.setMockMethodCallHandler(const MethodChannel(AppConstants.methodChannel),
        (call) async => call.method == 'getState' ? nativeState : null);
    messenger.setMockStreamHandler(const EventChannel('${AppConstants.methodChannel}/events'),
        MockStreamHandler.inline(onListen: (_, _) {}));
    SharedPreferences.setMockInitialValues({'storage_migrated_v2': true});
    FlutterSecureStorage.setMockInitialValues({});
    c = ProviderContainer();
    addTearDown(c.dispose);
  });

  Future<IpInfo?> read() => c.read(ipInfoProvider.future);

  test('disconnected VPN gives null without a request', () async {
    expect(await read(), isNull);
  });

  test('connected VPN asks ip-api.com through the authenticated SOCKS proxy', () async {
    final socks = await _Socks5.start(
        jsonEncode({'status': 'success', 'query': '203.0.113.7', 'country': 'Netherlands', 'countryCode': 'NL'}));
    addTearDown(socks.close);
    nativeState = {'state': 'connected', 'socksPort': socks.port, 'socksUser': 'su', 'socksPassword': 'sp'};
    final info = await read();
    expect((info?.ip, info?.country, info?.countryCode), ('203.0.113.7', 'Netherlands', 'NL'));
    expect(socks.auth.single, ('su', 'sp'));
    expect(socks.targets.single, endsWith(':80'));
  });

  test('failed lookup gives null', () async {
    final socks = await _Socks5.start(jsonEncode({'status': 'fail'}));
    addTearDown(socks.close);
    nativeState = {'state': 'connected', 'socksPort': socks.port, 'socksUser': 'su', 'socksPassword': 'sp'};
    expect(await read(), isNull);
  });

  test('dead proxy gives null', () async {
    final socks = await _Socks5.start('');
    final port = socks.port;
    await socks.close();
    nativeState = {'state': 'connected', 'socksPort': port, 'socksUser': 'su', 'socksPassword': 'sp'};
    expect(await read(), isNull);
  });
}
