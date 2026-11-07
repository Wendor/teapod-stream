import 'package:flutter_test/flutter_test.dart';

import '../../../tool/itest/src/device_guard.dart';
import 'fake_shell.dart';

void main() {
  FakeShell shell() => FakeShell({
        'settings get global wifi_on': '1',
        'settings get global airplane_mode_on': '0',
        'settings get global stay_on_while_plugged_in': '0',
      });

  test('restore reverts only changed params, idempotent', () async {
    final s = shell();
    final g = DeviceGuard(s);
    await g.snapshot();
    await g.airplane(true);
    s.calls.clear();
    await g.restore();
    await g.restore();
    expect(s.calls, ['shell cmd connectivity airplane-mode disable']);
  });

  test('restore brings wifi back and leaves doze', () async {
    final s = shell();
    final g = DeviceGuard(s);
    await g.snapshot();
    await g.wifi(false);
    await g.doze(true);
    s.calls.clear();
    await g.restore();
    expect(s.calls, containsAll([
      'shell cmd wifi set-wifi-enabled enabled',
      'shell dumpsys deviceidle unforce',
      'shell dumpsys battery reset',
    ]));
  });

  test('turning a fault off clears its undo', () async {
    final s = shell();
    final g = DeviceGuard(s);
    await g.snapshot();
    await g.airplane(true);
    await g.airplane(false);
    s.calls.clear();
    await g.restore();
    expect(s.calls, isEmpty);
  });

  test('killApp refuses main package', () {
    expect(() => DeviceGuard(shell()).killApp('com.teapodstream.teapodstream'), throwsArgumentError);
  });

  test('undo is registered before the command runs (Ctrl+C mid-command)', () async {
    final s = shell();
    final g = DeviceGuard(s);
    await g.snapshot();
    final pending = g.airplane(true); // команда ещё выполняется
    s.calls.clear();
    await g.restore();
    await pending.catchError((_) {});
    expect(s.calls, contains('shell cmd connectivity airplane-mode disable'));
  });

  test('after restore new faults are refused', () async {
    final g = DeviceGuard(shell());
    await g.snapshot();
    await g.restore();
    expect(() => g.airplane(true), throwsStateError);
  });

  test('snapshot with empty answers keeps wifi untouched on restore', () async {
    final s = FakeShell();
    final g = DeviceGuard(s);
    await g.snapshot();
    await g.wifi(false);
    s.calls.clear();
    await g.restore();
    expect(s.calls, isEmpty, reason: 'unknown original state must not be "restored" by guessing');
  });
}
