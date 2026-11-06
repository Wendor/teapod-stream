import 'package:uuid/uuid.dart';

import '../../core/models/protocol_settings.dart';
import '../../core/models/vpn_config.dart';

/// `ssh://user[:password]@host[:port]?pk=<ключ>&pkp=<passphrase>&hk=<host key>,…#имя`.
/// `pk`/`hk` — как в hiddify (ray2sing); `pkp` — passphrase ключа.
abstract final class SshParser {
  static const _pemHead = '-----BEGIN OPENSSH PRIVATE KEY-----';
  static const _pemTail = '-----END OPENSSH PRIVATE KEY-----';

  /// null — не ssh:// или нет ни пароля, ни ключа.
  static VpnConfig? parseUri(String uri) {
    try {
      final parsed = Uri.parse(uri);
      if (parsed.scheme != 'ssh' || parsed.host.isEmpty) return null;
      final userInfo = parsed.userInfo;
      final colon = userInfo.indexOf(':');
      final user = Uri.decodeComponent(colon < 0 ? userInfo : userInfo.substring(0, colon));
      final password = colon < 0 ? null : Uri.decodeComponent(userInfo.substring(colon + 1));
      final params = _query(parsed.query);
      final key = _privateKey(params['pk']);
      if (user.isEmpty || ((password?.isEmpty ?? true) && key == null)) return null;
      final host = parsed.host;
      return VpnConfig(
        id: const Uuid().v4(),
        name: parsed.fragment.isEmpty ? 'SSH $host' : Uri.decodeComponent(parsed.fragment),
        protocol: VpnProtocol.ssh,
        address: host,
        port: parsed.hasPort ? parsed.port : 22,
        uuid: '',
        security: VpnSecurity.none,
        transport: VpnTransport.tcp,
        createdAt: DateTime.now(),
        rawUri: uri,
        protocolSettings: SshSettings(
          user: user,
          password: (password?.isEmpty ?? true) ? null : password,
          privateKey: key,
          privateKeyPassphrase: (params['pkp']?.isEmpty ?? true) ? null : params['pkp'],
          hostKeys: (params['hk'] ?? '').split(',').map((k) => k.trim()).where((k) => k.isNotEmpty).toList(),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Полный PEM оставляется как есть; голое тело оборачивается в OpenSSH PEM.
  static String? _privateKey(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.contains('-----BEGIN ') && !v.contains(_pemHead)) return '$v\n';
    final body = v.replaceAll(_pemHead, '').replaceAll(_pemTail, '').trim();
    return '$_pemHead\n$body\n$_pemTail\n';
  }

  /// Значения query без превращения `+` в пробел (ключи в base64).
  static Map<String, String> _query(String query) => {
        for (final part in query.split('&').where((p) => p.contains('=')))
          part.substring(0, part.indexOf('=')).toLowerCase(): Uri.decodeComponent(part.substring(part.indexOf('=') + 1)),
      };
}
