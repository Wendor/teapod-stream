import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  test('a peer reset while the relay writes is no uncaught error', () async {
    // A server that reads a little and then drops the connection while the client keeps sending.
    final dropper = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(dropper.close);
    dropper.listen((s) {
      // SO_LINGER {on, 0 s}: destroy() sends RST, so the relay's next write to this side fails.
      s.setRawOption(
        RawSocketOption(
          Platform.isMacOS ? 0xffff : 1,
          Platform.isMacOS ? 0x80 : 13,
          Uint8List.fromList([1, 0, 0, 0, 0, 0, 0, 0]),
        ),
      );
      s.listen((_) => s.destroy(), onError: (Object _) {}, cancelOnError: true);
    });
    final errors = <Object>[];
    await runZonedGuarded(() async {
      final relay = Relay(FakeShell(), '127.0.0.1', dropper.port);
      await relay.start();
      final c = await Socket.connect(InternetAddress.loopbackIPv4, relay.port);
      c.done.ignore();
      c.listen((_) {}, onError: (Object _) {}, cancelOnError: true);
      final chunk = List<int>.filled(64 * 1024, 7);
      for (var i = 0; i < 200; i++) {
        c.add(chunk);
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      c.destroy();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await relay.stop();
    }, (e, _) => errors.add(e));
    expect(errors, isEmpty);
  });
}
