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

/// Stub agent: answers ok to every command, sends `connected` on connect.
class ScriptedShell implements Shell {
  final StreamController<String> logcat;
  final ops = <String>[];

  /// Cores whose connect the agent refuses; the core the native marker reports instead of the asked one.
  final Set<String> refuse;
  final String? runs;

  ScriptedShell(this.logcat, {this.refuse = const {}, this.runs});

  @override
  Future<ProcResult> run(List<String> args, {Duration timeout = const Duration(seconds: 30)}) async {
    final cmd = args.join(' ');
    final i = cmd.indexOf("--es cmd '");
    if (i >= 0) {
      final m = jsonDecode(cmd.substring(i + 10, cmd.lastIndexOf("'"))) as Map;
      ops.add(m['op'] == 'connect' ? 'connect ${m['core']}' : m['op'] as String);
      scheduleMicrotask(() {
        if (m['op'] == 'connect' && refuse.contains(m['core'])) {
          logcat.add('TEAPOD_ITEST {"id":"${m['id']}","ok":false,"error":"Bad state: core ${m['core']}: no"}');
          return;
        }
        logcat.add('TEAPOD_ITEST {"id":"${m['id']}","ok":true}');
        if (m['op'] == 'connect') {
          logcat.add('TEAPOD_ITEST {"ev":"state","value":"connected","t":1,"core":"${runs ?? m['core']}"}');
        }
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
    final mc = MatrixCase(
      'opt/x/boom',
      'cfg',
      'cfg',
      'go',
      const {},
      (_) => throw const FormatException('bad json'),
      true,
    );

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
    final ctx = CaseCtx(
      AgentClient(shell, logcat.stream),
      Probes(shell),
      const Baseline({}, null, null),
      DeviceGuard(shell),
      null,
    );
    final mc = MatrixCase(
      'opt/x/route-sites-only',
      'cfg',
      'cfg',
      'rust',
      const {
        'routing': {
          'sites': [echoHostPlaceholder],
        },
      },
      (_) async => (v: Verdict.pass, note: ''),
      true,
    );

    final r = await runCase(mc, ctx, RunDir(tmp), shell, logcat.stream);

    expect(r.verdict, Verdict.skip);
    expect(shell.ops.where((o) => o.startsWith('connect')), isEmpty);
  });

  group('core-switch', () {
    Future<(CaseResult, ScriptedShell)> run({Set<String> refuse = const {}, String? runs}) async {
      final tmp = Directory.systemTemp.createTempSync('itest_case');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final logcat = StreamController<String>.broadcast();
      final shell = ScriptedShell(logcat, refuse: refuse, runs: runs);
      final ctx = CaseCtx(
        AgentClient(shell, logcat.stream),
        Probes(shell),
        const Baseline({}, null, null),
        DeviceGuard(shell),
        null,
        configId: 'cfg',
      );
      final (patch, check) = optionCases['core-switch']!;
      final mc = MatrixCase('opt/xray-core/core-switch', 'cfg', 'cfg', 'go', patch, check, true);
      return (await runCase(mc, ctx, RunDir(tmp), shell, logcat.stream), shell);
    }

    test('switches the live session to every other core that runs the config, then disconnects', () async {
      final (r, shell) = await run(refuse: {'rust'});
      expect(shell.ops.where((o) => o.startsWith('connect') || o == 'disconnect').take(4), [
        'connect go',
        'connect rust',
        'connect box',
        'disconnect',
      ]);
      expect(r.note, contains('sing-box'));
      expect(r.note, isNot(contains('switch to')));
      expect(shell.ops.where((o) => o == 'disconnect'), hasLength(1), reason: 'no second disconnect when already off');
    });

    test('a session that still runs the old core fails', () async {
      final (r, _) = await run(runs: 'go');
      expect(r.verdict, Verdict.fail);
      expect(r.note, contains('switch to xray-rust: connected on go'));
    });
  });
}
