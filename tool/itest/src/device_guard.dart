import 'dart:io';

import 'adb.dart';
import 'agent_client.dart';

/// Phone state during a run: faults and their guaranteed rollback.
class DeviceGuard {
  final Shell shell;
  final _original = <String, String>{};
  final _undo = <String, List<String>>{};
  var _closed = false;

  DeviceGuard(this.shell);

  Future<String> _sh(String cmd) async => (await shell.run(['shell', cmd])).out.trim();

  /// Changes and rollback in order: a rollback won't overtake a fault command started before it.
  Future<void> _queue = Future.value();
  Future<T> _serial<T>(Future<T> Function() f) {
    final r = _queue.then((_) => f());
    _queue = r.then((_) {}, onError: (_) {});
    return r;
  }

  /// Original values; a non-numeric answer (adb hang) — the value is unknown,
  /// such a parameter isn't "restored" at random.
  Future<void> snapshot() async {
    for (final k in ['wifi_on', 'airplane_mode_on', 'stay_on_while_plugged_in']) {
      final v = await _sh('settings get global $k');
      if (int.tryParse(v) != null) _original[k] = v;
    }
    _screenWasOff = RegExp('Asleep|Dozing').hasMatch(await _sh('dumpsys power | grep -m1 mWakefulness='));
  }

  var _screenWasOff = false;

  /// [undo] — rollback commands, null — the parameter is back to the original. The rollback
  /// is registered before the command: Ctrl+C in the middle of it still rolls back.
  /// Returning to the original ([undo] == null) removes the rollback only after a successful command.
  Future<void> _apply(String key, String cmd, List<String>? undo) => _serial(() async {
    if (_closed) throw StateError('DeviceGuard: the phone has already been restored to its original state');
    if (undo != null) _undo.putIfAbsent(key, () => undo);
    final r = await shell.run(['shell', cmd]);
    if (!r.ok) throw StateError('adb: $cmd → ${r.code} ${r.err.trim()}');
    if (undo == null) _undo.remove(key);
  });

  /// Rollback to the original [flag] (`'0'`/`'1'`); null — the original is unknown.
  List<String>? _toggleUndo(String flag, bool on, String Function(bool on) cmd) {
    final orig = _original[flag];
    if (orig == null || on == (orig == '1')) return null;
    return [cmd(!on)];
  }

  /// Without a snapshot of the original state switching isn't allowed — there would be nothing to roll back.
  void _requireKnown(String flag) {
    if (_original[flag] == null) throw StateError('original $flag unknown — the fault is not applied');
  }

  Future<void> wifi(bool on) async {
    _requireKnown('wifi_on');
    String cmd(bool on) => 'cmd wifi set-wifi-enabled ${on ? 'enabled' : 'disabled'}';
    await _apply('wifi', cmd(on), _toggleUndo('wifi_on', on, cmd));
  }

  Future<void> airplane(bool on) async {
    _requireKnown('airplane_mode_on');
    String cmd(bool on) => 'cmd connectivity airplane-mode ${on ? 'enable' : 'disable'}';
    await _apply('airplane', cmd(on), _toggleUndo('airplane_mode_on', on, cmd));
  }

  Future<void> doze(bool on) async {
    if (on) {
      await _apply('battery', 'dumpsys battery unplug', ['dumpsys battery reset']);
      await _apply('doze', 'dumpsys deviceidle force-idle', ['dumpsys deviceidle unforce']);
    } else {
      await _apply('doze', 'dumpsys deviceidle unforce', null);
      await _apply('battery', 'dumpsys battery reset', null);
    }
  }

  Future<void> stayAwake(bool on) {
    final orig = _original['stay_on_while_plugged_in'];
    return _apply(
      'stay',
      'svc power stayon ${on ? 'usb' : 'false'}',
      orig == null ? null : ['settings put global stay_on_while_plugged_in $orig'],
    );
  }

  /// Doze exemption (build.sh itest enables it on install).
  Future<void> whitelist(String pkg, bool on) => _apply(
    'whitelist',
    'dumpsys deviceidle whitelist ${on ? '+' : '-'}$pkg',
    on ? null : ['dumpsys deviceidle whitelist +$pkg'],
  );

  Future<void> screen(bool on) => _sh('input keyevent ${on ? 'WAKEUP' : 'SLEEP'}');

  /// Kills the itest app process (only it).
  Future<void> killApp(String pkg) async {
    if (pkg != itestPackage) throw ArgumentError('killApp is allowed only for $itestPackage, not $pkg');
    await _sh("run-as $pkg sh -c 'kill -9 \$(pidof $pkg)'");
  }

  /// Moves the itest app off the screen and stops it (it shows
  /// over the lock screen and can share configs).
  Future<void> parkApp() async {
    await _sh('am start -a android.intent.action.MAIN -c android.intent.category.HOME');
    await _sh('am force-stop $itestPackage');
    // The run wakes the screen (screen(true), the agent activity) — turn it off if it was off.
    if (_screenWasOff) await _sh('input keyevent SLEEP');
  }

  /// Rolls back all changed parameters; no new faults are accepted afterwards.
  /// A failed rollback stays and is retried on the next call; errors
  /// don't interrupt the rest of the rollback.
  Future<void> restore() => _serial(() async {
    _closed = true;
    for (final MapEntry(key: key, value: cmds) in Map.of(_undo).entries) {
      var ok = true;
      for (final c in cmds) {
        try {
          final r = await shell.run(['shell', c]);
          if (!r.ok) {
            ok = false;
            stderr.writeln('  ! rollback failed: $c (${r.code}) ${r.err.trim()}');
          }
        } catch (e) {
          ok = false;
          stderr.writeln('  ! rollback failed: $c ($e)');
        }
      }
      if (ok) _undo.remove(key);
    }
  });
}
