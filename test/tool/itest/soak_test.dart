import 'package:flutter_test/flutter_test.dart';

import '../../../tool/itest/src/probes.dart';
import '../../../tool/itest/src/soak.dart';

final t0 = DateTime(2026, 11, 7, 12);

ProbeSample s(int sec, bool ok, [String? state = 'connected']) =>
    (t: t0.add(Duration(seconds: sec)), ok: ok, appState: state);

void main() {
  group('classifyRecovery', () {
    test('first ok probe within window → pass with recovery time', () {
      final r = classifyRecovery(
          fault: Fault.offline10s, restoredAt: t0, after: [s(20, false, 'connecting'), s(40, true)]);
      expect(r.verdict, Verdict.pass);
      expect(r.recovery, const Duration(seconds: 40));
    });

    test('no traffic for 4 min while reconnecting → fail', () {
      final r = classifyRecovery(
          fault: Fault.offline1m, restoredAt: t0, after: [for (var i = 20; i <= 240; i += 20) s(i, false, 'connecting')]);
      expect(r.verdict, Verdict.fail);
      expect(r.recovery, isNull);
    });

    test('no traffic for 4 min while app says connected → zombie', () {
      final r = classifyRecovery(
          fault: Fault.wifiLte, restoredAt: t0, after: [for (var i = 20; i <= 240; i += 20) s(i, false)]);
      expect(r.verdict, Verdict.zombie);
    });

    test('ok probe only after the window → fail', () {
      final r = classifyRecovery(
          fault: Fault.doze, restoredAt: t0, after: [s(60, false, 'connecting'), s(200, true)]);
      expect(r.verdict, Verdict.fail);
    });
  });

  group('classifyIdle', () {
    test('steady traffic → pass', () {
      expect(classifyIdle([for (var i = 0; i < 10; i++) s(i * 20, true)]).verdict, Verdict.pass);
    });

    test('3 failed probes in a row → not pass', () {
      final r = classifyIdle([s(0, true), s(20, false), s(40, false), s(60, false), s(80, true)]);
      expect(r.verdict, isNot(Verdict.pass));
      expect(r.note, contains('recovered'));
    });

    test('2 isolated failures → pass', () {
      expect(classifyIdle([s(0, false), s(20, true), s(40, false), s(60, true)]).verdict, Verdict.pass);
    });

    test('outage with connecting state → fail, with connected → zombie', () {
      expect(classifyIdle([s(0, false, 'connecting'), s(20, false, 'connecting'), s(40, false, 'connecting')]).verdict,
          Verdict.fail);
      expect(classifyIdle([s(0, false), s(20, false), s(40, false)]).verdict, Verdict.zombie);
    });
  });

  test('Fault.fromCli', () {
    expect(Fault.fromCli('offline-5m'), Fault.offline5m);
    expect(Fault.fromCli('kill'), Fault.killApp);
    expect(() => Fault.fromCli('nope'), throwsArgumentError);
  });
}
