import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ProcResult {
  final int code;
  final String out;
  final String err;

  const ProcResult(this.code, this.out, this.err);

  bool get ok => code == 0;
}

/// Выполнение adb-команд; в тестах подменяется.
abstract class Shell {
  Future<ProcResult> run(List<String> args, {Duration timeout = const Duration(seconds: 30)});
}

/// Одинарные кавычки для shell на устройстве.
String shQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";

class Adb implements Shell {
  final String serial;

  Adb(this.serial);

  /// Serial из аргумента, ANDROID_SERIAL или единственного подключённого.
  static Future<Adb> connect([String? serial]) async {
    serial ??= Platform.environment['ANDROID_SERIAL'];
    if (serial != null && serial.isNotEmpty) return Adb(serial);
    final r = await Process.run('adb', ['devices']);
    final ids = LineSplitter.split(r.stdout as String)
        .skip(1)
        .where((l) => l.trim().endsWith('device'))
        .map((l) => l.split(RegExp(r'\s+')).first)
        .toList();
    if (ids.length != 1) throw StateError('нужно ровно одно устройство (--serial), найдено: ${ids.length}');
    return Adb(ids.single);
  }

  /// `adb shell` изредка зависает на ~20 с (USB) — к таймауту добавляется запас,
  /// зависший вызов повторяется один раз.
  static const _stall = Duration(seconds: 25);

  @override
  Future<ProcResult> run(List<String> args, {Duration timeout = const Duration(seconds: 30)}) async {
    final r = await _run(args, timeout + _stall);
    return r.code == -1 ? _run(args, timeout + _stall) : r;
  }

  Future<ProcResult> _run(List<String> args, Duration timeout) async {
    final p = await Process.start('adb', ['-s', serial, ...args]);
    final out = p.stdout.transform(_utf8).join();
    final err = p.stderr.transform(_utf8).join();
    final code = await p.exitCode.timeout(timeout, onTimeout: () {
      p.kill();
      return -1;
    });
    return ProcResult(code, await out, await err);
  }

  /// Поток logcat с текущего момента; каждая строка дописывается в [sink]
  /// (через [mask]). Если `adb logcat` оборвался (USB, перезапуск adb-сервера),
  /// он перезапускается с времени последней строки — ответ агента, пришедший во
  /// время перезапуска, не теряется (повтор строки безвреден: ответы по id).
  Future<Stream<String>> logcat(IOSink sink, {String Function(String) mask = _same}) async {
    await run(['logcat', '-c']);
    final out = StreamController<String>.broadcast();
    // Позиция: время последней строки и сколько строк с этим временем уже отдано.
    String? last;
    var sameTime = 0;
    Future<void> start() async {
      if (_stopped) return;
      final p = await Process.start(
          'adb', ['-s', serial, 'logcat', '-v', 'threadtime', if (last != null) ...['-T', last!]]);
      _logcat = p;
      // После перезапуска с `-T` повторяются строки с времени последней полученной:
      // пропускаем более ранние и уже отданные с тем же временем, иначе старый
      // маркер состояния сочтётся новым. Новые строки с тем же временем проходят.
      final replayFrom = last;
      var replaySkip = sameTime;
      _sub = p.stdout.transform(_utf8).transform(const LineSplitter()).listen((l) {
        if (_stopped) return;
        final t = _logTime.firstMatch(l)?[0];
        if (replayFrom != null) {
          if (t == null) {
            if (replaySkip >= 0) return; // заголовки logcat до первой новой строки
          } else if (replaySkip >= 0) {
            final c = t.compareTo(replayFrom);
            if (c < 0) return;
            if (c == 0 && replaySkip > 0) {
              replaySkip--;
              return;
            }
            replaySkip = -1;
          }
        }
        if (t != null) {
          sameTime = t == last ? sameTime + 1 : 1;
          last = t;
        }
        sink.writeln(mask(l));
        out.add(l);
      }, onError: (Object e) {
        if (!_stopped) sink.writeln('ITEST_RUNNER logcat error: $e');
      });
      unawaited(p.exitCode.then((code) async {
        if (_stopped) return;
        sink.writeln('ITEST_RUNNER logcat exited ($code), restarting');
        await Future<void>.delayed(const Duration(seconds: 2));
        await start();
      }));
    }

    await start();
    return out.stream;
  }

  static final _logTime = RegExp(r'^\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}');
  static String _same(String s) => s;

  Process? _logcat;
  StreamSubscription<String>? _sub;
  var _stopped = false;

  /// После вызова в sink больше ничего не пишется — его можно закрывать.
  Future<void> stopLogcat() async {
    _stopped = true;
    _logcat?.kill();
    await _sub?.cancel();
  }
}

/// logd режет длинные строки по байтам — кириллица может оборваться посередине.
const _utf8 = Utf8Decoder(allowMalformed: true);
