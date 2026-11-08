import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/itest/src/matrix.dart';
import '../../../tool/itest/src/probes.dart';
import '../../../tool/itest/src/report.dart';
import '../../../tool/itest/src/soak.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('itest_report'));
  tearDown(() => tmp.deleteSync(recursive: true));

  RunReport sample() {
    final r = RunReport(RunDir(tmp))
      ..meta = {'app': '1.7.4', 'device': 'A065'}
      ..baseline = const Baseline({'u': '9.9.9.9'}, null, null);
    r.add(const CaseResult('base/sing-box/oslo-awg', Verdict.pass, 'via 1.2.3.4', Duration(seconds: 12), 'cases/base/sing-box/oslo-awg'));
    r.add(const CaseResult('opt/xray-core/split-only-shell', Verdict.fail, 'no traffic', Duration(seconds: 30), 'cases/opt/xray-core/split-only-shell'));
    r.addFault('sing-box', FaultResult(Fault.offline1m, Verdict.zombie, null, 'connected without traffic for 200s'));
    return r;
  }

  test('report lists cases with verdicts, links and rerun commands', () {
    final md = sample().render();
    expect(md, contains('| id | verdict | note | took |'));
    expect(md, contains('[opt/xray-core/split-only-shell](cases/opt/xray-core/split-only-shell/)'));
    expect(md, contains("dart run tool/itest/main.dart --skip-install --phase matrix --case 'opt/xray-core/split-only-shell'"));
    expect(md, contains('ZOMBIE'));
    expect(md, contains('--phase soak --core sing-box --fault offline-1m'));
  });

  test('report reminds to reconnect the main app VPN', () {
    expect(sample().render(), contains('основного приложения'));
  });

  test('case dir stays inside the run dir and rerun command quotes the id', () {
    final run = RunDir(tmp);
    expect(run.caseDir('base/x/../../evil').path, startsWith('${tmp.path}/cases/'));
    expect(run.caseDir('base/x/../../evil').path, isNot(contains('..')));
    final r = RunReport(run)..add(const CaseResult("base/x/it's", Verdict.fail, 'n', Duration.zero, 'd'));
    expect(r.render(), contains(r"--case 'base/x/it'\''s'"));
  });

  test('write produces md and json', () {
    sample().write();
    expect(File('${tmp.path}/report.md').existsSync(), isTrue);
    expect(File('${tmp.path}/report.json').readAsStringSync(), contains('"verdict":"fail"'));
  });

  test('maskSecrets hides credentials in URIs and UUIDs', () {
    final m = maskSecrets('vless://0c5e1a2b-1111-2222-3333-444455556666@host:443?pbk=abcKEY&sid=77&type=tcp#n '
        'hysteria2://topsecret@h:1 ssh://u:pw@s:22');
    expect(m, isNot(contains('0c5e')));
    expect(m, isNot(contains('abcKEY')));
    expect(m, isNot(contains('topsecret')));
    expect(m, isNot(contains('pw@')));
    expect(m, contains('type=tcp'));
  });

  test('render masks secrets that leak into notes', () {
    final r = RunReport(RunDir(tmp));
    r.add(const CaseResult('x', Verdict.fail, 'error ssh://u:pw@s:22', Duration.zero, 'cases/x'));
    expect(r.render(), isNot(contains('pw@')));
  });

  test('notes (import failures, skipped phases) are rendered', () {
    final r = RunReport(RunDir(tmp))..note('import: sub#0 failed');
    expect(r.render(), contains('import: sub#0 failed'));
  });
}
