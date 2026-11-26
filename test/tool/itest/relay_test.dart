import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/itest/src/relay.dart';
import 'fake_shell.dart';

void main() {
  late ServerSocket server;

  setUp(() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((s) => s.listen(s.add, onDone: s.destroy));
  });
  tearDown(() => server.close());

  Future<String> echo(int port) async {
    final s = await Socket.connect(InternetAddress.loopbackIPv4, port);
    s.write('ping');
    final reply = await s.first.timeout(const Duration(seconds: 5));
    s.destroy();
    return utf8.decode(reply);
  }

  test('forwards to the server, down cuts it, up brings it back; adb reverse maps the port', () async {
    final shell = FakeShell();
    final relay = Relay(shell, '127.0.0.1', server.port);
    await relay.start();
    expect(shell.calls, ['reverse tcp:${relay.port} tcp:${relay.port}']);
    expect(await echo(relay.port), 'ping');

    final open = await Socket.connect(InternetAddress.loopbackIPv4, relay.port);
    final closed = Completer<void>();
    open.listen((_) {}, onDone: closed.complete, onError: (Object _) => closed.complete());
    open.write('x');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await relay.down();
    await closed.future.timeout(const Duration(seconds: 5));
    await expectLater(Socket.connect(InternetAddress.loopbackIPv4, relay.port), throwsA(isA<SocketException>()));

    final port = relay.port;
    await relay.up();
    expect(relay.port, port);
    expect(await echo(relay.port), 'ping');

    await relay.stop();
    expect(shell.calls.last, 'reverse --remove tcp:$port');
  });
}
