import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'adb.dart';
import 'agent_client.dart';
import 'device_guard.dart';
import 'probes.dart';
import 'report.dart';

typedef AgentConfig = ({
  String id,
  String name,
  String protocol,
  String host,
  int port,
  String? sub,
  List<String> cores,

  /// A managed config with its own xray JSON (the outer address isn't the one it dials).
  bool raw,
});

AgentConfig agentConfigFromJson(Map<String, dynamic> m) => (
  id: m['id'] as String,
  name: m['name'] as String,
  protocol: m['protocol'] as String,
  host: m['host'] as String,
  port: m['port'] as int,
  sub: m['sub'] as String?,
  cores: (m['cores'] as List).cast<String>(),
  raw: m['raw'] == true,
);

/// Core nativeId → name in the report and filters.
const coreNames = {'go': 'xray-core', 'rust': 'xray-rust', 'box': 'sing-box'};

bool globMatch(String glob, String s) {
  final re = RegExp(
    '^${glob.split('*').map((p) => RegExp.escape(p).replaceAll(r'\?', '.')).join('.*')}\$',
    caseSensitive: false,
  );
  return re.hasMatch(s);
}

class CaseCtx {
  final AgentClient agent;
  final Probes probes;
  final Baseline baseline;
  final DeviceGuard device;

  /// Expected exit IP: from secrets (strict) or the server host IP (a hint).
  final String? egress;
  final bool strictEgress;

  /// The case's config (the core switch connects it again on other cores).
  final String configId;

  CaseCtx(
    this.agent,
    this.probes,
    this.baseline,
    this.device,
    this.egress, {
    this.strictEgress = false,
    this.configId = '',
  });

  /// Services through which this tunnel is distinguishable from the direct path.
  List<String> get informativeUrls =>
      egress != null && egress == baseline.directRuIp ? const [] : informative(baseline.direct, egress);

  Future<Map<String, String?>> observe(List<String> urls) async {
    final ips = await probes.ips(urls);
    return {for (var i = 0; i < urls.length; i++) urls[i]: ips[i]};
  }

  /// Through the tunnel: [url] or all echo services.
  Future<Outcome> tunnel([String? url]) async {
    final urls = url == null ? baseline.direct.keys.toList() : [url];
    return classifyTunnel(
      baseline: {for (final u in urls) u: baseline.direct[u]},
      observed: await observe(urls),
      egress: egress,
      strictEgress: strictEgress,
      ispIp: baseline.directRuIp,
    );
  }

  Future<Outcome> direct(String url) async =>
      classifyDirect(baseline: baseline.direct[url], observed: await probes.ip(url), egress: egress);

  Future<Outcome> directRu() async =>
      classifyDirect(baseline: baseline.directRuIp, observed: await probes.ip(echoRu), egress: egress);

  /// Two distinguishable services for routing rules (a — the rule, b — the rest). Not the app's own IP lookup
  /// services: in `onlySelected` the app sends them through the proxy whatever the rules say.
  (String, String)? get pair {
    final urls = informativeUrls.where((u) => !appLookupHosts.contains(Uri.parse(u).host)).toList();
    return urls.length < 2 ? null : (urls[0], urls[1]);
  }
}

typedef Check = Future<Outcome> Function(CaseCtx ctx);

/// Hosts of `IpLookupSource.all` (`lib/core/services/ip_lookup.dart`): `diagnosticRules` route them through the proxy.
const appLookupHosts = {'ip-api.com', 'ipinfo.io', 'api.ipify.org'};

class MatrixCase {
  final String id;
  final String configId;
  final String configName;
  final String core;
  final Map<String, dynamic> settingsPatch;
  final Check check;
  final bool owned;

  const MatrixCase(this.id, this.configId, this.configName, this.core, this.settingsPatch, this.check, this.owned);
}

class CaseResult {
  final String id;
  final Verdict verdict;
  final String note;
  final Duration took;
  final String dir;
  final String? configId;

  const CaseResult(this.id, this.verdict, this.note, this.took, this.dir, {this.configId});

  Map<String, Object?> toJson() => {
    'id': id,
    'verdict': verdict.name,
    'note': note,
    'tookMs': took.inMilliseconds,
    'dir': dir,
  };
}

/// All checks: fail beats skip, skip beats pass.
Outcome combine(List<Outcome> all) {
  final bad = all.where((o) => o.v == Verdict.fail);
  if (bad.isNotEmpty) return (v: Verdict.fail, note: bad.map((o) => o.note).join('; '));
  final skip = all.where((o) => o.v == Verdict.skip);
  if (skip.isNotEmpty) return (v: Verdict.skip, note: skip.map((o) => o.note).join('; '));
  return (v: Verdict.pass, note: all.map((o) => o.note).join('; '));
}

const _shell = 'com.android.shell';

Map<String, dynamic> _route(String direction, Map<String, dynamic> rules) => {
  'routing': {'direction': direction, ...rules},
};

Future<Outcome> _tunnelOnly(CaseCtx c) => c.tunnel();

/// A rule on service a's domain: [aDirect] — a direct, b through the tunnel; otherwise the reverse.
Check _routePair({required bool aDirect}) => (c) async {
  final p = c.pair;
  if (p == null) return (v: Verdict.skip, note: 'need 2 usable echo services');
  final (a, b) = p;
  return aDirect ? combine([await c.direct(a), await c.tunnel(b)]) : combine([await c.tunnel(a), await c.direct(b)]);
};

Future<Outcome> _splitDirect(CaseCtx c) async {
  final urls = c.informativeUrls;
  return urls.isEmpty ? (v: Verdict.skip, note: 'egress = direct IP, indistinguishable') : c.direct(urls.first);
}

/// The host of the first suitable echo service is put into the rule at run time.
const echoHostPlaceholder = r'$ECHO_A';

Future<Outcome> _dns(CaseCtx c, {required bool proxy}) async => combine([
  await c.tunnel(),
  classifyDns(baseline: c.baseline.dnsResolver, observed: await c.probes.dnsResolver(), proxy: proxy),
]);

Future<Outcome> _killSwitch(CaseCtx c, {required bool on}) async {
  final before = await c.tunnel();
  if (before.v != Verdict.pass) return before;
  await c.agent.send('drop');
  await c.agent.waitState({'blocked', 'error', 'disconnected'}, const Duration(seconds: 20));
  await Future<void>.delayed(const Duration(seconds: 3));
  final urls = c.informativeUrls;
  if (urls.isEmpty) return (v: Verdict.skip, note: 'egress = direct IP, indistinguishable');
  if (!on) return c.direct(urls.first);
  final observed = [for (var i = 0; i < 3; i++) ...(await c.observe(urls)).entries];
  if (observed.any((e) => e.value != null && e.value == c.baseline.direct[e.key])) {
    return (v: Verdict.fail, note: 'leak after drop');
  }
  final seen = observed.map((e) => e.value).nonNulls;
  return seen.isEmpty
      ? (v: Verdict.pass, note: 'blocked after drop')
      : (v: Verdict.fail, note: 'traffic after drop via ${seen.toSet().join(',')}');
}

Future<Outcome> _proxyOnly(CaseCtx c) async {
  final m = c.agent.lastConnected ?? const {};
  final proxy = "-x 'socks5h://${m['socksUser']}:${m['socksPassword']}@127.0.0.1:${m['socksPort']}'";
  final urls = c.baseline.direct.keys.toList();
  return classifyTunnel(
    baseline: c.baseline.direct,
    observed: {for (final u in urls) u: await c.probes.ip(u, extra: proxy)},
    egress: c.egress,
    strictEgress: c.strictEgress,
  );
}

/// The hot switch of the running session to each other core that runs the config (the server list's
/// path), then a disconnect: the stop must reach the core that runs now, not the one the session started on.
Future<Outcome> _coreSwitch(CaseCtx c) async {
  final from = c.agent.lastConnected?['core'];
  final outs = <Outcome>[];
  for (final core in coreNames.keys.where((k) => k != from)) {
    c.agent.lastState = null;
    try {
      await c.agent.send('connect', {'configId': c.configId, 'core': core});
    } on ItestAgentError catch (e) {
      if (e.message.contains('Bad state: core')) continue;
      rethrow;
    }
    final state = await c.agent.waitState({'connected', 'error', 'blocked'}, const Duration(seconds: 60));
    final runs = c.agent.lastConnected?['core'];
    if (state != 'connected' || runs != core) {
      return (v: Verdict.fail, note: 'switch to ${coreNames[core]}: $state${runs == core ? '' : ' on $runs'}');
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    final o = await c.tunnel();
    outs.add((v: o.v, note: '${coreNames[core]}: ${o.note}'));
  }
  if (outs.isEmpty) return (v: Verdict.skip, note: 'no other core runs this config');
  c.agent.lastState = null;
  await c.agent.send('disconnect');
  final state = await c.agent.waitState({'disconnected', 'error'}, const Duration(seconds: 15));
  if (state != 'disconnected') return (v: Verdict.fail, note: 'disconnect after the switch: $state');
  final urls = c.informativeUrls;
  if (urls.isNotEmpty) outs.add(await c.direct(urls.first));
  return combine(outs);
}

/// Options not supported by all cores (`CoreBackend.supports`): name → cores.
/// xray-rust answers pings itself, ICMP can't be turned off in it.
const _coreOptions = {
  'proxy-only': {'go'},
  'icmp-off': {'go', 'box'},
  'mux': {'go'},
  'noise': {'go', 'rust'},
  'mtu-1280': {'go', 'box'},
};

/// Option cases: name → (settings patch, check).
final Map<String, (Map<String, dynamic>, Check)> optionCases = {
  'route-sites-direct': (
    _route('bypass', {
      'sitesEnabled': true,
      'sites': [echoHostPlaceholder],
    }),
    _routePair(aDirect: true),
  ),
  'route-sites-only': (
    _route('onlySelected', {
      'sitesEnabled': true,
      'sites': [echoHostPlaceholder],
    }),
    _routePair(aDirect: false),
  ),
  'route-zone-ru': (
    _route('bypass', {
      'domainEnabled': true,
      'domainZones': ['ru'],
    }),
    (c) async => c.baseline.directRuIp == null
        ? (v: Verdict.skip, note: 'ru echo')
        : combine([await c.directRu(), await c.tunnel()]),
  ),
  'route-geoip-ru': (
    _route('bypass', {
      'geoEnabled': true,
      'geoCodes': ['ru'],
    }),
    (c) async => c.baseline.directRuIp == null
        ? (v: Verdict.skip, note: 'ru echo')
        : combine([await c.directRu(), await c.tunnel()]),
  ),
  'route-geosite': (
    _route('bypass', {
      'geositeEnabled': true,
      'geositeCodes': ['google'],
    }),
    _tunnelOnly,
  ),
  'route-adblock': (
    _route('global', {'adBlockEnabled': true}),
    (c) async => combine([
      await c.tunnel(),
      switch (await c.probes.reachable('https://ad.doubleclick.net')) {
        true => (v: Verdict.fail, note: 'ad domain reachable'),
        false => (v: Verdict.pass, note: 'ad blocked'),
        null => (v: Verdict.fail, note: 'probe failed: no HTTP status'),
      },
    ]),
  ),
  'dns-proxy-ipv4': ({'dnsMode': 'proxy', 'dnsQueryStrategy': 'ipv4Only'}, (c) => _dns(c, proxy: true)),
  'dns-proxy-auto': ({'dnsMode': 'proxy', 'dnsQueryStrategy': 'auto'}, (c) => _dns(c, proxy: true)),
  'dns-direct': ({'dnsMode': 'direct'}, (c) => _dns(c, proxy: false)),
  'split-exclude-shell': (
    {
      'splitTunnelingEnabled': true,
      'vpnMode': 'allExcept',
      'excludedPackages': [_shell],
    },
    _splitDirect,
  ),
  'split-only-shell': (
    {
      'splitTunnelingEnabled': true,
      'vpnMode': 'onlySelected',
      'includedPackages': [_shell],
    },
    _tunnelOnly,
  ),
  'split-only-other': (
    {
      'splitTunnelingEnabled': true,
      'vpnMode': 'onlySelected',
      'includedPackages': ['com.android.chrome'],
    },
    _splitDirect,
  ),
  'killswitch-on': ({'killSwitchEnabled': true}, (c) => _killSwitch(c, on: true)),
  'killswitch-off': ({'killSwitchEnabled': false}, (c) => _killSwitch(c, on: false)),
  'icmp-on': (
    {'allowIcmp': true},
    (c) async =>
        await c.probes.ping('1.1.1.1') ? (v: Verdict.pass, note: 'ping ok') : (v: Verdict.fail, note: 'ping failed'),
  ),
  'icmp-off': (
    {'allowIcmp': false},
    // Without VPN 1.1.1.1 doesn't answer ping — nothing to check the blocking with.
    (c) async => c.baseline.ping == false
        ? (v: Verdict.skip, note: 'no direct ping to 1.1.1.1')
        : await c.probes.ping('1.1.1.1')
        ? (v: Verdict.fail, note: 'ping passed with ICMP off')
        : (v: Verdict.pass, note: 'ping blocked'),
  ),
  'udp-off': ({'enableUdp': false}, _tunnelOnly),
  'quic-block': ({'blockQuic': true}, _tunnelOnly),
  'mux': (
    {
      'mux': {'enabled': true},
    },
    _tunnelOnly,
  ),
  'fragment': (
    {
      'fragment': {'enabled': true},
    },
    _tunnelOnly,
  ),
  'noise': (
    {
      'noise': {'enabled': true},
    },
    _tunnelOnly,
  ),
  'sniffing-off': ({'sniffingEnabled': false}, _tunnelOnly),
  'mtu-1280': ({'mtu': 1280}, _tunnelOnly),
  'tls-fp-chrome': ({'tlsFingerprint': 'chrome'}, _tunnelOnly),
  'core-switch': (const {}, _coreSwitch),
  'proxy-only': ({'proxyOnly': true}, _proxyOnly),
};

/// Run cases. [reference]: core nativeId → reference config id (for opt cases).
List<MatrixCase> buildMatrix(
  List<AgentConfig> configs, {
  required Map<String, bool> owned,
  Map<String, String> reference = const {},
  String? configGlob,
  String? coreGlob,
  String? caseGlob,
}) {
  bool coreOk(String core) => coreGlob == null || globMatch(coreGlob, coreNames[core] ?? core);
  final names = <String, int>{};
  for (final c in configs) {
    names[c.name] = (names[c.name] ?? 0) + 1;
  }
  String label(AgentConfig c) => names[c.name]! > 1 ? '${c.name}@${c.host}:${c.port}' : c.name;
  final cases = <MatrixCase>[
    for (final core in coreNames.keys)
      if (coreOk(core))
        for (final c in configs)
          if (c.cores.contains(core) && (configGlob == null || globMatch(configGlob, label(c))))
            MatrixCase(
              'base/${coreNames[core]}/${label(c)}',
              c.id,
              label(c),
              core,
              const {},
              _tunnelOnly,
              owned[c.id] ?? false,
            ),
    for (final MapEntry(key: core, value: refId) in reference.entries)
      if (coreOk(core))
        for (final c in configs.where((c) => c.id == refId))
          for (final MapEntry(key: name, value: (patch, check)) in optionCases.entries)
            if (_coreOptions[name]?.contains(core) ?? true)
              MatrixCase('opt/${coreNames[core]}/$name', c.id, label(c), core, patch, check, owned[c.id] ?? false),
  ];
  return caseGlob == null ? cases : cases.where((c) => globMatch(caseGlob, c.id)).toList();
}

/// The case is inapplicable even before connecting.
class _Skip implements Exception {
  final String note;
  const _Skip(this.note);
}

/// Running one case: settings → connect → check → disconnect.
Future<CaseResult> runCase(MatrixCase mc, CaseCtx ctx, RunDir run, Shell shell, Stream<String> logcat) async {
  final started = DateTime.now();
  final dir = run.caseDir(mc.id);
  final steps = File('${dir.path}/steps.log').openWrite();
  final logs = File('${dir.path}/logcat.txt').openWrite();
  final sub = logcat.listen((l) => logs.writeln(maskSecrets(l)));
  void step(String s) => steps.writeln('${DateTime.now().toIso8601String()} $s');
  ctx.probes.log = step;
  Outcome out;
  var connectSent = false, connected = false;
  try {
    final usesEcho = jsonEncode(mc.settingsPatch).contains(echoHostPlaceholder);
    if (usesEcho && ctx.pair == null) throw const _Skip('need 2 usable echo services');
    final host = ctx.pair == null ? '' : Uri.parse(ctx.pair!.$1).host;
    final patch =
        jsonDecode(jsonEncode(mc.settingsPatch).replaceAll(echoHostPlaceholder, host)) as Map<String, dynamic>;
    step('reset settings $patch');
    await ctx.agent.send('reset', {'keepConfigs': true, 'settings': patch});
    ctx.agent.lastState = null;
    step('connect ${mc.configName} on ${coreNames[mc.core]}');
    connectSent = true;
    await ctx.agent.send('connect', {'configId': mc.configId, 'core': mc.core});
    final state = await ctx.agent.waitState({'connected', 'error', 'blocked'}, const Duration(seconds: 60));
    step('state $state');
    if (state != 'connected') {
      out = (v: Verdict.fail, note: 'connect: $state');
    } else {
      connected = true;
      await Future<void>.delayed(const Duration(seconds: 2));
      out = await mc.check(ctx);
    }
  } on _Skip catch (e) {
    out = (v: Verdict.skip, note: e.note);
  } on ItestAgentError catch (e) {
    out = e.message.contains('connect: Bad state: core')
        ? (v: Verdict.skip, note: 'unsupported: ${e.message}')
        : (v: Verdict.fail, note: e.message);
  } on ItestTimeout catch (e) {
    out = (v: Verdict.fail, note: e.message);
  } catch (e) {
    // An error of the runner itself must not abort the whole run.
    out = (v: Verdict.fail, note: 'internal: $e');
  }
  step('verdict ${out.v.name}: ${out.note}');
  if (out.v != Verdict.pass) await dumpGoroutines(ctx.agent, dir, step);
  try {
    // Already off (the check disconnected itself): a second disconnect gets no new state to wait for.
    if (ctx.agent.lastState != 'disconnected') {
      // A late marker of this case must not leak into waiting for the next one.
      ctx.agent.lastState = null;
      await ctx.agent.send('disconnect');
      await ctx.agent.waitState({'disconnected', 'error'}, const Duration(seconds: 15));
    }
    ctx.agent.lastState = null;
  } catch (e) {
    step('disconnect: $e');
  }
  try {
    if (out.v != Verdict.pass) await collectDiag(shell, dir);
  } catch (e) {
    step('diag: $e');
  }
  // A foreign server might just not answer; after connecting a failure is ours.
  if (!mc.owned && connectSent && !connected && out.v == Verdict.fail) {
    out = (v: Verdict.skip, note: 'unreachable (not owned): ${out.note}');
  }
  ctx.probes.log = null;
  await sub.cancel();
  await logs.close();
  await steps.close();
  return CaseResult(
    mc.id,
    out.v,
    out.note,
    DateTime.now().difference(started),
    run.relative(dir),
    configId: mc.configId,
  );
}

/// Goroutines of Go cores before disconnecting — for analyzing hangs (`goroutines.txt`).
Future<void> dumpGoroutines(AgentClient agent, Directory dir, void Function(String) step) async {
  try {
    File('${dir.path}/goroutines.txt').writeAsStringSync(await agent.send('goroutines') as String);
  } catch (e) {
    step('goroutines: $e');
  }
}

/// Snapshot for analyzing a failure: network and the app log.
Future<void> collectDiag(Shell shell, Directory dir) async {
  File('${dir.path}/connectivity.txt').writeAsStringSync((await shell.run(['shell', 'dumpsys connectivity'])).out);
  File(
    '${dir.path}/vpn_log.txt',
  ).writeAsStringSync((await shell.run(['shell', 'run-as $itestPackage cat files/vpn_log.txt'])).out);
}
