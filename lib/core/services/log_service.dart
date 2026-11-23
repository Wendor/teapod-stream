import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_constants.dart';
import '../models/subscription.dart';
import '../models/vpn_config.dart';
import '../models/vpn_log_entry.dart';

class _CircularBuffer {
  final List<VpnLogEntry?> _buffer;
  int _head = 0;
  int _count = 0;

  _CircularBuffer(int capacity) : _buffer = List<VpnLogEntry?>.filled(capacity, null);

  void add(VpnLogEntry entry) {
    _buffer[_head] = entry;
    _head = (_head + 1) % _buffer.length;
    if (_count < _buffer.length) _count++;
  }

  void clear() {
    _head = 0;
    _count = 0;
    _buffer.fillRange(0, _buffer.length, null);
  }

  List<VpnLogEntry> toList() {
    if (_count < _buffer.length) {
      return _buffer.whereType<VpnLogEntry>().toList();
    }
    return List.generate(_buffer.length, (i) => _buffer[(_head + i) % _buffer.length]!);
  }
}

class LogService extends Notifier<List<VpnLogEntry>> {
  late final _CircularBuffer _buffer;

  @override
  List<VpnLogEntry> build() {
    _buffer = _CircularBuffer(AppConstants.maxLogEntries);
    return [];
  }

  void add(VpnLogEntry entry) {
    _buffer.add(entry);
    state = _buffer.toList();
  }

  void addInfo(String message, {String? source}) => add(VpnLogEntry.info(message, source: source));

  void addError(String message, {String? source}) => add(VpnLogEntry.error(message, source: source));

  void addWarning(String message, {String? source}) => add(VpnLogEntry.warning(message, source: source));

  void addDebug(String message, {String? source}) => add(VpnLogEntry.debug(message, source: source));

  void loadFromEntries(List<VpnLogEntry> entries) {
    _buffer.clear();
    for (final e in entries) {
      _buffer.add(e);
    }
    state = _buffer.toList();
  }

  void clear() {
    _buffer.clear();
    state = [];
  }
}

final logServiceProvider = NotifierProvider<LogService, List<VpnLogEntry>>(LogService.new);

/// Values from saved connections and settings that [maskLog] hides: server addresses, SNI and host headers, UUIDs,
/// passwords, share links, subscription URLs and their hosts, plus [extra] (SOCKS credentials).
List<String> logSecrets({
  Iterable<VpnConfig> configs = const [],
  Iterable<Subscription> subscriptions = const [],
  Iterable<String> extra = const [],
}) => [
  for (final c in configs) ...[c.address, c.uuid, ?c.sni, ?c.wsHost, ?c.password, ?c.obfsPassword, ?c.rawUri],
  for (final s in subscriptions) ...[s.url, ?Uri.tryParse(s.url)?.host],
  ...extra,
];

final _uuid = RegExp(r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b');
final _keyValue = RegExp(
  r'''\b(user(?:name)?|pass(?:word|wd)?|pwd|token|secret|auth|key|pbk|sid|obfs-password)=[^\s&,;"']+''',
  caseSensitive: false,
);
final _jsonSecret = RegExp(
  r'"(user(?:name)?|pass(?:word)?|id|uuid|token|secret|publicKey|privateKey|shortId)"\s*:\s*"[^"]*"',
  caseSensitive: false,
);
final _ipv4 = RegExp(r'(?<![\w.])(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?!\w|\.\d)');
final _ipv6 = RegExp(r'(?<![\w:.])[0-9A-Fa-f]{0,4}(?::[0-9A-Fa-f]{0,4}){2,7}(?![\w:])');

/// Shorter known values are not replaced literally: they would hit unrelated text.
const _minSecretLength = 4;

/// Masks a log before it leaves the device: [secrets] (see [logSecrets]), UUIDs, `user=`/`pass=`-like values and
/// public IPv4/IPv6 addresses. Loopback, private and link-local addresses stay: they are the device's own and help
/// debugging.
String maskLog(String text, {Iterable<String> secrets = const []}) {
  final known = {
    for (final s in secrets)
      if (s.trim().length >= _minSecretLength) s.trim(),
  }.toList()..sort((a, b) => b.length.compareTo(a.length));
  var out = text;
  if (known.isNotEmpty) {
    final alternatives = known.map(RegExp.escape).join('|');
    out = out.replaceAll(RegExp('(?<![\\w-])(?:$alternatives)(?![\\w-])', caseSensitive: false), '<hidden>');
  }
  return out
      .replaceAll(_uuid, '<uuid>')
      .replaceAllMapped(_keyValue, (m) => '${m[1]}=<hidden>')
      .replaceAllMapped(_jsonSecret, (m) => '"${m[1]}":"<hidden>"')
      .replaceAllMapped(_ipv4, (m) => _isPublicIpv4(m) ? '<ip>' : m[0]!)
      .replaceAllMapped(_ipv6, (m) => _isPublicIpv6(m[0]!) ? '<ip>' : m[0]!);
}

bool _isPublicIpv4(Match m) {
  final o = [for (var i = 1; i <= 4; i++) int.parse(m[i]!)];
  if (o.any((v) => v > 255)) return false; // not an address
  final (a, b) = (o[0], o[1]);
  final local =
      a == 0 ||
      a == 10 ||
      a == 127 ||
      (a == 100 && b >= 64 && b <= 127) || // CGNAT
      (a == 169 && b == 254) ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 192 && b == 168) ||
      a >= 224; // multicast, reserved
  return !local;
}

bool _isPublicIpv6(String s) {
  final List<int> bytes;
  try {
    bytes = Uri.parseIPv6Address(s);
  } on FormatException {
    return false; // times, MAC addresses and other colon-separated text
  }
  if (bytes.take(15).every((b) => b == 0)) return false; // :: and ::1
  final linkLocal = bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80; // fe80::/10
  final uniqueLocal = bytes[0] & 0xfe == 0xfc; // fc00::/7
  return !linkLocal && !uniqueLocal && bytes[0] != 0xff; // ff00::/8 multicast
}
