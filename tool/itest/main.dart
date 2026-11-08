// Интеграционные тесты на устройстве: dart run tool/itest/main.dart --help
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'src/adb.dart';
import 'src/agent_client.dart';
import 'src/device_guard.dart';
import 'src/matrix.dart';
import 'src/probes.dart';
import 'src/report.dart';
import 'src/secrets.dart';
import 'src/soak.dart';

Duration parseDuration(String s) {
  final m = RegExp(r'^(\d+)(s|m|h)$').firstMatch(s);
  if (m == null) throw FormatException('длительность вида 30s / 15m / 2h: $s');
  final n = int.parse(m[1]!);
  return switch (m[2]) { 's' => Duration(seconds: n), 'm' => Duration(minutes: n), _ => Duration(hours: n) };
}

Future<void> main(List<String> argv) async {
  // Любая необработанная ошибка (в т.ч. асинхронная) должна дойти до finalize —
  // иначе телефон останется в режиме самолёта / Doze.
  await runZonedGuarded(() => _main(argv), (e, st) async {
    stderr.writeln('✗ необработанная ошибка: $e\n$st');
    await _finalize?.call();
    exit(1);
  });
}

Future<void> Function()? _finalize;

Future<void> _main(List<String> argv) async {
  final parser = ArgParser()
    ..addOption('phase', allowed: ['matrix', 'soak', 'all'], defaultsTo: 'all')
    ..addOption('config', help: 'glob по имени конфига')
    ..addOption('core', help: 'xray-core | xray-rust | sing-box (glob)')
    ..addOption('case', help: 'glob по id кейса, напр. opt/*/split-*')
    ..addOption('fault', help: 'soak: ${Fault.values.map((f) => f.cli).join(', ')}')
    ..addOption('repeat', defaultsTo: '1')
    ..addOption('duration', defaultsTo: '1h', help: 'soak: на каждое ядро')
    ..addOption('probe-interval', defaultsTo: '20s')
    ..addOption('serial')
    ..addOption('secrets', defaultsTo: 'tool/itest/secrets.json')
    ..addFlag('list', negatable: false, help: 'показать кейсы без запуска')
    ..addFlag('skip-install', negatable: false, help: 'не пересобирать itest-APK')
    ..addFlag('help', abbr: 'h', negatable: false);
  final args = parser.parse(argv);
  if (args.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }

  final secrets = Secrets.load(args.option('secrets')!);
  final adb = await Adb.connect(args.option('serial'));
  if (!args.flag('skip-install') && !args.flag('list')) {
    final r = await Process.start('./build.sh', ['itest'],
        mode: ProcessStartMode.inheritStdio, environment: {'ANDROID_SERIAL': adb.serial});
    if (await r.exitCode != 0) throw StateError('./build.sh itest завершился с ошибкой');
  }

  final run = RunDir.create('runs');
  final logSink = run.file('logcat.txt').openWrite();
  final logcat = await adb.logcat(logSink);
  final agent = AgentClient(adb, logcat);
  final device = DeviceGuard(adb);
  final probes = Probes(adb);
  final report = RunReport(run);
  stdout.writeln('▶ прогон: ${run.root.path}');

  // Один раз; повторный вызов (второй Ctrl+C, ошибка) ждёт тот же откат.
  // Сначала телефон (restore также запрещает новые сбои), потом остальное.
  Future<void>? finalizing;
  Future<void> finalize() => finalizing ??= () async {
        await device.restore();
        try {
          await agent.send('disconnect', const {}, const Duration(seconds: 5));
        } catch (_) {}
        await device.parkApp();
        report.write();
        await adb.stopLogcat();
        await logSink.close();
        stdout.writeln('▶ отчёт: ${run.file('report.md').path}');
      }();
  _finalize = finalize;

  final sigint = ProcessSignal.sigint.watch().listen((_) async {
    stdout.writeln('\n▶ прерывание — возвращаю телефон в исходное состояние (подождите)');
    await finalize();
    exit(130);
  });

  try {
    await device.snapshot();
    await device.screen(true);
    report.meta = await collectMeta(adb, agent);
    await device.stayAwake(true);

    final imported = await importAll(agent, secrets, report);
    final configs = imported.configs;
    stdout.writeln('▶ конфигов: ${configs.length}');

    String? glob(String name) => args.option(name);
    var cases = buildMatrix(configs,
        owned: imported.owned, configGlob: glob('config'), coreGlob: glob('core'), caseGlob: glob('case'));
    if (args.flag('list')) {
      final all = buildMatrix(configs,
          owned: imported.owned,
          reference: {for (final c in coreNames.keys) c: '?'},
          configGlob: glob('config'),
          coreGlob: glob('core'),
          caseGlob: glob('case'));
      for (final c in all) {
        stdout.writeln(c.id);
      }
      stdout.writeln('opt-кейсы — на опорном конфиге каждого ядра');
      return;
    }

    // Чужой VPN (например, основного приложения) исказил бы baseline: подключение
    // itest-VPN его вытесняет.
    if (configs.isNotEmpty && configs.first.cores.isNotEmpty) {
      try {
        await agent.send('connect', {'configId': configs.first.id, 'core': configs.first.cores.first});
        await agent.waitState({'connected', 'error', 'blocked'}, const Duration(seconds: 60));
      } catch (_) {}
      await agent.send('disconnect');
      await agent.waitState({'disconnected', 'error'}, const Duration(seconds: 15)).catchError((_) => '');
    }
    final baseline = await measureBaseline(probes);
    report.baseline = baseline;
    run.file('baseline.json').writeAsStringSync(jsonEncode(baseline.toJson()));
    stdout.writeln('▶ baseline: ${baseline.toJson()}');
    if (baseline.direct.values.every((v) => v == null)) throw StateError('нет интернета без VPN — прогон невозможен');

    CaseCtx ctxFor(String configId) => CaseCtx(agent, probes, baseline, device, imported.egress[configId],
        strictEgress: imported.strict.contains(configId));

    final reference = <String, String>{};
    if (args.option('phase') != 'soak') {
      final base = cases.where((c) => c.id.startsWith('base/')).toList();
      for (final mc in base) {
        report.add(await runCase(mc, ctxFor(mc.configId), run, adb, logcat));
      }
      reference.addAll(pickReference(configs, imported.owned, secrets.reference, report.cases));
      for (final core in coreNames.keys) {
        final ranBase = report.cases.any((c) => c.id.startsWith('base/${coreNames[core]}/'));
        if (!reference.containsKey(core) && ranBase) {
          report.note('opt/soak ${coreNames[core]}: пропущены — нет опорного конфига (ни один owned не прошёл base)');
        }
      }
      final opt = buildMatrix(configs,
              owned: imported.owned,
              reference: reference,
              configGlob: glob('config'),
              coreGlob: glob('core'),
              caseGlob: glob('case'))
          .where((c) => c.id.startsWith('opt/'));
      for (final mc in opt) {
        report.add(await runCase(mc, ctxFor(mc.configId), run, adb, logcat));
      }
    } else {
      reference.addAll(pickReference(configs, imported.owned, secrets.reference, const []));
    }

    if (args.option('phase') != 'matrix') {
      final faults = args.option('fault') == null
          ? Fault.values.where((f) => f != Fault.idle).toList()
          : [Fault.fromCli(args.option('fault')!)];
      for (final MapEntry(key: core, value: configId) in reference.entries) {
        if (glob('core') != null && !globMatch(glob('core')!, coreNames[core]!)) continue;
        final soak = Soak(
          agent: agent,
          probes: probes,
          device: device,
          baseline: baseline,
          shell: adb,
          dir: run.soakDir(coreNames[core]!),
          logcat: logcat,
          configId: configId,
          core: core,
          egress: imported.egress[configId],
          faults: faults,
          repeat: int.parse(args.option('repeat')!),
          duration: parseDuration(args.option('duration')!),
          probeInterval: parseDuration(args.option('probe-interval')!),
          onResult: (r) {
            report.addFault(coreNames[core]!, r);
            stdout.writeln('  ${coreNames[core]} ${r.fault.cli}: ${r.verdict.name} ${r.note}');
          },
        );
        stdout.writeln('▶ soak ${coreNames[core]}');
        await soak.run();
      }
    }
  } catch (e, st) {
    stderr.writeln('✗ $e\n$st');
    report.error = '$e';
    exitCode = 1;
  } finally {
    await finalize();
    await sigint.cancel();
  }
}

typedef Imported = ({
  List<AgentConfig> configs,
  Map<String, bool> owned,
  Map<String, String?> egress,
  Set<String> strict,
});

/// Загружает тестовые подключения в itest-приложение по одному: так видно,
/// какой конфиг откуда (owned / egressIp).
Future<Imported> importAll(AgentClient agent, Secrets s, RunReport report) async {
  await agent.send('reset');
  final owned = <String, bool>{};
  final egress = <String, String?>{};
  Future<Set<String>> ids() async => {for (final m in (await agent.send('list') as List)) (m as Map)['id'] as String};
  for (final c in s.configs) {
    final before = await ids();
    final r = await agent.send('import', {'uris': [c.uri]}, const Duration(seconds: 60)) as Map;
    for (final f in r['failed'] as List) {
      report.note('import: конфиг #${s.configs.indexOf(c)} не разобран ($f)');
    }
    for (final id in (await ids()).difference(before)) {
      owned[id] = c.owned;
      egress[id] = c.egressIp;
    }
  }
  for (final sub in s.subs) {
    final before = await ids();
    final r = await agent.send('import', {'subs': [sub.url]}, const Duration(seconds: 90)) as Map;
    for (final f in r['failed'] as List) {
      report.note('import: подписка #${s.subs.indexOf(sub)}${sub.owned ? '' : ' (не своя)'} — $f');
    }
    for (final id in (await ids()).difference(before)) {
      owned[id] = sub.owned;
    }
  }
  final configs = (await agent.send('list') as List).cast<Map<String, dynamic>>().map(agentConfigFromJson).toList()
    ..removeWhere((c) => s.exclude.any((g) => globMatch(g, '${c.host}:${c.port}')));
  // Без явного egressIp ожидаемый выход — IP хоста сервера (подсказка, не строго).
  final strict = {for (final e in egress.entries) if (e.value != null) e.key};
  for (final c in configs) {
    if (egress[c.id] != null) continue;
    try {
      egress[c.id] = (await InternetAddress.lookup(c.host, type: InternetAddressType.IPv4)).first.address;
    } catch (_) {}
  }
  return (configs: configs, owned: owned, egress: egress, strict: strict);
}

/// Опорный конфиг ядра: из secrets.reference по имени, иначе первый owned с PASS в base.
Map<String, String> pickReference(
    List<AgentConfig> configs, Map<String, bool> owned, Map<String, String> byName, List<CaseResult> results) {
  final out = <String, String>{};
  for (final core in coreNames.keys) {
    final named = byName[core];
    final pinned = configs.where((c) => c.name == named && c.cores.contains(core)).firstOrNull;
    final passed = configs.where((c) =>
        owned[c.id] == true &&
        c.cores.contains(core) &&
        results.any((r) => r.id.startsWith('base/${coreNames[core]}/${c.name}') && r.verdict == Verdict.pass));
    final ref = pinned ?? passed.firstOrNull ?? (results.isEmpty ? configs.where((c) => owned[c.id] == true && c.cores.contains(core)).firstOrNull : null);
    if (ref != null) out[core] = ref.id;
  }
  return out;
}

Future<Map<String, Object?>> collectMeta(Shell shell, AgentClient agent) async {
  Future<String> sh(String c) async => (await shell.run(['shell', c])).out.trim();
  final git = await Process.run('git', ['rev-parse', '--short', 'HEAD']);
  final ping = await agent.send('ping', const {}, const Duration(seconds: 60)) as Map;
  return {
    'started': DateTime.now().toIso8601String(),
    'app': ping['version'],
    'cores': ping['cores'],
    'git': (git.stdout as String).trim(),
    'device': await sh('getprop ro.product.model'),
    'android': await sh('getprop ro.build.version.release'),
  };
}
