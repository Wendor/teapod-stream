import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_http.dart';
import 'tunnel_socks.dart';

/// The exit IP as a lookup service saw it; [countryCode] is null when the service doesn't report it.
class IpLookupResult {
  final String ip;
  final String? country;
  final String? countryCode;

  const IpLookupResult(this.ip, {this.country, this.countryCode});
}

/// A service that tells the exit IP. [parse] gets the response body and returns null for an answer without an IP.
class IpLookupSource {
  final String id;
  final Uri url;
  final IpLookupResult? Function(String body) parse;

  const IpLookupSource._(this.id, this.url, this.parse);

  String get host => url.host;

  static final ipApi = IpLookupSource._(
    'ip-api',
    Uri.parse('http://ip-api.com/json?fields=query,country,countryCode,status'),
    (body) {
      final json = _object(body);
      if (json == null || json['status'] != 'success') return null;
      return _result(json['query'], country: json['country'], countryCode: json['countryCode']);
    },
  );

  static final ipInfo = IpLookupSource._('ipinfo', Uri.parse('https://ipinfo.io/json'), (body) {
    final json = _object(body);
    return json == null ? null : _result(json['ip'], countryCode: json['country']);
  });

  static final ipify = IpLookupSource._('ipify', Uri.parse('https://api.ipify.org?format=json'), (body) {
    final json = _object(body);
    return json == null ? null : _result(json['ip']);
  });

  /// The default order.
  static final all = [ipApi, ipInfo, ipify];

  /// Hosts the cores route through the tunnel in "selected only" mode, so the lookup sees the tunnel's exit.
  static final hosts = [for (final s in all) s.host];

  static Map<String, dynamic>? _object(String body) {
    try {
      final json = jsonDecode(body);
      return json is Map<String, dynamic> ? json : null;
    } on FormatException {
      return null;
    }
  }

  static IpLookupResult? _result(Object? ip, {Object? country, Object? countryCode}) {
    if (ip is! String || ip.isEmpty) return null;
    String? text(Object? v) => v is String && v.isNotEmpty ? v : null;
    return IpLookupResult(ip, country: text(country), countryCode: text(countryCode)?.toUpperCase());
  }
}

/// Asks the services one by one until one answers. The order is kept per config in memory: the service that
/// answered goes first, one that failed goes last for [penalty]. After a restart the worst case is one slow
/// service once — not worth storing.
class IpLookup {
  IpLookup({
    List<IpLookupSource>? sources,
    this.perService = const Duration(seconds: 4),
    this.total = const Duration(seconds: 10),
    this.penalty = const Duration(hours: 1),
    DateTime Function()? now,
  }) : sources = sources ?? IpLookupSource.all,
       _now = now ?? DateTime.now;

  final List<IpLookupSource> sources;
  final Duration perService;
  final Duration total;
  final Duration penalty;
  final DateTime Function() _now;

  final _order = <String, List<IpLookupSource>>{};
  final _failedAt = <String, Map<String, DateTime>>{};

  /// The order the next lookup for [configId] will use.
  List<IpLookupSource> orderFor(String configId) {
    final order = _order[configId] ?? sources;
    final failed = _failedAt[configId] ?? const {};
    final now = _now();
    bool penalized(IpLookupSource s) => failed[s.id] != null && now.difference(failed[s.id]!) < penalty;
    return [...order.where((s) => !penalized(s)), ...order.where(penalized)];
  }

  static const _maxBodyBytes = 64 * 1024;

  /// [lookup] over HTTP through [socks]: the lookup is about the tunnel's exit IP. One client for the chain: closing
  /// it ends the requests the lookup stopped waiting for.
  Future<IpLookupResult?> lookupThrough(String configId, TunnelSocks socks) async {
    final client = AppHttp.client(socks: socks);
    Future<String> fetch(Uri url) async {
      final resp = await AppHttp.get(
        url,
        client: client,
        headers: const {HttpHeaders.userAgentHeader: 'TeapodStream'},
        maxBytes: _maxBodyBytes,
      );
      if (resp.statusCode != HttpStatus.ok) throw HttpException('HTTP ${resp.statusCode}', uri: url);
      return resp.body;
    }

    try {
      return await lookup(configId, fetch);
    } finally {
      client.close(force: true);
    }
  }

  /// The first answer with an IP, or null when every service failed or [total] ran out. [fetch] returns the body
  /// of a GET to the URL (through the tunnel) and throws on any failure.
  Future<IpLookupResult?> lookup(String configId, Future<String> Function(Uri url) fetch) async {
    final deadline = _now().add(total);
    for (final source in orderFor(configId)) {
      final left = deadline.difference(_now());
      if (left <= Duration.zero) break;
      IpLookupResult? result;
      try {
        result = source.parse(await fetch(source.url).timeout(left < perService ? left : perService));
      } catch (_) {
        result = null;
      }
      if (result != null) {
        _succeeded(configId, source);
        return result;
      }
      (_failedAt[configId] ??= {})[source.id] = _now();
    }
    return null;
  }

  void _succeeded(String configId, IpLookupSource source) {
    _order[configId] = [source, ...(_order[configId] ?? sources).where((s) => s != source)];
    _failedAt[configId]?.remove(source.id);
  }
}
