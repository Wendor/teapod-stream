import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'adb.dart';
import 'agent_client.dart';
import 'device_guard.dart';
import 'matrix.dart' show collectDiag, dumpGoroutines;
import 'probes.dart';
import 'report.dart' show maskSecrets;

enum Fault {
  wifiLte('wifi-lte'),
  offline10s('offline-10s'),
  offline1m('offline-1m'),
  offline5m('offline-5m'),
  doze('doze'),
  killApp('kill'),
  idle('idle');

  const Fault(this.cli);

  final String cli;

  static Fault fromCli(String s) =>
      values.firstWhere((f) => f.cli == s, orElse: () => throw ArgumentError('неизвестный сбой: $s'));
}

typedef ProbeSample = ({DateTime t, bool ok, String? appState});

class FaultResult {
  final Fault fault;
  final Verdict verdict;
  final Duration? recovery;
  final String note;
  final DateTime at;

  FaultResult(this.fault, this.verdict, this.recovery, this.note, {DateTime? at}) : at = at ?? DateTime.now();

  Map<String, Object?> toJson() => {
        'fault': fault.cli,
        'verdict': verdict.name,
        'recoveryMs': recovery?.inMilliseconds,
        'note': note,
        'at': at.toIso8601String(),
      };
}

/// Восстановление после сбоя: трафик в пределах [failAfter] — pass; иначе
/// zombie, если приложение всё это время показывало connected, или fail.
FaultResult classifyRecovery({
  required Fault fault,
  required DateTime restoredAt,
  required List<ProbeSample> after,
  Duration failAfter = const Duration(minutes: 3),
  Duration zombieAfter = const Duration(minutes: 3),
}) {
  final ok = after.where((s) => s.ok && !s.t.isBefore(restoredAt)).firstOrNull;
  if (ok != null && ok.t.difference(restoredAt) <= failAfter) {
    final rec = ok.t.difference(restoredAt);
    return FaultResult(fault, Verdict.pass, rec, 'recovered in ${rec.inSeconds}s', at: restoredAt);
  }
  final failing = after.where((s) => !s.ok).toList();
  final connected = failing.reversed.takeWhile((s) => s.appState == 'connected').toList();
  if (connected.length > 1 && connected.first.t.difference(connected.last.t) >= zombieAfter) {
    return FaultResult(fault, Verdict.zombie, null,
        'connected without traffic for ${connected.first.t.difference(connected.last.t).inSeconds}s',
        at: restoredAt);
  }
  return FaultResult(fault, Verdict.fail, null,
      'no traffic ${failAfter.inSeconds}s after restore (state ${after.lastOrNull?.appState})',
      at: restoredAt);
}

/// Спокойный интервал: ≥ [minRun] проваленных проб подряд — отвал без причины.
FaultResult classifyIdle(List<ProbeSample> samples, {int minRun = 3}) {
  var run = <ProbeSample>[];
  for (var i = 0; i <= samples.length; i++) {
    final s = i < samples.length ? samples[i] : null;
    if (s != null && !s.ok) {
      run.add(s);
      continue;
    }
    if (run.length >= minRun) {
      final zombie = run.every((r) => r.appState == 'connected');
      final secs = run.last.t.difference(run.first.t).inSeconds;
      return FaultResult(Fault.idle, zombie ? Verdict.zombie : Verdict.fail, null,
          'outage ${secs}s from ${run.first.t.toIso8601String().substring(11, 19)}, '
          '${s == null ? 'not recovered' : 'recovered'} (state ${run.last.appState})',
          at: run.first.t);
    }
    run = [];
  }
  return FaultResult(Fault.idle, Verdict.pass, null, '${samples.length} probes ok',
      at: samples.firstOrNull?.t);
}

/// Долгий прогон одного ядра со сбоями.
class Soak {
  final AgentClient agent;
  final Probes probes;
  final DeviceGuard device;
  final Baseline baseline;
  final Shell shell;
  final Directory dir;
  final Stream<String> logcat;
  final String configId;
  final String core;
  final String? egress;
  final bool strictEgress;
  final List<Fault> faults;
  final int repeat;
  final Duration duration;
  final Duration probeInterval;
  final void Function(FaultResult) onResult;

  late final IOSink _timeline = File('${dir.path}/timeline.jsonl').openWrite();
  final _recent = ListQueue<String>();
  var _diagN = 0;
  var _onWifi = true;
  var _lteOk = true;

  Soak({
    required this.agent,
    required this.probes,
    required this.device,
    required this.baseline,
    required this.shell,
    required this.dir,
    required this.logcat,
    required this.configId,
    required this.core,
    required this.egress,
    this.strictEgress = false,
    required this.faults,
    required this.repeat,
    required this.duration,
    required this.probeInterval,
    required this.onResult,
  });

  void _event(String kind, [Map<String, Object?> extra = const {}]) =>
      _timeline.writeln(jsonEncode({'t': DateTime.now().toIso8601String(), 'kind': kind, ...extra}));

  /// [fast] — замер восстановления: без повтора и с коротким таймаутом,
  /// чтобы время восстановления не включало ретраи упавших попыток.
  Future<ProbeSample> _probe({bool fast = false}) async {
    // Различимый сервис: ответ ≠ его прямому IP; иначе достаточно любого ответа.
    final urls = egress != null && egress == baseline.directRuIp ? const <String>[] : informative(baseline.direct, egress);
    final url = urls.isEmpty ? echoMain.first : urls.first;
    Future<String?> get(String u) =>
        fast ? probes.ip(u, timeout: const Duration(seconds: 5), retries: 0) : probes.ip(u);
    var (u, ip) = (url, await get(url));
    if (ip == null && urls.length > 1) (u, ip) = (urls[1], await get(urls[1]));
    // Вне Wi-Fi из baseline прямой IP другой — «не прямой» ещё не значит «через VPN».
    final byEgress = egress != null && (strictEgress || !_onWifi);
    final ok = ip != null && (byEgress ? ip == egress : urls.isEmpty || ip != baseline.direct[u]);
    final s = (t: DateTime.now(), ok: ok, appState: agent.lastState);
    _event('probe', {'ip': ip, 'ok': ok, 'onWifi': _onWifi, 'state': agent.lastState});
    return s;
  }

  /// Пробы каждые [probeInterval] в течение [d]; [untilOk] — до первой успешной.
  Future<List<ProbeSample>> _sample(Duration d, {bool untilOk = false}) async {
    final out = <ProbeSample>[];
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      final s = await _probe(fast: untilOk);
      out.add(s);
      if (untilOk && s.ok) break;
      await Future<void>.delayed(untilOk ? const Duration(seconds: 2) : probeInterval);
    }
    return out;
  }

  Future<bool> _connect() async {
    agent.lastState = null;
    try {
      await agent.send('reset', {'keepConfigs': true});
      await agent.send('connect', {'configId': configId, 'core': core});
      return await agent.waitState({'connected', 'error', 'blocked'}, const Duration(seconds: 60)) == 'connected';
    } catch (e) {
      _event('note', {'text': 'connect: $e'});
      return false;
    }
  }

  Future<void> _reconnect() async {
    try {
      await agent.send('disconnect', const {}, const Duration(seconds: 60));
      await agent.waitState({'disconnected', 'error'}, const Duration(seconds: 15));
    } catch (_) {}
    _event('note', {'text': 'forced reconnect: ${await _connect()}'});
  }

  Future<void> _diag(FaultResult r) async {
    final d = Directory('${dir.path}/fault-${++_diagN}-${r.fault.cli}')..createSync(recursive: true);
    await dumpGoroutines(agent, d, (e) => _event('note', {'text': e}));
    await collectDiag(shell, d);
    File('${d.path}/logcat.txt').writeAsStringSync('${maskSecrets(_recent.join('\n'))}\n');
    File('${d.path}/result.json').writeAsStringSync(jsonEncode(r.toJson()));
  }

  void _report(FaultResult r) {
    _event('result', r.toJson());
    onResult(r);
  }

  /// Возвращает момент восстановления сети.
  Future<DateTime> _inject(Fault f) async {
    _event('fault-start', {'fault': f.cli});
    _onWifi = false;
    switch (f) {
      case Fault.wifiLte:
        await device.wifi(false);
        _lteOk = (await _sample(const Duration(minutes: 1))).any((s) => s.ok);
        await device.wifi(true);
      case Fault.offline10s || Fault.offline1m || Fault.offline5m:
        await device.airplane(true);
        await Future<void>.delayed(switch (f) {
          Fault.offline10s => const Duration(seconds: 10),
          Fault.offline1m => const Duration(minutes: 1),
          _ => const Duration(minutes: 5),
        });
        await device.airplane(false);
      case Fault.doze:
        await device.whitelist(itestPackage, false);
        await device.stayAwake(false);
        await device.screen(false);
        await device.doze(true);
        await Future<void>.delayed(const Duration(minutes: 15));
        await device.doze(false);
        await device.screen(true);
        await device.stayAwake(true);
        await device.whitelist(itestPackage, true);
      case Fault.killApp:
        await device.killApp(itestPackage);
        // Убитый процесс маркеров не шлёт: прежнее `connected` дало бы ложный ZOMBIE.
        agent.lastState = null;
      case Fault.idle:
        break;
    }
    _onWifi = true;
    _event('fault-end', {'fault': f.cli});
    return DateTime.now();
  }

  Future<void> run() async {
    final sub = logcat.listen((l) {
      _recent.addLast(l);
      if (_recent.length > 20000) _recent.removeFirst();
    });
    final deadline = DateTime.now().add(duration);
    final schedule = [for (var i = 0; i < repeat; i++) ...faults];
    final idleLen = Duration(
        seconds: (duration.inSeconds ~/ (2 * (schedule.isEmpty ? 1 : schedule.length))).clamp(60, 600));
    try {
      if (!await _connect()) {
        final r = FaultResult(Fault.idle, Verdict.fail, null, 'initial connect failed');
        await _diag(r);
        _report(r);
        return;
      }
      // Спокойный интервал → сбой → восстановление; по кругу до [duration].
      // С --repeat > 1 — ровно repeat проходов по списку сбоев.
      var i = 0;
      while (DateTime.now().isBefore(deadline)) {
        final idle = classifyIdle(await _sample(idleLen));
        _report(idle);
        if (idle.verdict != Verdict.pass) {
          await _diag(idle);
          await _reconnect();
        }
        if (schedule.isEmpty) continue;
        if (!DateTime.now().isBefore(deadline) || (repeat > 1 && i >= schedule.length)) break;
        final f = schedule[i++ % schedule.length];
        final restoredAt = await _inject(f);
        var r = classifyRecovery(
            fault: f,
            restoredAt: restoredAt,
            after: await _sample(const Duration(minutes: 3, seconds: 30), untilOk: true));
        if (f == Fault.wifiLte && !_lteOk && r.verdict == Verdict.pass) {
          r = FaultResult(f, Verdict.fail, null, 'no VPN traffic during the LTE minute', at: r.at);
        }
        _report(r);
        if (r.verdict != Verdict.pass) {
          await _diag(r);
          await _reconnect();
        }
      }
    } finally {
      try {
        await agent.send('disconnect', const {}, const Duration(seconds: 60));
      } catch (_) {}
      await sub.cancel();
      await _timeline.close();
    }
  }
}
