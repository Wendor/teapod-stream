import 'dart:convert';
import 'dart:io';

import '../../core/models/vpn_config.dart';
import 'wireguard_parser.dart';

/// Ключи `vpn://` приложения AmneziaVPN: base64url(qCompress(JSON сервера)),
/// qCompress = 4 байта длины big-endian + zlib. Клиентский конфиг AWG/WireGuard —
/// wg-quick-текст в `containers[].awg|wireguard.last_config` (строка JSON, поле `config`).
abstract final class AmneziaKeyParser {
  static const _protocols = ['awg', 'wireguard'];
  static final _mtuLine = RegExp(r'^\s*MTU\s*=', multiLine: true, caseSensitive: false);
  static final _interface = RegExp(r'\[Interface\]', caseSensitive: false);

  /// null — не ключ AmneziaVPN или в нём нет клиентского конфига WireGuard/AWG.
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
          // AmneziaVPN кладёт MTU в last_config, а не в текст конфига.
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
