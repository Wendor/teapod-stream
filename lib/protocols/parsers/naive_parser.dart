import 'package:uuid/uuid.dart';

import '../../core/models/protocol_settings.dart';
import '../../core/models/vpn_config.dart';

/// NaiveProxy: `naive+https://user:pass@host[:port]?extra-headers=…#имя` и `naive+quic://`.
/// `extra-headers` — строки `Имя: значение`, разделённые `\r\n`.
abstract final class NaiveParser {
  /// null — не naive-ссылка или нет логина/пароля.
  static VpnConfig? parseUri(String uri) {
    try {
      final parsed = Uri.parse(uri);
      final quic = parsed.scheme == 'naive+quic';
      if (!quic && parsed.scheme != 'naive+https') return null;
      final colon = parsed.userInfo.indexOf(':');
      if (colon <= 0 || parsed.host.isEmpty) return null;
      final user = Uri.decodeComponent(parsed.userInfo.substring(0, colon));
      final password = Uri.decodeComponent(parsed.userInfo.substring(colon + 1));
      if (password.isEmpty) return null;
      final host = parsed.host;
      return VpnConfig(
        id: const Uuid().v4(),
        name: parsed.fragment.isEmpty ? 'Naive $host' : Uri.decodeComponent(parsed.fragment),
        protocol: VpnProtocol.naive,
        address: host,
        port: parsed.hasPort ? parsed.port : 443,
        uuid: '',
        security: VpnSecurity.tls,
        transport: VpnTransport.tcp,
        createdAt: DateTime.now(),
        rawUri: uri,
        protocolSettings: NaiveSettings(
          user: user,
          password: password,
          quic: quic,
          extraHeaders: _headers(parsed.queryParameters['extra-headers'] ?? ''),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, String> _headers(String raw) => {
        for (final line in raw.split(RegExp(r'\r?\n')))
          if (line.indexOf(':') case final i when i > 0) line.substring(0, i).trim(): line.substring(i + 1).trim(),
      };
}
