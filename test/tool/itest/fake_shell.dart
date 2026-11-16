import '../../../tool/itest/src/adb.dart';

/// Records commands; the answer is by the first matching prefix from [replies].
class FakeShell implements Shell {
  final calls = <String>[];
  final Map<String, String> replies;

  /// Exit codes in turn (−1 — timeout); empty — 0.
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
