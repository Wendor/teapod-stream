import 'dart:io';

import 'adb.dart';
import 'agent_client.dart';

/// Состояние телефона на время прогона: сбои и их гарантированный откат.
class DeviceGuard {
  final Shell shell;
  final _original = <String, String>{};
  final _undo = <String, List<String>>{};
  var _closed = false;

  DeviceGuard(this.shell);

  Future<String> _sh(String cmd) async => (await shell.run(['shell', cmd])).out.trim();

  /// Изменения и откат по очереди: откат не обгонит команду сбоя, начатую до него.
  Future<void> _queue = Future.value();
  Future<T> _serial<T>(Future<T> Function() f) {
    final r = _queue.then((_) => f());
    _queue = r.then((_) {}, onError: (_) {});
    return r;
  }

  /// Исходные значения; нечисловой ответ (зависание adb) — значение неизвестно,
  /// такой параметр не «восстанавливается» наугад.
  Future<void> snapshot() async {
    for (final k in ['wifi_on', 'airplane_mode_on', 'stay_on_while_plugged_in']) {
      final v = await _sh('settings get global $k');
      if (int.tryParse(v) != null) _original[k] = v;
    }
    _screenWasOff = RegExp('Asleep|Dozing').hasMatch(await _sh('dumpsys power | grep -m1 mWakefulness='));
  }

  var _screenWasOff = false;

  /// [undo] — команды отката, null — параметр вернулся в исходное. Откат
  /// регистрируется до команды: Ctrl+C посреди неё всё равно откатит.
  /// Возврат в исходное ([undo] == null) снимает откат только после успешной команды.
  Future<void> _apply(String key, String cmd, List<String>? undo) => _serial(() async {
        if (_closed) throw StateError('DeviceGuard: телефон уже возвращён в исходное состояние');
        if (undo != null) _undo.putIfAbsent(key, () => undo);
        final r = await shell.run(['shell', cmd]);
        if (!r.ok) throw StateError('adb: $cmd → ${r.code} ${r.err.trim()}');
        if (undo == null) _undo.remove(key);
      });

  /// Откат к исходному [flag] (`'0'`/`'1'`); null — исходное неизвестно.
  List<String>? _toggleUndo(String flag, bool on, String Function(bool on) cmd) {
    final orig = _original[flag];
    if (orig == null || on == (orig == '1')) return null;
    return [cmd(!on)];
  }

  /// Без снимка исходного состояния переключать нельзя — нечего было бы откатить.
  void _requireKnown(String flag) {
    if (_original[flag] == null) throw StateError('исходное $flag неизвестно — сбой не применяется');
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
    return _apply('stay', 'svc power stayon ${on ? 'usb' : 'false'}',
        orig == null ? null : ['settings put global stay_on_while_plugged_in $orig']);
  }

  /// Исключение из Doze (build.sh itest включает его при установке).
  Future<void> whitelist(String pkg, bool on) => _apply('whitelist', 'dumpsys deviceidle whitelist ${on ? '+' : '-'}$pkg',
      on ? null : ['dumpsys deviceidle whitelist +$pkg']);

  Future<void> screen(bool on) => _sh('input keyevent ${on ? 'WAKEUP' : 'SLEEP'}');

  /// Убивает процесс itest-приложения (только его).
  Future<void> killApp(String pkg) async {
    if (pkg != itestPackage) throw ArgumentError('killApp разрешён только для $itestPackage, не $pkg');
    await _sh("run-as $pkg sh -c 'kill -9 \$(pidof $pkg)'");
  }

  /// Уводит itest-приложение с экрана и останавливает его (оно показывается
  /// поверх локскрина и умеет делиться конфигами).
  Future<void> parkApp() async {
    await _sh('am start -a android.intent.action.MAIN -c android.intent.category.HOME');
    await _sh('am force-stop $itestPackage');
    // Прогон будит экран (screen(true), activity агента) — гасим, если был погашен.
    if (_screenWasOff) await _sh('input keyevent SLEEP');
  }

  /// Откат всех изменённых параметров; дальше новые сбои не принимаются.
  /// Неудавшийся откат остаётся и повторяется при следующем вызове; ошибки
  /// не прерывают остальной откат.
  Future<void> restore() => _serial(() async {
        _closed = true;
        for (final MapEntry(key: key, value: cmds) in Map.of(_undo).entries) {
          var ok = true;
          for (final c in cmds) {
            try {
              final r = await shell.run(['shell', c]);
              if (!r.ok) {
                ok = false;
                stderr.writeln('  ! откат не удался: $c (${r.code}) ${r.err.trim()}');
              }
            } catch (e) {
              ok = false;
              stderr.writeln('  ! откат не удался: $c ($e)');
            }
          }
          if (ok) _undo.remove(key);
        }
      });
}
