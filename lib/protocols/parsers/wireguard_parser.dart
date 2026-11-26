import 'package:uuid/uuid.dart';

import '../../core/models/app_message.dart';
import '../../core/models/protocol_settings.dart';
import '../../core/models/vpn_config.dart';

/// WireGuard: `wireguard://` / `wg://` links and wg-quick `.conf` text (one peer).
abstract final class WireGuardParser {
  static final _confHeader = RegExp(r'^\s*\[Interface\]\s*$', multiLine: true, caseSensitive: false);

  static bool isConf(String text) => _confHeader.hasMatch(text);

  /// `.conf` → profile; [FormatException] with the reason if it can't be parsed.
  /// `DNS` and wg-quick keys (`PostUp`, `Table`, …) are ignored.
  static VpnConfig parseConf(String text, {String? name}) {
    final sections = _sections(text);
    final interfaces = sections.where((s) => s.name == 'interface').toList();
    final peers = sections.where((s) => s.name == 'peer').toList();
    if (interfaces.length != 1) throw ReasonException(AppMessage.l10n((l) => l.wgOneInterface));
    if (peers.isEmpty) throw ReasonException(AppMessage.l10n((l) => l.wgNoPeer));
    if (peers.length > 1) throw ReasonException(AppMessage.l10n((l) => l.wgOnePeer(peers.length)));
    final iface = interfaces.single.values;
    final peer = peers.single.values;
    final (host, port) = _endpoint(_required(peer, 'endpoint', 'Endpoint'));
    final settings = WireGuardSettings(
      privateKey: _required(iface, 'privatekey', 'PrivateKey'),
      addresses: _prefixes(iface['address']),
      peerPublicKey: _required(peer, 'publickey', 'PublicKey'),
      presharedKey: _nonEmpty(peer['presharedkey']),
      mtu: int.tryParse(iface['mtu'] ?? ''),
      allowedIps: _allowedIps(peer['allowedips']),
      keepalive: _keepalive(peer['persistentkeepalive']),
      amnezia: _amnezia(iface),
    );
    final config = _config(host, port, settings, name ?? 'WireGuard $host', null);
    return config.copyWith(rawUri: toUri(config));
  }

  /// `wireguard://<privateKey>@host:port?publickey=…&address=…#name`; null — can't parse.
  static VpnConfig? parseUri(String uri) {
    try {
      final parsed = Uri.parse(uri);
      if (parsed.scheme != 'wireguard' && parsed.scheme != 'wg') return null;
      final params = _query(parsed.query);
      final privateKey = Uri.decodeComponent(parsed.userInfo);
      final publicKey = params['publickey'] ?? params['public_key'] ?? '';
      if (privateKey.isEmpty || publicKey.isEmpty || parsed.host.isEmpty) return null;
      final host = parsed.host;
      final port = parsed.hasPort ? parsed.port : 51820;
      final settings = WireGuardSettings(
        privateKey: privateKey,
        addresses: _prefixes(params['address'] ?? params['ip']),
        peerPublicKey: publicKey,
        presharedKey: _nonEmpty(params['presharedkey'] ?? params['pre_shared_key']),
        mtu: int.tryParse(params['mtu'] ?? ''),
        reserved: _reserved(params['reserved']),
        allowedIps: _allowedIps(params['allowedips'] ?? params['allowed_ips']),
        keepalive: _keepalive(params['keepalive']),
        amnezia: _amnezia(params),
      );
      final name = parsed.fragment.isEmpty ? 'WireGuard $host' : Uri.decodeComponent(parsed.fragment);
      return _config(host, port, settings, name, uri);
    } catch (_) {
      return null;
    }
  }

  /// `wireguard://` link for the profile (export, deduplication, `rawUri` from `.conf`).
  static String toUri(VpnConfig config) {
    final wg = config.protocolSettings! as WireGuardSettings;
    final host = config.address.contains(':') ? '[${config.address}]' : config.address;
    final params = <String, String>{
      'publickey': wg.peerPublicKey,
      'presharedkey': ?wg.presharedKey,
      'address': wg.addresses.join(','),
      'mtu': ?wg.mtu?.toString(),
      'reserved': ?wg.reserved?.join(','),
      'allowedips': wg.allowedIps.join(','),
      'keepalive': ?wg.keepalive?.toString(),
    };
    final amnezia = {
      for (final e in (wg.amnezia?.toJson() ?? const {}).entries)
        e.key.replaceAll('_', ''): Uri.encodeComponent('${e.value}'),
    };
    final query = [
      ...params.entries.map((e) => '${e.key}=${_encodeList(e.value)}'),
      ...amnezia.entries.map((e) => '${e.key}=${e.value}'),
    ].join('&');
    return 'wireguard://${Uri.encodeComponent(wg.privateKey)}@$host:${config.port}?$query'
        '#${Uri.encodeComponent(config.name)}';
  }

  static VpnConfig _config(String host, int port, WireGuardSettings settings, String name, String? rawUri) => VpnConfig(
    id: const Uuid().v4(),
    name: name,
    protocol: VpnProtocol.wireguard,
    address: host,
    port: port,
    uuid: '',
    security: VpnSecurity.none,
    transport: VpnTransport.tcp,
    createdAt: DateTime.now(),
    rawUri: rawUri,
    protocolSettings: settings,
  );

  /// AmneziaWG keys: in `.conf` — as in amneziawg-go (`Jc`, `HeaderProtectionKey`…), in a link —
  /// the same in lowercase; the value is the `AmneziaParams` JSON key.
  static const _amneziaInts = ['jc', 'jmin', 'jmax', 's1', 's2', 's3', 's4'];
  static const _amneziaStrings = {
    'h1': 'h1',
    'h2': 'h2',
    'h3': 'h3',
    'h4': 'h4',
    'i1': 'i1',
    'i2': 'i2',
    'i3': 'i3',
    'i4': 'i4',
    'i5': 'i5',
    'headerprotectionkey': 'header_protection_key',
    'contentpaddingaddition': 'content_padding_addition',
    'rekeyaftertime': 'rekey_after_time',
    'rekeytimeout': 'rekey_timeout',
    'rejectaftertime': 'reject_after_time',
    'keepalivetimeout': 'keepalive_timeout',
    'maxhandshakeattempts': 'max_handshake_attempts',
  };
  static const _amneziaFlags = {'randomtrailers': 'random_trailers', 'disablecookies': 'disable_cookies'};

  /// null — the config has no AmneziaWG parameters (plain WireGuard).
  static AmneziaParams? _amnezia(Map<String, String> values) {
    final json = <String, dynamic>{
      for (final key in _amneziaInts) key: ?int.tryParse(values[key] ?? ''),
      for (final e in _amneziaStrings.entries) e.value: ?_nonEmpty(values[e.key]),
      for (final e in _amneziaFlags.entries)
        if (const {'on', 'true', '1'}.contains(values[e.key]?.trim().toLowerCase())) e.value: true,
    };
    return json.isEmpty ? null : AmneziaParams.fromJson(json);
  }

  static List<({String name, Map<String, String> values})> _sections(String text) {
    final sections = <({String name, Map<String, String> values})>[];
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      // As in wg-quick: everything after `#` is a comment.
      final hash = raw.indexOf('#');
      final line = (hash < 0 ? raw : raw.substring(0, hash)).trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        sections.add((name: line.substring(1, line.length - 1).trim().toLowerCase(), values: {}));
        continue;
      }
      final eq = line.indexOf('=');
      if (eq <= 0 || sections.isEmpty) continue;
      final key = line.substring(0, eq).trim().toLowerCase();
      final value = line.substring(eq + 1).trim();
      final values = sections.last.values;
      // wg-quick accumulates repeated Address/AllowedIPs.
      values[key] = _repeatable.contains(key) && values.containsKey(key) ? '${values[key]},$value' : value;
    }
    return sections;
  }

  static String _required(Map<String, String> values, String key, String label) =>
      _nonEmpty(values[key]) ?? (throw ReasonException(AppMessage.l10n((l) => l.wgMissingKey(label))));

  static String? _nonEmpty(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();

  static const _repeatable = {'address', 'allowedips'};

  static List<String> _list(String? v) => (v ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  /// An address without a mask (allowed in wg-quick) is a single host: /32 or /128.
  static List<String> _prefixes(String? v) => [
    for (final p in _list(v)) p.contains('/') ? p : (p.contains(':') ? '$p/128' : '$p/32'),
  ];

  static List<String> _allowedIps(String? v) {
    final ips = _prefixes(v);
    return ips.isEmpty ? const ['0.0.0.0/0', '::/0'] : ips;
  }

  static List<int>? _reserved(String? v) {
    final parts = _list(v).map(int.tryParse).toList();
    return parts.length == 3 && parts.every((p) => p != null) ? parts.cast<int>() : null;
  }

  /// AmneziaWG allows a `22-30` range — the lower bound is taken.
  static int? _keepalive(String? v) => int.tryParse((v ?? '').split('-').first.trim());

  /// `host:port` or `[v6]:port`.
  static (String, int) _endpoint(String value) {
    final match = RegExp(r'^\[(.+)\]:(\d+)$').firstMatch(value) ?? RegExp(r'^([^:]+):(\d+)$').firstMatch(value);
    if (match == null) throw ReasonException(AppMessage.l10n((l) => l.wgInvalidEndpoint(value)));
    return (match.group(1)!, int.parse(match.group(2)!));
  }

  /// Query values without turning `+` into a space (keys are base64).
  static Map<String, String> _query(String query) => {
    for (final part in query.split('&').where((p) => p.contains('=')))
      part.substring(0, part.indexOf('=')).toLowerCase(): Uri.decodeComponent(part.substring(part.indexOf('=') + 1)),
  };

  static String _encodeList(String value) => value.split(',').map(Uri.encodeComponent).join(',');
}
