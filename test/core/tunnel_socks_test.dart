import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/services/tunnel_socks.dart';

void main() {
  const socks = TunnelSocks(1080, 'u', 'p');

  test('proxySettings: port and credentials; empty user — no auth', () {
    final p = socks.proxySettings;
    expect((p.host, p.port, p.username, p.password), (InternetAddress.loopbackIPv4, 1080, 'u', 'p'));
    final anon = const TunnelSocks(1081, '', 'ignored').proxySettings;
    expect((anon.username, anon.password), (null, null));
  });

  test('no tunnel — direct right away', () async {
    final calls = <TunnelSocks?>[];
    expect(await TunnelSocks.orDirect(null, (s) async => calls..add(s)), [null]);
  });

  test('connectivity failure through the tunnel → retry directly', () async {
    final calls = <TunnelSocks?>[];
    final r = await TunnelSocks.orDirect(socks, (s) async {
      calls.add(s);
      if (s != null) throw const SocketException('tunnel dead');
      return 'direct';
    });
    expect(r, 'direct');
    expect(calls, [socks, null]);
  });

  test('a server response (HTTP error) is not retried directly', () async {
    final calls = <TunnelSocks?>[];
    await expectLater(
      TunnelSocks.orDirect<void>(socks, (s) async {
        calls.add(s);
        throw Exception('HTTP 404');
      }),
      throwsException,
    );
    expect(calls, [socks]);
  });
}
