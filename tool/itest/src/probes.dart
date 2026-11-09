import 'dart:convert';
import 'dart:io';

import 'adb.dart';

/// Echo-сервисы, отдающие голый IP клиента.
/// Сеть (например, роутер с маршрутизацией) может сама заворачивать часть из них
/// в туннель — такие отсеивает [measureBaseline].
const echoMain = [
  'https://ifconfig.co/ip',
  'https://ipinfo.io/ip',
  'https://checkip.amazonaws.com/',
  'https://api.ipify.org',
  'https://ident.me',
];

/// Echo с российским доменом и IP — для правил `domain:ru` и `geoip:ru`. Отдаёт
/// HTML: берётся первый публичный IPv4 (API Яндекса в домашней сети отвечал 127.0.0.1).
const echoRu = 'https://ip.nic.ru';
const _htmlEcho = {echoRu};

enum Verdict { pass, fail, skip, zombie }

typedef Outcome = ({Verdict v, String note});

/// Резолвер по edns.ip-api.com; [geo] — страна и провайдер.
typedef Resolver = ({String ip, String geo});

/// Пробы трафика из `adb shell` (uid shell идёт через TUN как обычное приложение).
class Probes {
  final Shell shell;
  Probes(this.shell);

  /// Журнал кейса: сюда пишется сырой ответ проваленной пробы.
  void Function(String)? log;

  Future<String> _curl(String args, Duration timeout) async =>
      (await shell.run(['shell', 'curl -s -m ${timeout.inSeconds} $args'], timeout: timeout + const Duration(seconds: 5)))
          .out
          .trim();

  /// IP клиента по echo-сервису; пустой ответ повторяется [retries] раз через 2 с —
  /// одиночный сбой echo-сервиса (лимит запросов, таймаут) не должен ронять кейс.
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

  /// Рекурсивный резолвер, через который ушёл DNS-запрос: IP и провайдер.
  Future<Resolver?> dnsResolver() async {
    try {
      // Редирект на случайный поддомен — запрос к резолверу без кеша.
      final j = jsonDecode(await _curl('-L http://edns.ip-api.com/json', const Duration(seconds: 10)))
          as Map<String, dynamic>;
      final dns = j['dns'] as Map?;
      final ip = dns?['ip'] as String?;
      return ip == null ? null : (ip: ip, geo: dns?['geo'] as String? ?? '');
    } catch (_) {
      return null;
    }
  }

  /// Есть HTTP-ответ; `null` — проба не выполнилась (нет кода статуса).
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
  /// Прямой IP по каждому echo-сервису (null — сервис недоступен). Сеть может
  /// сама заворачивать часть сервисов в свой туннель — они видят его выход.
  final Map<String, String?> direct;
  final String? directRuIp;
  final Resolver? dnsResolver;

  /// Ответил ли 1.1.1.1 на ping без VPN (контроль для icmp-off); null — не мерили.
  final bool? ping;

  const Baseline(this.direct, this.directRuIp, this.dnsResolver, {this.ping});

  Map<String, Object?> toJson() => {
        'direct': direct,
        'directRuIp': directRuIp,
        'dnsResolver': dnsResolver == null ? null : {'ip': dnsResolver!.ip, 'geo': dnsResolver!.geo},
        'ping': ping,
      };
}

/// Без VPN: прямой IP по каждому сервису, IP до российского echo и резолвер.
Future<Baseline> measureBaseline(Probes p) async {
  final ips = await p.ips(echoMain);
  return Baseline({for (var i = 0; i < echoMain.length; i++) echoMain[i]: ips[i]},
      await p.ip(echoRu), await p.dnsResolver(),
      ping: await p.ping('1.1.1.1'));
}

/// Сервисы, по которым туннель с выходом [egress] отличим от прямого пути.
List<String> informative(Map<String, String?> baseline, String? egress) =>
    [for (final e in baseline.entries) if (e.value != null && e.value != egress) e.key];

/// Ожидание «через туннель» по ответам сервисов ([observed]: url → IP).
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
  // Сервер в сети устройства (выход = IP провайдера, [ispIp] — по RU-echo, который
  // сеть не заворачивает): по IP туннель неотличим от прямого пути.
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

/// Ожидание «напрямую» для одного сервиса.
Outcome classifyDirect({required String? baseline, required String? observed, String? egress}) {
  if (baseline == null) return (v: Verdict.skip, note: 'echo');
  if (observed == null) return (v: Verdict.fail, note: 'no traffic');
  if (observed != baseline) return (v: Verdict.fail, note: 'expected direct $baseline, got $observed');
  return baseline == egress
      ? (v: Verdict.skip, note: 'direct IP = egress, indistinguishable')
      : (v: Verdict.pass, note: 'direct');
}

/// DNS через прокси не должен уходить к провайдеру из baseline. Сравнивается
/// провайдер (geo), а не IP: у провайдера anycast-пул резолверов.
Outcome classifyDns({required Resolver? baseline, required Resolver? observed, required bool proxy}) {
  if (observed == null) return (v: Verdict.fail, note: 'dns resolve failed');
  final sameGeo = observed.geo.isNotEmpty && observed.geo == baseline?.geo;
  if (proxy && baseline != null && (observed.ip == baseline.ip || sameGeo)) {
    return (v: Verdict.fail, note: 'dns leak: ${observed.geo} ${observed.ip}');
  }
  return (v: Verdict.pass, note: 'resolver ${observed.geo} ${observed.ip}');
}
