import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/services/tunnel_socks.dart';

void main() {
  const socks = TunnelSocks(1080, 'u', 'p');

  test('без туннеля — сразу напрямую', () async {
    final calls = <TunnelSocks?>[];
    expect(await TunnelSocks.orDirect(null, (s) async => calls..add(s)), [null]);
  });

  test('сбой через туннель → повтор напрямую', () async {
    final calls = <TunnelSocks?>[];
    final r = await TunnelSocks.orDirect(socks, (s) async {
      calls.add(s);
      if (s != null) throw Exception('tunnel dead');
      return 'direct';
    });
    expect(r, 'direct');
    expect(calls, [socks, null]);
  });

  test('ошибка из keep не повторяется напрямую', () async {
    final calls = <TunnelSocks?>[];
    await expectLater(
      TunnelSocks.orDirect<void>(socks, (s) async {
        calls.add(s);
        throw StateError('cert');
      }, keep: (e) => e is StateError),
      throwsStateError,
    );
    expect(calls, [socks]);
  });
}
