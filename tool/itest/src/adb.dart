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

/// Runs adb commands; replaced in tests.
abstract class Shell {
  Future<ProcResult> run(List<String> args, {Duration timeout = const Duration(seconds: 30)});
}

/// Single quotes for the device shell.
String shQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";

class Adb implements Shell {
  final String serial;

  Adb(this.serial);

  /// Serial from the argument, ANDROID_SERIAL or the single connected device.
  static Future<Adb> connect([String? serial]) async {
    serial ??= Platform.environment['ANDROID_SERIAL'];
    if (serial != null && serial.isNotEmpty) return Adb(serial);
    final r = await Process.run('adb', ['devices']);
    final ids = LineSplitter.split(
      r.stdout as String,
    ).skip(1).where((l) => l.trim().endsWith('device')).map((l) => l.split(RegExp(r'\s+')).first).toList();
    if (ids.length != 1) throw StateError('exactly one device is required (--serial), found: ${ids.length}');
    return Adb(ids.single);
  }

  /// `adb shell` occasionally hangs for ~20 s (USB) — a margin is added to the timeout,
  /// a hung call is retried once.
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
    final code = await p.exitCode.timeout(
      timeout,
      onTimeout: () {
        p.kill();
        return -1;
      },
    );
    return ProcResult(code, await out, await err);
  }

  /// logcat stream from the current moment; every line is appended to [sink]
  /// (through [mask]). If `adb logcat` broke off (USB, adb server restart),
  /// it restarts from the time of the last line — an agent response that arrived during
  /// the restart isn't lost (a repeated line is harmless: responses are matched by id).
  Future<Stream<String>> logcat(IOSink sink, {String Function(String) mask = _same}) async {
    await run(['logcat', '-c']);
    final out = StreamController<String>.broadcast();
    // Position: time of the last line and how many lines with that time were already emitted.
    String? last;
    var sameTime = 0;
    Future<void> start() async {
      if (_stopped) return;
      final p = await Process.start('adb', [
        '-s',
        serial,
        'logcat',
        '-v',
        'threadtime',
        if (last != null) ...['-T', last!],
      ]);
      _logcat = p;
      // After a restart with `-T` lines from the time of the last received one repeat:
      // skip earlier ones and those already emitted with the same time, otherwise an old
      // state marker would be taken as new. New lines with the same time pass.
      final replayFrom = last;
      var replaySkip = sameTime;
      _sub = p.stdout
          .transform(_utf8)
          .transform(const LineSplitter())
          .listen(
            (l) {
              if (_stopped) return;
              final t = _logTime.firstMatch(l)?[0];
              if (replayFrom != null) {
                if (t == null) {
                  if (replaySkip >= 0) return; // logcat headers before the first new line
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
            },
            onError: (Object e) {
              if (!_stopped) sink.writeln('ITEST_RUNNER logcat error: $e');
            },
          );
      unawaited(
        p.exitCode.then((code) async {
          if (_stopped) return;
          sink.writeln('ITEST_RUNNER logcat exited ($code), restarting');
          await Future<void>.delayed(const Duration(seconds: 2));
          await start();
        }),
      );
    }

    await start();
    return out.stream;
  }

  static final _logTime = RegExp(r'^\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}');
  static String _same(String s) => s;

  Process? _logcat;
  StreamSubscription<String>? _sub;
  var _stopped = false;

  /// After the call nothing more is written to the sink — it can be closed.
  Future<void> stopLogcat() async {
    _stopped = true;
    _logcat?.kill();
    await _sub?.cancel();
  }
}

/// logd cuts long lines by bytes — Cyrillic can break in the middle.
const _utf8 = Utf8Decoder(allowMalformed: true);
