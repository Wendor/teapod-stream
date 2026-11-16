import 'dart:convert';
import 'dart:io';

import 'adb.dart';

/// Echo services returning the client's bare IP.
/// The network (e.g. a router with routing) may itself route some of them
/// into a tunnel — [measureBaseline] filters those out.
const echoMain = [
  'https://ifconfig.co/ip',
  'https://ipinfo.io/ip',
  'https://checkip.amazonaws.com/',
  'https://api.ipify.org',
  'https://ident.me',
];

/// Echo with a Russian domain and IP — for `domain:ru` and `geoip:ru` rules. Returns
/// HTML: the first public IPv4 is taken (the Yandex API answered 127.0.0.1 on the home network).
const echoRu = 'https://ip.nic.ru';
const _htmlEcho = {echoRu};

enum Verdict { pass, fail, skip, zombie }

typedef Outcome = ({Verdict v, String note});

/// Resolver via edns.ip-api.com; [geo] — country and provider.
typedef Resolver = ({String ip, String geo});

/// Traffic probes from `adb shell` (the shell uid goes through TUN like a regular app).
class Probes {
  final Shell shell;
  Probes(this.shell);

  /// Case log: the raw answer of a failed probe is written here.
  void Function(String)? log;

  Future<String> _curl(String args, Duration timeout) async =>
      (await shell.run(['shell', 'curl -s -m ${timeout.inSeconds} $args'], timeout: timeout + const Duration(seconds: 5)))
          .out
          .trim();

  /// Client IP via an echo service; an empty answer is retried [retries] times every 2 s —
  /// a single echo service failure (rate limit, timeout) must not fail the case.
  Future<String?> ip(String url,
      {Duration timeout = const Duration(seconds: 10), String extra = '', int retries = 1}) async {
    for (var i = 0;; i++) {
      final out = await _curl('$extra -w "\\n%{http_code}" $url'.trim(), timeout);
      final nl = out.lastIndexOf('\n');
      final ip = _parseIp(url, (nl < 0 ? out : out.substring(0, nl)).trim());
      if (ip != null) return ip;
      final body = out.replaceAll(RegExp(r'\s+'), ' ');
      log?.call('probe $url #${i + 1}: ${body.length > 160 ? '${body.substring(0, 160)}…' : body}');
      if (i >= retries) return null;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  String? _parseIp(String url, String out) {
    if (_htmlEcho.contains(url)) {
      return RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b')
          .allMatches(out)
          .map((m) => m[0]!)
          .where((ip) => _public(InternetAddress.tryParse(ip)))
          .firstOrNull;
    }
    final v = out.replaceAll('"', '');
    final a = InternetAddress.tryParse(v);
    return _public(a) ? v : null;
  }

  /// The recursive resolver the DNS query went through: IP and provider.
  Future<Resolver?> dnsResolver() async {
    try {
      // Redirect to a random subdomain — a query to the resolver without cache.
      final j = jsonDecode(await _curl('-L http://edns.ip-api.com/json', const Duration(seconds: 10)))
          as Map<String, dynamic>;
      final dns = j['dns'] as Map?;
      final ip = dns?['ip'] as String?;
      return ip == null ? null : (ip: ip, geo: dns?['geo'] as String? ?? '');
    } catch (_) {
      return null;
    }
  }

  /// There is an HTTP response; `null` — the probe didn't run (no status code).
  Future<bool?> reachable(String url) async {
    final code = await _curl('-o /dev/null -w %{http_code} $url', const Duration(seconds: 10));
    if (code == '000') return false;
    return RegExp(r'^[1-5]\d\d$').hasMatch(code) ? true : null;
  }

  Future<bool> ping(String host) async =>
      (await shell.run(['shell', 'ping -c 2 -W 3 $host'], timeout: const Duration(seconds: 15))).ok;

  Future<List<String?>> ips(List<String> urls) => Future.wait(urls.map(ip));
}

bool _public(InternetAddress? a) {
  if (a == null || a.isLoopback || a.isLinkLocal) return false;
  if (a.type != InternetAddressType.IPv4) return true;
  final [b0, b1, ..._] = a.rawAddress;
  return !(b0 == 10 || (b0 == 172 && b1 >= 16 && b1 < 32) || (b0 == 192 && b1 == 168) || b0 == 0);
}

class Baseline {
  /// Direct IP per echo service (null — the service is unavailable). The network may
  /// route some services into its own tunnel — they see its exit.
  final Map<String, String?> direct;
  final String? directRuIp;
  final Resolver? dnsResolver;

  /// Whether 1.1.1.1 answered ping without VPN (control for icmp-off); null — not measured.
  final bool? ping;

  const Baseline(this.direct, this.directRuIp, this.dnsResolver, {this.ping});

  Map<String, Object?> toJson() => {
        'direct': direct,
        'directRuIp': directRuIp,
        'dnsResolver': dnsResolver == null ? null : {'ip': dnsResolver!.ip, 'geo': dnsResolver!.geo},
        'ping': ping,
      };
}

/// Without VPN: direct IP per service, IP to the Russian echo, and the resolver.
Future<Baseline> measureBaseline(Probes p) async {
  final ips = await p.ips(echoMain);
  return Baseline({for (var i = 0; i < echoMain.length; i++) echoMain[i]: ips[i]},
      await p.ip(echoRu), await p.dnsResolver(),
      ping: await p.ping('1.1.1.1'));
}

/// Services through which a tunnel with exit [egress] is distinguishable from the direct path.
List<String> informative(Map<String, String?> baseline, String? egress) =>
    [for (final e in baseline.entries) if (e.value != null && e.value != egress) e.key];

/// "Through the tunnel" expectation from service answers ([observed]: url → IP).
Outcome classifyTunnel({
  required Map<String, String?> baseline,
  required Map<String, String?> observed,
  String? egress,
  bool strictEgress = false,
  String? ispIp,
}) {
  if (baseline.values.every((v) => v == null)) return (v: Verdict.skip, note: 'echo');
  final seen = observed.values.nonNulls.toSet();
  if (seen.isEmpty) return (v: Verdict.fail, note: 'no traffic');
  // The server is in the device's network (exit = ISP IP, [ispIp] — via the RU echo, which
  // the network doesn't reroute): by IP the tunnel is indistinguishable from the direct path.
  if (egress != null && egress == ispIp && !strictEgress) {
    return (v: Verdict.pass, note: 'traffic ok; server in device network, leak undetectable');
  }
  final leaks = [
    for (final u in informative(baseline, egress))
      if (observed[u] != null && observed[u] == baseline[u]) Uri.parse(u).host,
  ];
  if (leaks.isNotEmpty) return (v: Verdict.fail, note: 'leak: direct IP at ${leaks.join(',')}');
  if (strictEgress && egress != null && seen.any((ip) => ip != egress)) {
    return (v: Verdict.fail, note: 'unexpected egress ${seen.join(',')}');
  }
  final useful = informative(baseline, egress);
  final proof = useful.where((u) => observed[u] != null);
  if (useful.isNotEmpty && proof.isEmpty) {
    return (v: Verdict.skip, note: 'informative echo services silent; only ${seen.join(',')} (= direct)');
  }
  return proof.isEmpty
      ? (v: Verdict.pass, note: 'traffic ok via ${seen.join(',')}; egress = direct IP, leak undetectable')
      : (v: Verdict.pass, note: 'via ${seen.join(',')}');
}

/// "Direct" expectation for one service.
Outcome classifyDirect({required String? baseline, required String? observed, String? egress}) {
  if (baseline == null) return (v: Verdict.skip, note: 'echo');
  if (observed == null) return (v: Verdict.fail, note: 'no traffic');
  if (observed != baseline) return (v: Verdict.fail, note: 'expected direct $baseline, got $observed');
  return baseline == egress
      ? (v: Verdict.skip, note: 'direct IP = egress, indistinguishable')
      : (v: Verdict.pass, note: 'direct');
}

/// DNS through the proxy must not go to the provider from the baseline. The provider
/// (geo) is compared, not the IP: providers have an anycast pool of resolvers.
Outcome classifyDns({required Resolver? baseline, required Resolver? observed, required bool proxy}) {
  if (observed == null) return (v: Verdict.fail, note: 'dns resolve failed');
  final sameGeo = observed.geo.isNotEmpty && observed.geo == baseline?.geo;
  if (proxy && baseline != null && (observed.ip == baseline.ip || sameGeo)) {
    return (v: Verdict.fail, note: 'dns leak: ${observed.geo} ${observed.ip}');
  }
  return (v: Verdict.pass, note: 'resolver ${observed.geo} ${observed.ip}');
}
