import 'dart:convert';
import 'dart:io';

import 'matrix.dart';
import 'probes.dart';
import 'soak.dart';

/// Run directory `runs/<YYYY-MM-DD_HH-MM-SS>/`.
class RunDir {
  final Directory root;

  RunDir(this.root) {
    root.createSync(recursive: true);
  }

  factory RunDir.create(String base) {
    final t = DateTime.now().toIso8601String().substring(0, 19).replaceAll('T', '_').replaceAll(':', '-');
    return RunDir(Directory('$base/$t'));
  }

  final _caseDirs = <String, Directory>{};

  /// Case directory; different ids that match after normalization get a suffix.
  Directory caseDir(String id) => _caseDirs[id] ??= () {
        final base = '${root.path}/cases/${id.replaceAll(RegExp(r'[^\w.\-/]'), '_').replaceAll('..', '_')}';
        final taken = _caseDirs.values.map((d) => d.path).toSet();
        var path = base;
        for (var i = 2; taken.contains(path); i++) {
          path = '$base-$i';
        }
        return Directory(path)..createSync(recursive: true);
      }();

  Directory soakDir(String core) => Directory('${root.path}/soak/$core')..createSync(recursive: true);

  File file(String name) => File('${root.path}/$name');

  String relative(FileSystemEntity e) => e.path.substring(root.path.length + 1);
}

/// Masks credentials in URIs, keys in queries, UUIDs and subscription tokens.
String maskSecrets(String s) => s
    .replaceAllMapped(RegExp(r'([a-z][a-z0-9+.\-]*://)[^@\s/"]+@', caseSensitive: false), (m) => '${m[1]}***@')
    .replaceAllMapped(
        // Value up to the URL separator; JSON escaping (\" and \\) is part of the value.
        RegExp(r'\b(pbk|sid|pqv|password|publickey|privatekey|key|token|auth)=(?:\\.|[^&\s#"\\])+',
            caseSensitive: false),
        (m) => '${m[1]}=***')
    .replaceAll(RegExp(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', caseSensitive: false), '***')
    .replaceAllMapped(RegExp(r'(/sub/)(?:\\.|[^\s/?#"\\])+'), (m) => '${m[1]}***')
    // Agent JSON markers (e.g. `connected` carries socksPassword).
    .replaceAllMapped(
        RegExp(r'"(\w*(?:password|pass|token|key|auth|user))"\s*:\s*"(?:\\.|[^"\\])*"', caseSensitive: false),
        (m) => '"${m[1]}":"***"');

/// Run report; written after every result so an interrupted run
/// leaves an up-to-date `report.md`.
class RunReport {
  final RunDir run;
  final cases = <CaseResult>[];
  final faults = <({String core, FaultResult r})>[];
  final notes = <String>[];
  Map<String, Object?> meta = const {};
  Baseline? baseline;
  String? error;

  RunReport(this.run);

  void add(CaseResult r) {
    cases.add(r);
    stdout.writeln('  ${r.verdict.name.toUpperCase().padRight(6)} ${r.id}  ${maskSecrets(r.note)}');
    write();
  }

  /// A note about the run (what wasn't checked and why).
  void note(String text) {
    notes.add(text);
    stdout.writeln('  ! ${maskSecrets(text)}');
    write();
  }

  void addFault(String core, FaultResult r) {
    faults.add((core: core, r: r));
    write();
  }

  void write() {
    run.file('report.md').writeAsStringSync(render());
    run.file('report.json').writeAsStringSync(maskSecrets(jsonEncode({
      'meta': meta,
      'baseline': baseline?.toJson(),
      'error': error,
      'notes': notes,
      'cases': [for (final c in cases) c.toJson()],
      'soak': [for (final f in faults) {'core': f.core, ...f.r.toJson()}],
    })));
  }

  String render() {
    final b = StringBuffer('# itest ${meta['started'] ?? ''}\n\n');
    meta.forEach((k, v) => b.writeln('- **$k:** $v'));
    if (baseline != null) b.writeln('- **baseline:** ${jsonEncode(baseline!.toJson())}');
    if (error != null) b.writeln('\n**Run aborted by an error:** $error');
    if (notes.isNotEmpty) b.writeln('\n**Notes:**\n${notes.map((n) => '- $n').join('\n')}');
    final count = <Verdict, int>{};
    for (final v in [...cases.map((c) => c.verdict), ...faults.map((f) => f.r.verdict)]) {
      count[v] = (count[v] ?? 0) + 1;
    }
    b.writeln('\n**Total:** ${Verdict.values.map((v) => '${v.name.toUpperCase()} ${count[v] ?? 0}').join(' · ')}');
    if (cases.isNotEmpty) {
      b.writeln('\n## Matrix\n\n| id | verdict | note | took |\n|---|---|---|---|');
      for (final c in cases) {
        b.writeln('| [${c.id}](${c.dir}/) | ${c.verdict.name.toUpperCase()} | ${c.note.replaceAll('|', '/')} '
            '| ${c.took.inSeconds}s |');
      }
    }
    if (faults.isNotEmpty) {
      b.writeln('\n## Soak\n\n| time | core | fault | verdict | recovery | note |\n|---|---|---|---|---|---|');
      for (final (:core, :r) in faults) {
        b.writeln('| ${r.at.toIso8601String().substring(11, 19)} | $core | ${r.fault.cli} '
            '| ${r.verdict.name.toUpperCase()} | ${r.recovery == null ? '—' : '${r.recovery!.inSeconds}s'} | ${r.note} |');
      }
      b.writeln('\nProbe timeline: `soak/<core>/timeline.jsonl`, failure snapshots: `soak/<core>/fault-*`.');
    }
    final failed = cases.where((c) => c.verdict == Verdict.fail || c.verdict == Verdict.zombie);
    final badFaults = faults.where((f) => f.r.verdict == Verdict.fail || f.r.verdict == Verdict.zombie);
    if (failed.isNotEmpty || badFaults.isNotEmpty) {
      b.writeln('\n## Rerun failures\n\n```bash');
      for (final c in failed) {
        b.writeln("dart run tool/itest/main.dart --skip-install --phase matrix --case '${c.id.replaceAll("'", r"'\''")}'");
      }
      for (final f in badFaults.map((f) => '${f.core}|${f.r.fault.cli}').toSet()) {
        final [core, fault] = f.split('|');
        b.writeln('dart run tool/itest/main.dart --skip-install --phase soak --core $core --fault $fault --repeat 3 --duration 2h');
      }
      b.writeln('```');
    }
    b.writeln('\n> The main app VPN was disconnected by the tests — reconnect it manually.');
    return maskSecrets(b.toString());
  }
}
