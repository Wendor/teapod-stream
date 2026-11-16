import 'dart:convert';
import 'dart:io';

import '../../core/models/vpn_config.dart';
import 'wireguard_parser.dart';

/// AmneziaVPN app `vpn://` keys: base64url(qCompress(server JSON)),
/// qCompress = 4 bytes of big-endian length + zlib. The AWG/WireGuard client config is
/// wg-quick text in `containers[].awg|wireguard.last_config` (a JSON string, the `config` field).
abstract final class AmneziaKeyParser {
  static const _protocols = ['awg', 'wireguard'];
  static final _mtuLine = RegExp(r'^\s*MTU\s*=', multiLine: true, caseSensitive: false);
  static final _interface = RegExp(r'\[Interface\]', caseSensitive: false);

  /// null — not an AmneziaVPN key or it has no WireGuard/AWG client config.
  static VpnConfig? parse(String key) {
    if (!key.startsWith('vpn://')) return null;
    try {
      var data = key.substring('vpn://'.length).trim();
      data = data.padRight((data.length + 3) ~/ 4 * 4, '=');
      final compressed = base64Url.decode(data);
      final server = jsonDecode(utf8.decode(zlib.decode(compressed.sublist(4)))) as Map<String, dynamic>;
      for (final container in (server['containers'] as List? ?? const []).cast<Map<String, dynamic>>()) {
        for (final protocol in _protocols) {
          final lastConfig = (container[protocol] as Map<String, dynamic>?)?['last_config'] as String?;
          if (lastConfig == null) continue;
          final last = jsonDecode(lastConfig) as Map<String, dynamic>;
          var text = last['config'] as String?;
          if (text == null || !WireGuardParser.isConf(text)) continue;
          // AmneziaVPN puts the MTU into last_config, not into the config text.
          final mtu = int.tryParse('${last['mtu'] ?? ''}');
          if (mtu != null && !_mtuLine.hasMatch(text)) text = text.replaceFirst(_interface, '[Interface]\nMTU = $mtu');
          final name = server['description'] as String?;
          return WireGuardParser.parseConf(text, name: (name?.isNotEmpty ?? false) ? name : null);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
