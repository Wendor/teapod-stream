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
        fault: Fault.offline10s,
        restoredAt: t0,
        after: [s(20, false, 'connecting'), s(40, true)],
      );
      expect(r.verdict, Verdict.pass);
      expect(r.recovery, const Duration(seconds: 40));
    });

    test('no traffic for 4 min while reconnecting → fail', () {
      final r = classifyRecovery(
        fault: Fault.offline1m,
        restoredAt: t0,
        after: [for (var i = 20; i <= 240; i += 20) s(i, false, 'connecting')],
      );
      expect(r.verdict, Verdict.fail);
      expect(r.recovery, isNull);
    });

    test('no traffic for 4 min while app says connected → zombie', () {
      final r = classifyRecovery(
        fault: Fault.wifiLte,
        restoredAt: t0,
        after: [for (var i = 20; i <= 240; i += 20) s(i, false)],
      );
      expect(r.verdict, Verdict.zombie);
    });

    test('ok probe only after the window → fail', () {
      final r = classifyRecovery(fault: Fault.doze, restoredAt: t0, after: [s(60, false, 'connecting'), s(200, true)]);
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
      expect(
        classifyIdle([s(0, false, 'connecting'), s(20, false, 'connecting'), s(40, false, 'connecting')]).verdict,
        Verdict.fail,
      );
      expect(classifyIdle([s(0, false), s(20, false), s(40, false)]).verdict, Verdict.zombie);
    });
  });

  test('Fault.fromCli', () {
    expect(Fault.fromCli('offline-5m'), Fault.offline5m);
    expect(Fault.fromCli('kill'), Fault.killApp);
    expect(() => Fault.fromCli('nope'), throwsArgumentError);
  });

  group('probeOk', () {
    bool ok(String? ip, {String? egress, bool strict = false, String? tunnelIp, bool onWifi = true}) => probeOk(
      ip: ip,
      direct: '198.51.100.1',
      distinguishable: true,
      egress: egress,
      strict: strict,
      tunnelIp: tunnelIp,
      onWifi: onWifi,
    );

    test('after server-switch (no expected exit): any exit but the direct one', () {
      expect(ok('203.0.113.9'), isTrue);
      expect(ok('198.51.100.1'), isFalse);
      expect(ok(null), isFalse);
    });

    test('a strict exit must match, on Wi-Fi too', () {
      expect(ok('203.0.113.5', egress: '203.0.113.5', strict: true), isTrue);
      expect(ok('203.0.113.9', egress: '203.0.113.5', strict: true), isFalse);
    });

    test('off Wi-Fi the exit seen on Wi-Fi is expected', () {
      expect(ok('203.0.113.7', tunnelIp: '203.0.113.7', onWifi: false), isTrue);
      expect(ok('192.0.2.50', tunnelIp: '203.0.113.7', onWifi: false), isFalse);
    });
  });

  group('server faults and adoption', () {
    final passed = FaultResult(Fault.serverDown, Verdict.pass, const Duration(seconds: 1), 'recovered in 1s');

    test('no relay → SKIP', () {
      expect(relayMissing(Fault.serverSwitch, hasRelay: false)?.verdict, Verdict.skip);
      expect(relayMissing(Fault.serverSwitch, hasRelay: true), isNull);
    });

    test('traffic during the cut turns a recovery into FAIL', () {
      expect(cutChecked(passed, trafficDuringCut: true).verdict, Verdict.fail);
      expect(cutChecked(passed, trafficDuringCut: false), same(passed));
    });

    test('a recovered kill / ui-restart fails unless the fresh UI shows connected', () {
      final r = FaultResult(Fault.uiRestart, Verdict.pass, Duration.zero, 'recovered in 0s');
      expect(adoptionChecked(r, 'connected'), same(r));
      final bad = adoptionChecked(r, 'disconnected');
      expect(bad.verdict, Verdict.fail);
      expect(bad.note, contains('disconnected'));
      final failed = FaultResult(Fault.killApp, Verdict.fail, null, 'no traffic');
      expect(adoptionChecked(failed, 'disconnected'), same(failed));
    });
  });

  group('ExpectedExit', () {
    const direct = '198.51.100.1';
    bool check(ExpectedExit e, String? ip, {bool onWifi = true}) =>
        e.check(ip: ip, direct: direct, distinguishable: true, onWifi: onWifi);

    test('relay → server-switch → back: each expectation replaces the last and forgets the Wi-Fi exit', () {
      final e = ExpectedExit('203.0.113.5', true);
      expect(check(e, '203.0.113.9'), isFalse, reason: 'the config is strict');

      e.expect((egress: '203.0.113.7', strict: false)); // on the relay copy
      expect(check(e, '203.0.113.7'), isTrue);
      expect(e.tunnelIp, '203.0.113.7');
      expect(check(e, '192.0.2.1', onWifi: false), isFalse, reason: 'off Wi-Fi the exit seen on Wi-Fi is expected');

      e.expect((egress: null, strict: false)); // server-switch: any other config
      expect(e.tunnelIp, isNull);
      expect(check(e, '192.0.2.44'), isTrue);
      expect(check(e, direct), isFalse);

      e.expect(null); // back on the config
      expect(e.current, (egress: '203.0.113.5', strict: true));
      expect(e.tunnelIp, isNull);
      expect(check(e, '192.0.2.44'), isFalse);
      expect(check(e, '203.0.113.5'), isTrue);
    });
  });

  test('server-down: an answer from another exit during the cut fails, though it is not the expected exit', () {
    final exits = ExpectedExit('203.0.113.5', false)..tunnelIp = '203.0.113.5';
    // The cut runs off Wi-Fi bookkeeping: an exit other than the expected one isn't a pass...
    expect(exits.check(ip: '192.0.2.9', direct: '198.51.100.1', distinguishable: true, onWifi: false), isFalse);
    // ...but it is traffic, and the session wasn't on the relay.
    final answers = <String?>[null, '192.0.2.9', null];
    final passed = FaultResult(Fault.serverDown, Verdict.pass, Duration.zero, 'recovered in 0s');
    expect(cutChecked(passed, trafficDuringCut: trafficDuringCut(answers)).verdict, Verdict.fail);
    expect(cutChecked(passed, trafficDuringCut: trafficDuringCut([null, null])), same(passed));
  });
}
