import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/itest/src/agent_client.dart';
import 'fake_shell.dart';

String _id(String amStart) {
  final json = amStart.substring(amStart.indexOf("--es cmd '") + 10, amStart.lastIndexOf("'"));
  return (jsonDecode(json) as Map)['id'] as String;
}

void main() {
  late FakeShell shell;
  late StreamController<String> logcat;
  late AgentClient client;

  setUp(() {
    shell = FakeShell();
    logcat = StreamController<String>.broadcast();
    client = AgentClient(shell, logcat.stream);
  });

  test('send resolves on marker with same id, ignores other ids', () async {
    final f = client.send('ping');
    await Future<void>.delayed(Duration.zero);
    final id = _id(shell.calls.single);
    logcat.add('I flutter : TEAPOD_ITEST {"id":"other","ok":true,"data":1}');
    logcat.add('I flutter : TEAPOD_ITEST {"id":"$id","ok":true,"data":{"cores":["go"]}}');
    expect(await f, {'cores': ['go']});
  });

  test('send quotes JSON for the device shell', () async {
    unawaited(client.send('settings', {'patch': {'s': "it's"}}, const Duration(milliseconds: 10)).catchError((_) => null));
    await Future<void>.delayed(Duration.zero);
    expect(shell.calls.single, contains(r"""it'\''s"""));
  });

  test('send retries am start when it hangs', () async {
    shell = FakeShell(const {}, [-1, 0]);
    client = AgentClient(shell, logcat.stream);
    final f = client.send('ping');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(shell.calls, hasLength(2));
    logcat.add('TEAPOD_ITEST {"id":"${_id(shell.calls.last)}","ok":true,"data":1}');
    expect(await f, 1);
  });

  test('send throws ItestTimeout when no marker', () {
    expect(client.send('ping', const {}, const Duration(milliseconds: 50)),
        throwsA(isA<ItestTimeout>()));
  });

  test('send throws ItestAgentError on ok:false with error text', () async {
    final f = client.send('connect');
    await Future<void>.delayed(Duration.zero);
    logcat.add('TEAPOD_ITEST {"id":"${_id(shell.calls.single)}","ok":false,"error":"core sing-box: nope"}');
    await expectLater(f, throwsA(isA<ItestAgentError>().having((e) => e.message, 'message', contains('nope'))));
  });

  test('send reads large replies from the file named in the marker', () async {
    shell = FakeShell({'cat ': jsonEncode({'id': 'x', 'ok': true, 'data': [1, 2, 3]})});
    client = AgentClient(shell, logcat.stream);
    final f = client.send('list');
    await Future<void>.delayed(Duration.zero);
    logcat.add('TEAPOD_ITEST {"id":"${_id(shell.calls.first)}","ok":true,"file":"/data/user/0/p/files/itest_x.json"}');
    expect(await f, [1, 2, 3]);
    expect(shell.calls.last, contains('run-as $itestPackage cat /data/user/0/p/files/itest_x.json'));
  });

  test('waitState completes on native state marker', () async {
    final f = client.waitState({'connected', 'error'}, const Duration(seconds: 1));
    logcat.add('TEAPOD_ITEST {"ev":"state","value":"connecting","t":1}');
    logcat.add('TEAPOD_ITEST {"ev":"state","value":"connected","t":2,"socksPort":1080}');
    expect(await f, 'connected');
    expect(client.lastConnected?['socksPort'], 1080);
  });
}
