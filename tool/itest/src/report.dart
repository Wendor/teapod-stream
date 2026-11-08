import 'dart:convert';
import 'dart:io';

import 'matrix.dart';
import 'probes.dart';
import 'soak.dart';

/// Каталог прогона `runs/<YYYY-MM-DD_HH-MM-SS>/`.
class RunDir {
  final Directory root;

  RunDir(this.root) {
    root.createSync(recursive: true);
  }

  factory RunDir.create(String base) {
    final t = DateTime.now().toIso8601String().substring(0, 19).replaceAll('T', '_').replaceAll(':', '-');
    return RunDir(Directory('$base/$t'));
  }

  Directory caseDir(String id) =>
      Directory('${root.path}/cases/${id.replaceAll(RegExp(r'[^\w.\-/]'), '_').replaceAll('..', '_')}')
        ..createSync(recursive: true);

  Directory soakDir(String core) => Directory('${root.path}/soak/$core')..createSync(recursive: true);

  File file(String name) => File('${root.path}/$name');

  String relative(FileSystemEntity e) => e.path.substring(root.path.length + 1);
}

/// Маскирует креды в URI, ключи в query, UUID и токены подписок.
String maskSecrets(String s) => s
    .replaceAllMapped(RegExp(r'([a-z][a-z0-9+.\-]*://)[^@\s/]+@', caseSensitive: false), (m) => '${m[1]}***@')
    .replaceAllMapped(
        RegExp(r'\b(pbk|sid|pqv|password|publickey|privatekey|key|token|auth)=[^&\s#]+', caseSensitive: false),
        (m) => '${m[1]}=***')
    .replaceAll(RegExp(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', caseSensitive: false), '***')
    .replaceAllMapped(RegExp(r'(/sub/)[^\s/?#]+'), (m) => '${m[1]}***');

/// Отчёт прогона; пишется после каждого результата, чтобы прерванный прогон
/// оставлял актуальный `report.md`.
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

  /// Замечание о прогоне (что не проверено и почему).
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
    if (error != null) b.writeln('\n**Прогон прерван ошибкой:** $error');
    if (notes.isNotEmpty) b.writeln('\n**Замечания:**\n${notes.map((n) => '- $n').join('\n')}');
    final count = <Verdict, int>{};
    for (final v in [...cases.map((c) => c.verdict), ...faults.map((f) => f.r.verdict)]) {
      count[v] = (count[v] ?? 0) + 1;
    }
    b.writeln('\n**Итог:** ${Verdict.values.map((v) => '${v.name.toUpperCase()} ${count[v] ?? 0}').join(' · ')}');
    if (cases.isNotEmpty) {
      b.writeln('\n## Matrix\n\n| id | verdict | note | took |\n|---|---|---|---|');
      for (final c in cases) {
        b.writeln('| [${c.id}](${c.dir}/) | ${c.verdict.name.toUpperCase()} | ${c.note.replaceAll('|', '/')} '
            '| ${c.took.inSeconds}s |');
      }
    }
    if (faults.isNotEmpty) {
      b.writeln('\n## Soak\n\n| время | ядро | сбой | verdict | восстановление | note |\n|---|---|---|---|---|---|');
      for (final (:core, :r) in faults) {
        b.writeln('| ${r.at.toIso8601String().substring(11, 19)} | $core | ${r.fault.cli} '
            '| ${r.verdict.name.toUpperCase()} | ${r.recovery == null ? '—' : '${r.recovery!.inSeconds}s'} | ${r.note} |');
      }
      b.writeln('\nТаймлайн проб: `soak/<ядро>/timeline.jsonl`, снимки провалов: `soak/<ядро>/fault-*`.');
    }
    final failed = cases.where((c) => c.verdict == Verdict.fail || c.verdict == Verdict.zombie);
    final badFaults = faults.where((f) => f.r.verdict == Verdict.fail || f.r.verdict == Verdict.zombie);
    if (failed.isNotEmpty || badFaults.isNotEmpty) {
      b.writeln('\n## Перезапуск провалов\n\n```bash');
      for (final c in failed) {
        b.writeln("dart run tool/itest/main.dart --skip-install --phase matrix --case '${c.id.replaceAll("'", r"'\''")}'");
      }
      for (final f in badFaults.map((f) => '${f.core}|${f.r.fault.cli}').toSet()) {
        final [core, fault] = f.split('|');
        b.writeln('dart run tool/itest/main.dart --skip-install --phase soak --core $core --fault $fault --repeat 3 --duration 2h');
      }
      b.writeln('```');
    }
    b.writeln('\n> VPN основного приложения отключён тестами — подключите его вручную.');
    return maskSecrets(b.toString());
  }
}
