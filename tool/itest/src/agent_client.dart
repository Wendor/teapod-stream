import 'dart:async';
import 'dart:convert';

import 'adb.dart';

const itestPackage = 'com.teapodstream.teapodstream.itest';
const _activity = 'com.teapodstream.teapodstream.MainActivity';
const _prefix = 'TEAPOD_ITEST {';

class ItestTimeout implements Exception {
  final String message;
  ItestTimeout(this.message);
  @override
  String toString() => 'ItestTimeout: $message';
}

class ItestAgentError implements Exception {
  final String message;
  ItestAgentError(this.message);
  @override
  String toString() => 'ItestAgentError: $message';
}

typedef AgentState = ({String state, DateTime t});

/// Клиент агента itest-сборки: команды через `am start`, ответы и состояния —
/// из logcat-маркеров `TEAPOD_ITEST`.
class AgentClient {
  final Shell shell;
  final String pkg;
  final _replies = <String, Completer<Map<String, dynamic>>>{};
  final _states = StreamController<AgentState>.broadcast();
  var _seq = 0;

  /// Последнее состояние VPN по нативному маркеру.
  String? lastState;

  /// Маркер последнего `connected` (содержит socksPort/socksUser/socksPassword).
  Map<String, dynamic>? lastConnected;

  AgentClient(this.shell, Stream<String> logcat, {this.pkg = itestPackage}) {
    logcat.listen(_onLine);
  }

  Stream<AgentState> get states => _states.stream;

  void _onLine(String line) {
    final i = line.indexOf(_prefix);
    if (i < 0) return;
    final Map<String, dynamic> m;
    try {
      m = jsonDecode(line.substring(i + _prefix.length - 1)) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (m['ev'] == 'state') {
      lastState = m['value'] as String;
      if (lastState == 'connected') lastConnected = m;
      _states.add((state: lastState!, t: DateTime.now()));
    } else if (m['id'] is String) {
      _replies.remove(m['id'])?.complete(m);
    }
  }

  Future<Object?> send(String op,
      [Map<String, dynamic> args = const {}, Duration timeout = const Duration(seconds: 30)]) async {
    final id = '${++_seq}-${DateTime.now().millisecondsSinceEpoch}';
    final reply = Completer<Map<String, dynamic>>();
    _replies[id] = reply;
    final cmd = jsonEncode({'id': id, 'op': op, ...args});
    // Повтор, если вызов не завершился (Adb сам повторяет зависшие вызовы, это
    // страховка для других Shell).
    final am = ['shell', 'am start -n $pkg/$_activity -a com.teapodstream.ITEST --es cmd ${shQuote(cmd)}'];
    if ((await shell.run(am, timeout: const Duration(seconds: 15))).code == -1) {
      await shell.run(am, timeout: const Duration(seconds: 15));
    }
    var m = await reply.future.timeout(timeout, onTimeout: () {
      _replies.remove(id);
      throw ItestTimeout('$op: нет ответа агента за ${timeout.inSeconds} с');
    });
    if (m['file'] is String) {
      final file = m['file'];
      final r = await shell.run(['shell', 'run-as $pkg cat $file']);
      if (!r.ok) throw ItestAgentError('$op: не прочитан $file (${r.code})');
      m = jsonDecode(r.out) as Map<String, dynamic>;
      // Удаляем только прочитанный файл; сбой очистки ответу не мешает.
      unawaited(shell.run(['shell', 'run-as $pkg rm -f $file']).then((_) {}, onError: (_) {}));
    }
    if (m['ok'] != true) throw ItestAgentError('$op: ${m['error']}');
    return m['data'];
  }

  /// Ждёт состояние из [targets]; если оно уже текущее — сразу.
  Future<String> waitState(Set<String> targets, Duration timeout) async {
    if (targets.contains(lastState)) return lastState!;
    final s = await states.firstWhere((s) => targets.contains(s.state)).timeout(timeout,
        onTimeout: () => throw ItestTimeout('нет состояния $targets за ${timeout.inSeconds} с (сейчас $lastState)'));
    return s.state;
  }
}
