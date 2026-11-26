import 'dart:async';
import 'dart:io';

import 'adb.dart';

/// A TCP relay on the computer to a real server, reached from the phone through `adb reverse`:
/// the phone's copy of the config dials `127.0.0.1:[port]`. [down] makes the server dead
/// (new connections are refused, open ones are cut), [up] brings it back.
class Relay {
  final Shell shell;
  final String host;
  final int serverPort;
  int port = 0;
  ServerSocket? _server;
  final _open = <Socket>{};

  Relay(this.shell, this.host, this.serverPort);

  bool get isUp => _server != null;

  /// Binds the listener (the first call picks the port) and maps the same port on the phone.
  Future<void> start() async {
    await up();
    final r = await shell.run(['reverse', 'tcp:$port', 'tcp:$port']);
    if (!r.ok) throw StateError('adb reverse: ${r.out}');
  }

  Future<void> up() async {
    if (_server != null) return;
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    port = s.port;
    _server = s;
    s.listen(_accept);
  }

  Future<void> down() async {
    final s = _server;
    _server = null;
    await s?.close();
    for (final c in _open.toList()) {
      c.destroy();
    }
    _open.clear();
  }

  Future<void> stop() async {
    await down();
    if (port != 0) await shell.run(['reverse', '--remove', 'tcp:$port']);
  }

  Future<void> _accept(Socket a) async {
    // A write to a socket the peer reset fails its `done`; the read side's onError closes the pair.
    a.done.ignore();
    final Socket b;
    try {
      b = await Socket.connect(host, serverPort, timeout: const Duration(seconds: 10));
    } catch (_) {
      a.destroy();
      return;
    }
    b.done.ignore();
    if (_server == null) {
      a.destroy();
      b.destroy();
      return;
    }
    _open
      ..add(a)
      ..add(b);
    void close() {
      _open
        ..remove(a)
        ..remove(b);
      a.destroy();
      b.destroy();
    }

    a.listen(b.add, onDone: close, onError: (Object _) => close(), cancelOnError: true);
    b.listen(a.add, onDone: close, onError: (Object _) => close(), cancelOnError: true);
  }
}
