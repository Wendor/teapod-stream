import '../../../tool/itest/src/adb.dart';

/// Записывает команды; ответ — по первому совпавшему префиксу из [replies].
class FakeShell implements Shell {
  final calls = <String>[];
  final Map<String, String> replies;

  /// Коды выхода по очереди (−1 — таймаут); пусто — 0.
  final List<int> codes;

  FakeShell([this.replies = const {}, List<int>? codes]) : codes = codes ?? [];

  @override
  Future<ProcResult> run(List<String> args, {Duration timeout = const Duration(seconds: 30)}) async {
    final cmd = args.join(' ');
    calls.add(cmd);
    if (codes.isNotEmpty) return ProcResult(codes.removeAt(0), '', '');
    for (final e in replies.entries) {
      if (cmd.contains(e.key)) return ProcResult(0, e.value, '');
    }
    return const ProcResult(0, '', '');
  }
}
