import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'adb.dart';
import 'agent_client.dart';
import 'device_guard.dart';
import 'matrix.dart' show collectDiag, dumpGoroutines;
import 'probes.dart';
import 'relay.dart';
import 'report.dart' show maskSecrets;

enum Fault {
  wifiLte('wifi-lte'),
  offline10s('offline-10s'),
  offline1m('offline-1m'),
  offline5m('offline-5m'),
  doze('doze'),
  killApp('kill'),

  /// The activity is recreated over a running session (a new task, like a launch from recents after a swipe):
  /// the fresh UI must adopt the session without dropping it.
  uiRestart('ui-restart'),

  /// The server dies for 2 minutes and comes back (a relay copy of a TCP config): the heartbeat's reconnect.
  serverDown('server-down'),

  /// The server dies for good under `failAction: switchConfig`: the move to another live config.
  serverSwitch('server-switch'),
  idle('idle');

  const Fault(this.cli);

  final String cli;

  bool get needsRelay => this == serverDown || this == serverSwitch;

  static Fault fromCli(String s) =>
      values.firstWhere((f) => f.cli == s, orElse: () => throw ArgumentError('unknown fault: $s'));
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

/// Recovery after a fault: traffic within [failAfter] — pass; otherwise
/// zombie if the app showed connected all that time, or fail.
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
    return FaultResult(
      fault,
      Verdict.zombie,
      null,
      'connected without traffic for ${connected.first.t.difference(connected.last.t).inSeconds}s',
      at: restoredAt,
    );
  }
  return FaultResult(
    fault,
    Verdict.fail,
    null,
    'no traffic ${failAfter.inSeconds}s after restore (state ${after.lastOrNull?.appState})',
    at: restoredAt,
  );
}

/// One probe's answer [ip]: through the tunnel or not. [expected] exit — the strict [egress], else the exit seen on
/// Wi-Fi ([tunnelIp]) or the [egress] hint, checked when strict or off Wi-Fi (the direct IP changes there); otherwise
/// any answer but the [direct] one of a [distinguishable] service passes.
bool probeOk({
  required String? ip,
  required String? direct,
  required bool distinguishable,
  required String? egress,
  required bool strict,
  required String? tunnelIp,
  required bool onWifi,
}) {
  final expected = strict ? egress : tunnelIp ?? egress;
  final byEgress = expected != null && (strict || !onWifi);
  return ip != null && (byEgress ? ip == expected : !distinguishable || ip != direct);
}

/// A server fault without a relayed config is SKIP before it starts.
FaultResult? relayMissing(Fault f, {required bool hasRelay}) =>
    hasRelay ? null : FaultResult(f, Verdict.skip, null, 'no TCP config for the relay');

/// `server-down`: traffic while the server was cut means the session wasn't on the relay — the recovery says nothing.
FaultResult cutChecked(FaultResult r, {required bool trafficDuringCut}) => trafficDuringCut
    ? FaultResult(
        r.fault,
        Verdict.fail,
        null,
        'traffic while the server was cut: the relay is not in the path',
        at: r.at,
      )
    : r;

/// After `kill` / `ui-restart` traffic came back: the fresh UI must also show the session ([uiState]) as connected.
FaultResult adoptionChecked(FaultResult r, String? uiState) => r.verdict != Verdict.pass || uiState == 'connected'
    ? r
    : FaultResult(r.fault, Verdict.fail, r.recovery, 'traffic back, but the app shows $uiState', at: r.at);

/// Quiet interval: ≥ [minRun] failed probes in a row — a drop without a cause.
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
      return FaultResult(
        Fault.idle,
        zombie ? Verdict.zombie : Verdict.fail,
        null,
        'outage ${secs}s from ${run.first.t.toIso8601String().substring(11, 19)}, '
        '${s == null ? 'not recovered' : 'recovered'} (state ${run.last.appState})',
        at: run.first.t,
      );
    }
    run = [];
  }
  return FaultResult(Fault.idle, Verdict.pass, null, '${samples.length} probes ok', at: samples.firstOrNull?.t);
}

/// A long run of one core with faults.
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

  /// The relay to a TCP config and the phone's copy of that config ([Fault.needsRelay]); none — those faults are skipped.
  final Relay? relay;
  final String? relayConfigId;
  final String? relayEgress;
  final bool relayStrictEgress;

  late final IOSink _timeline = File('${dir.path}/timeline.jsonl').openWrite();
  final _recent = ListQueue<String>();
  var _diagN = 0;
  var _onWifi = true;
  var _lteOk = true;
  String? _tunnelIp;

  /// The exit the probes expect while the session isn't on [configId]: the relayed config's, or after
  /// `server-switch` none (any config's exit, just not the direct path).
  ({String? egress, bool strict})? _exit;
  var _cutLeak = false;

  /// Probes that got any answer (an IP, whatever the exit) since the last reset.
  var _answers = 0;
  List<String>? _faultLog;

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
    this.relay,
    this.relayConfigId,
    this.relayEgress,
    this.relayStrictEgress = false,
  });

  /// Probes expect [exit] from now on (null — [configId]'s); the exit seen on Wi-Fi is forgotten.
  void _expect(({String? egress, bool strict})? exit) {
    _exit = exit;
    _tunnelIp = null;
  }

  void _event(String kind, [Map<String, Object?> extra = const {}]) =>
      _timeline.writeln(jsonEncode({'t': DateTime.now().toIso8601String(), 'kind': kind, ...extra}));

  /// [fast] — recovery measurement: no retry and a short timeout,
  /// so the recovery time doesn't include retries of failed attempts.
  Future<ProbeSample> _probe({bool fast = false}) async {
    // A distinguishable service: answer ≠ its direct IP; otherwise any answer is enough.
    final (:egress, strict: strictEgress) = _exit ?? (egress: this.egress, strict: this.strictEgress);
    final urls = egress != null && egress == baseline.directRuIp
        ? const <String>[]
        : informative(baseline.direct, egress);
    final url = urls.isEmpty ? echoMain.first : urls.first;
    Future<String?> get(String u) =>
        fast ? probes.ip(u, timeout: const Duration(seconds: 5), retries: 0) : probes.ip(u);
    var (u, ip) = (url, await get(url));
    if (ip == null && urls.length > 1) (u, ip) = (urls[1], await get(urls[1]));
    // Off Wi-Fi the direct IP differs from the baseline — "not direct" doesn't yet mean "through VPN".
    // The expected exit is the one confirmed on Wi-Fi (the server's entry address may differ).
    if (ip != null) _answers++;
    final ok = probeOk(
      ip: ip,
      direct: baseline.direct[u],
      distinguishable: urls.isNotEmpty,
      egress: egress,
      strict: strictEgress,
      tunnelIp: _tunnelIp,
      onWifi: _onWifi,
    );
    if (ok && _onWifi && urls.isNotEmpty) _tunnelIp = ip;
    final s = (t: DateTime.now(), ok: ok, appState: agent.lastState);
    _event('probe', {'ip': ip, 'ok': ok, 'onWifi': _onWifi, 'state': agent.lastState});
    return s;
  }

  /// Probes every [probeInterval] during [d]; [untilOk] — until the first success.
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

  Future<bool> _connect({String? config, Map<String, dynamic> settings = const {}}) async {
    agent.lastState = null;
    try {
      await agent.send('reset', {'keepConfigs': true, 'settings': settings});
      await agent.send('connect', {'configId': config ?? configId, 'core': core});
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
    try {
      await collectDiag(shell, d);
    } catch (e) {
      // Even without diagnostics the result must get into the report.
      _event('note', {'text': 'diag: $e'});
    }
    File('${d.path}/logcat.txt').writeAsStringSync('${maskSecrets(_recent.join('\n'))}\n');
    File('${d.path}/result.json').writeAsStringSync(jsonEncode(r.toJson()));
  }

  /// Always-on VPN is definitely off (`null`); on an error or any packet — it isn't.
  Future<bool> _alwaysOnOff() async {
    try {
      final r = await shell.run(['shell', 'settings get secure always_on_vpn_app']);
      return r.ok && r.out.trim() == 'null';
    } catch (_) {
      return false;
    }
  }

  /// Moves the session to the relay copy before a server fault; false — the fault is reported and skipped.
  Future<bool> _onRelay(Fault f) async {
    if (relayMissing(f, hasRelay: relay != null && relayConfigId != null) case final skip?) {
      _report(skip);
      return false;
    }
    await relay!.up();
    _expect((egress: relayEgress, strict: relayStrictEgress));
    final settings = f == Fault.serverSwitch
        ? const {
            'heartbeat': {'failAction': 'switchConfig', 'switchSource': 'all'},
          }
        : const <String, dynamic>{};
    if (await _connect(config: relayConfigId, settings: settings) &&
        (await _sample(const Duration(minutes: 1), untilOk: true)).any((s) => s.ok)) {
      return true;
    }
    // The relay dials from the computer's network, which may not reach the server (a firewall, the
    // computer's own VPN): an environment limit, not the app's failure.
    final r = FaultResult(
      f,
      Verdict.skip,
      null,
      'no traffic through the relay (the computer may not reach the server)',
    );
    _report(r);
    await _diag(r);
    _expect(null);
    _event('note', {'text': 'back to the config: ${await _connect()}'});
    return false;
  }

  /// After the process was killed and the service restarted, a fresh UI adopts the running session.
  Future<FaultResult> _adopted(FaultResult r) async {
    String? state;
    final end = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(end)) {
      try {
        state = ((await agent.send('state')) as Map)['state'] as String?;
      } catch (e) {
        state = '$e';
      }
      if (state == 'connected') break;
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    return adoptionChecked(r, state);
  }

  void _report(FaultResult r) {
    _event('result', r.toJson());
    onResult(r);
  }

  /// Returns the moment the network recovered.
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
        _faultLog = [];
        await device.killApp(itestPackage);
        // A killed process sends no markers: the previous `connected` would give a false ZOMBIE.
        agent.lastState = null;
      case Fault.uiRestart:
        await shell.run([
          'shell',
          'am start -W -f 0x10008000 -a android.intent.action.MAIN -c android.intent.category.LAUNCHER '
              '-n $itestPackage/com.teapodstream.teapodstream.MainActivity',
        ]);
      case Fault.serverDown:
        await relay!.down();
        // Any answer while the server is cut — through another exit or direct — means the session doesn't go
        // through the relay; `ok` alone would miss an exit other than the expected one.
        _answers = 0;
        await _sample(const Duration(minutes: 2));
        _cutLeak = _answers > 0;
        await relay!.up();
      case Fault.serverSwitch:
        // The server stays dead: recovery is the switch, counted from the cut, to any other config.
        await relay!.down();
        _expect((egress: null, strict: false));
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
      _faultLog?.add(l);
      if (_recent.length > 20000) _recent.removeFirst();
    });
    final deadline = DateTime.now().add(duration);
    final schedule = [for (var i = 0; i < repeat; i++) ...faults];
    final idleLen = Duration(
      seconds: (duration.inSeconds ~/ (2 * (schedule.isEmpty ? 1 : schedule.length))).clamp(60, 600),
    );
    try {
      if (!await _connect()) {
        final r = FaultResult(Fault.idle, Verdict.fail, null, 'initial connect failed');
        await _diag(r);
        _report(r);
        return;
      }
      // Quiet interval → fault → recovery; in a loop until [duration].
      // With --repeat > 1 — exactly repeat passes over the fault list.
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
        if (f.needsRelay && !await _onRelay(f)) continue;
        final restoredAt = await _inject(f);
        var r = classifyRecovery(
          fault: f,
          restoredAt: restoredAt,
          after: await _sample(const Duration(minutes: 3, seconds: 30), untilOk: true),
        );
        // Android didn't restart the service — its race with the system Vpn (unbinding before
        // the process death is handled); without always-on VPN this is OS behavior. Only
        // when confirmed in logcat, otherwise the failure stays FAIL.
        final log = _faultLog ?? const <String>[];
        _faultLog = null;
        final osRace =
            log.any((l) => l.contains('Exception when unbinding service $itestPackage/')) &&
            !log.any((l) => l.contains('Scheduling restart of crashed service $itestPackage/'));
        if (f == Fault.killApp &&
            r.verdict != Verdict.pass &&
            agent.lastState == null &&
            osRace &&
            await _alwaysOnOff()) {
          r = FaultResult(f, Verdict.skip, null, 'Android did not restart the service (always-on VPN off)', at: r.at);
        }
        if (f == Fault.wifiLte && !_lteOk && r.verdict == Verdict.pass) {
          r = FaultResult(f, Verdict.fail, null, 'no VPN traffic during the LTE minute', at: r.at);
        }
        if ((f == Fault.killApp || f == Fault.uiRestart) && r.verdict == Verdict.pass) r = await _adopted(r);
        if (f == Fault.serverDown) r = cutChecked(r, trafficDuringCut: _cutLeak);
        _cutLeak = false;
        _report(r);
        if (r.verdict != Verdict.pass) await _diag(r);
        if (f.needsRelay) {
          await relay!.up();
          _expect(null);
          _event('note', {'text': 'back to the config: ${await _connect()}'});
        } else if (r.verdict != Verdict.pass) {
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
