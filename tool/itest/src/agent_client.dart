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

/// itest build agent client: commands via `am start`, responses and states —
/// from `TEAPOD_ITEST` logcat markers.
class AgentClient {
  final Shell shell;
  final String pkg;
  final _replies = <String, Completer<Map<String, dynamic>>>{};
  final _states = StreamController<AgentState>.broadcast();
  var _seq = 0;

  /// The last VPN state from the native marker.
  String? lastState;

  /// The last `connected` marker (contains socksPort/socksUser/socksPassword).
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
    // Retry if the call didn't finish (Adb retries hung calls itself, this
    // is a safeguard for other Shells).
    final am = ['shell', 'am start -n $pkg/$_activity -a com.teapodstream.ITEST --es cmd ${shQuote(cmd)}'];
    if ((await shell.run(am, timeout: const Duration(seconds: 15))).code == -1) {
      await shell.run(am, timeout: const Duration(seconds: 15));
    }
    var m = await reply.future.timeout(timeout, onTimeout: () {
      _replies.remove(id);
      throw ItestTimeout('$op: no agent response within ${timeout.inSeconds} s');
    });
    if (m['file'] is String) {
      final file = m['file'];
      final r = await shell.run(['shell', 'run-as $pkg cat $file']);
      if (!r.ok) throw ItestAgentError('$op: $file not read (${r.code})');
      m = jsonDecode(r.out) as Map<String, dynamic>;
      // Delete only the read file; a cleanup failure doesn't affect the response.
      unawaited(shell.run(['shell', 'run-as $pkg rm -f $file']).then((_) {}, onError: (_) {}));
    }
    if (m['ok'] != true) throw ItestAgentError('$op: ${m['error']}');
    return m['data'];
  }

  /// Waits for a state from [targets]; if it is already current — right away.
  Future<String> waitState(Set<String> targets, Duration timeout) async {
    if (targets.contains(lastState)) return lastState!;
    final s = await states.firstWhere((s) => targets.contains(s.state)).timeout(timeout,
        onTimeout: () => throw ItestTimeout('no state $targets within ${timeout.inSeconds} s (now $lastState)'));
    return s.state;
  }
}
