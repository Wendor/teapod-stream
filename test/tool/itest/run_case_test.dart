import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/itest/src/adb.dart';
import '../../../tool/itest/src/agent_client.dart';
import '../../../tool/itest/src/device_guard.dart';
import '../../../tool/itest/src/matrix.dart';
import '../../../tool/itest/src/probes.dart';
import '../../../tool/itest/src/report.dart';

/// Агент-заглушка: отвечает ok на каждую команду, на connect шлёт `connected`.
class ScriptedShell implements Shell {
  final StreamController<String> logcat;
  final ops = <String>[];

  ScriptedShell(this.logcat);

  @override
  Future<ProcResult> run(List<String> args, {Duration timeout = const Duration(seconds: 30)}) async {
    final cmd = args.join(' ');
    final i = cmd.indexOf("--es cmd '");
    if (i >= 0) {
      final m = jsonDecode(cmd.substring(i + 10, cmd.lastIndexOf("'"))) as Map;
      ops.add(m['op'] as String);
      scheduleMicrotask(() {
        logcat.add('TEAPOD_ITEST {"id":"${m['id']}","ok":true}');
        if (m['op'] == 'connect') logcat.add('TEAPOD_ITEST {"ev":"state","value":"connected","t":1}');
        if (m['op'] == 'disconnect') logcat.add('TEAPOD_ITEST {"ev":"state","value":"disconnected","t":2}');
      });
    }
    return const ProcResult(0, '', '');
  }
}

void main() {
  test('unexpected exception in a check → FAIL(internal), VPN still disconnected', () async {
    final tmp = Directory.systemTemp.createTempSync('itest_case');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final logcat = StreamController<String>.broadcast();
    final shell = ScriptedShell(logcat);
    final agent = AgentClient(shell, logcat.stream);
    final ctx = CaseCtx(agent, Probes(shell), const Baseline({}, null, null), DeviceGuard(shell), null);
    final mc = MatrixCase('opt/x/boom', 'cfg', 'cfg', 'go', const {}, (_) => throw const FormatException('bad json'), true);

    final r = await runCase(mc, ctx, RunDir(tmp), shell, logcat.stream);

    expect(r.verdict, Verdict.fail);
    expect(r.note, contains('internal'));
    expect(shell.ops, contains('disconnect'));
  });

  test('echo-host rule without two usable echo services → SKIP before connect', () async {
    final tmp = Directory.systemTemp.createTempSync('itest_case');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final logcat = StreamController<String>.broadcast();
    final shell = ScriptedShell(logcat);
    final ctx = CaseCtx(AgentClient(shell, logcat.stream), Probes(shell), const Baseline({}, null, null),
        DeviceGuard(shell), null);
    final mc = MatrixCase('opt/x/route-sites-only', 'cfg', 'cfg', 'rust',
        const {'routing': {'sites': [echoHostPlaceholder]}}, (_) async => (v: Verdict.pass, note: ''), true);

    final r = await runCase(mc, ctx, RunDir(tmp), shell, logcat.stream);

    expect(r.verdict, Verdict.skip);
    expect(shell.ops, isNot(contains('connect')));
  });
}
