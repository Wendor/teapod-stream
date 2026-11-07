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

  /// Исходные значения; нечисловой ответ (зависание adb) — значение неизвестно,
  /// такой параметр не «восстанавливается» наугад.
  Future<void> snapshot() async {
    for (final k in ['wifi_on', 'airplane_mode_on', 'stay_on_while_plugged_in']) {
      final v = await _sh('settings get global $k');
      if (int.tryParse(v) != null) _original[k] = v;
    }
  }

  /// [undo] — команды отката, null — параметр вернулся в исходное. Откат
  /// регистрируется до команды: Ctrl+C посреди неё всё равно откатит.
  Future<void> _apply(String key, String cmd, List<String>? undo) async {
    if (_closed) throw StateError('DeviceGuard: телефон уже возвращён в исходное состояние');
    undo == null ? _undo.remove(key) : _undo.putIfAbsent(key, () => undo);
    await _sh(cmd);
  }

  /// Откат к исходному [flag] (`'0'`/`'1'`); null — исходное неизвестно.
  List<String>? _toggleUndo(String flag, bool on, String Function(bool on) cmd) {
    final orig = _original[flag];
    if (orig == null || on == (orig == '1')) return null;
    return [cmd(!on)];
  }

  Future<void> wifi(bool on) {
    String cmd(bool on) => 'cmd wifi set-wifi-enabled ${on ? 'enabled' : 'disabled'}';
    return _apply('wifi', cmd(on), _toggleUndo('wifi_on', on, cmd));
  }

  Future<void> airplane(bool on) {
    String cmd(bool on) => 'cmd connectivity airplane-mode ${on ? 'enable' : 'disable'}';
    return _apply('airplane', cmd(on), _toggleUndo('airplane_mode_on', on, cmd));
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
  }

  /// Откат всех изменённых параметров; дальше новые сбои не принимаются.
  /// Повторный вызов ничего не делает.
  Future<void> restore() async {
    _closed = true;
    final undo = Map.of(_undo);
    _undo.clear();
    for (final cmds in undo.values) {
      for (final c in cmds) {
        await _sh(c);
      }
    }
  }
}
