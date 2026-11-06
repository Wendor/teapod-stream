import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/protocol_settings.dart';
import '../../core/models/vpn_config.dart';

/// Outbound (или endpoint) прокси в формате sing-box 1.14; тег всегда `proxy`.
abstract final class SingBoxOutbound {
  static const tag = 'proxy';

  /// WireGuard/AmneziaWG в sing-box — endpoint, а не outbound.
  static bool isEndpoint(VpnConfig config) => config.protocol == VpnProtocol.wireguard;

  /// Outbound без UDP: SSH и Naive (UDP только через udp_over_tcp, его серверы не обязаны уметь).
  static bool isTcpOnly(VpnConfig config) =>
      config.protocol == VpnProtocol.ssh || config.protocol == VpnProtocol.naive;

  static Map<String, dynamic> build(VpnConfig config, VpnEngineOptions options) {
    final server = {'tag': tag, 'server': config.address, 'server_port': config.port};
    return switch (config.protocol) {
      VpnProtocol.vless => {
          'type': 'vless',
          ...server,
          'uuid': config.uuid,
          if (config.flow?.isNotEmpty ?? false) 'flow': config.flow,
          'packet_encoding': 'xudp',
          ..._tlsAndTransport(config, options),
        },
      VpnProtocol.vmess => {
          'type': 'vmess',
          ...server,
          'uuid': config.uuid,
          'security': 'auto',
          'alter_id': 0,
          'packet_encoding': 'xudp',
          ..._tlsAndTransport(config, options),
        },
      VpnProtocol.trojan => {
          'type': 'trojan',
          ...server,
          'password': config.password ?? '',
          ..._tlsAndTransport(config, options),
        },
      VpnProtocol.shadowsocks => {
          'type': 'shadowsocks',
          ...server,
          'method': config.method ?? 'chacha20-ietf-poly1305',
          'password': config.password ?? '',
        },
      VpnProtocol.hysteria2 => _hysteria2(config, options),
      VpnProtocol.wireguard => _wireguard(config, config.protocolSettings! as WireGuardSettings),
      VpnProtocol.ssh => _ssh(config, config.protocolSettings! as SshSettings),
      VpnProtocol.naive => _naive(config, config.protocolSettings! as NaiveSettings),
    };
  }

  /// WireGuard — встроенный endpoint sing-box; AmneziaWG — `awg` из teapod-core.
  static Map<String, dynamic> _wireguard(VpnConfig config, WireGuardSettings wg) => {
        'type': wg.amnezia == null ? 'wireguard' : 'awg',
        'tag': tag,
        'address': wg.addresses,
        'private_key': wg.privateKey,
        'mtu': ?wg.mtu,
        'peers': [
          {
            'address': config.address,
            'port': config.port,
            'public_key': wg.peerPublicKey,
            'pre_shared_key': ?wg.presharedKey,
            'allowed_ips': wg.allowedIps,
            'persistent_keepalive_interval': ?wg.keepalive,
            'reserved': ?wg.reserved,
          },
        ],
        if (wg.amnezia case final amnezia?)
          'amnezia': {
            for (final e in amnezia.toJson().entries)
              if (e.value != 0 && e.value != '') e.key: e.value,
          },
      };

  static Map<String, dynamic> _ssh(VpnConfig config, SshSettings ssh) => {
        'type': 'ssh',
        'tag': tag,
        'server': config.address,
        'server_port': config.port,
        'user': ssh.user,
        'password': ?ssh.password,
        if (ssh.privateKey case final key?) 'private_key': [key],
        'private_key_passphrase': ?ssh.privateKeyPassphrase,
        if (ssh.hostKeys.isNotEmpty) 'host_key': ssh.hostKeys,
      };

  static Map<String, dynamic> _naive(VpnConfig config, NaiveSettings naive) => {
        'type': 'naive',
        'tag': tag,
        'server': config.address,
        'server_port': config.port,
        'username': naive.user,
        'password': naive.password,
        if (naive.quic) 'quic': true,
        if (naive.extraHeaders.isNotEmpty) 'extra_headers': naive.extraHeaders,
        'tls': {'enabled': true, 'server_name': config.address},
      };

  static Map<String, dynamic> _hysteria2(VpnConfig config, VpnEngineOptions options) {
    final hop = config.hopPorts?.trim() ?? '';
    return {
      'type': 'hysteria2',
      'tag': tag,
      'server': config.address,
      if (hop.isEmpty) 'server_port': config.port else 'server_ports': hopRanges(hop),
      'password': config.password ?? '',
      if (config.obfsPassword?.isNotEmpty ?? false) 'obfs': {'type': 'salamander', 'password': config.obfsPassword},
      // QUIC требует стандартный TLS-стек: uTLS для Hysteria2 не включается.
      'tls': _tls(config, options, reality: false, utls: false),
    };
  }

  /// `20000-30000,443` → `["20000:30000","443:443"]`.
  static List<String> hopRanges(String spec) => [
        for (final part in spec.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty))
          part.contains('-') ? part.replaceFirst('-', ':') : '$part:$part',
      ];

  static Map<String, dynamic> _tlsAndTransport(VpnConfig config, VpnEngineOptions options) {
    final transport = _transport(config);
    return {
      if (config.security != VpnSecurity.none)
        'tls': _tls(config, options, reality: config.security == VpnSecurity.reality),
      'transport': ?transport,
    };
  }

  static Map<String, dynamic> _tls(VpnConfig config, VpnEngineOptions options,
      {required bool reality, bool utls = true}) {
    final fingerprint = options.tlsFingerprint.xrayValue ?? config.fingerprint;
    final alpn = (config.alpn ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final fragment = options.fragment;
    return {
      'enabled': true,
      if (config.sni?.isNotEmpty ?? false) 'server_name': config.sni,
      if (config.allowInsecure) 'insecure': true,
      if (alpn.isNotEmpty) 'alpn': alpn,
      if (utls && (reality || (fingerprint?.isNotEmpty ?? false)))
        'utls': {'enabled': true, 'fingerprint': (fingerprint?.isNotEmpty ?? false) ? fingerprint : 'chrome'},
      if (reality)
        'reality': {'enabled': true, 'public_key': config.publicKey ?? '', 'short_id': config.shortId ?? ''},
      if (config.ech?.isNotEmpty ?? false) 'ech': _ech(config.ech!),
      if (!reality && fragment.enabled && fragment.packets.trim() == 'tlshello') 'fragment': true,
    };
  }

  /// xray `ech`: base64 ECHConfigList или `[домен+]DNS-сервер` — запрос HTTPS-записи.
  static Map<String, dynamic> _ech(String value) {
    if (!value.contains('://')) {
      return {
        'enabled': true,
        'config': ['-----BEGIN ECH CONFIGS-----', value, '-----END ECH CONFIGS-----'],
      };
    }
    final plus = value.indexOf('+');
    final domain = plus > 0 && plus < value.indexOf('://') ? value.substring(0, plus) : '';
    return {'enabled': true, if (domain.isNotEmpty) 'query_server_name': domain};
  }

  static Map<String, dynamic>? _transport(VpnConfig config) {
    final path = config.wsPath?.isNotEmpty ?? false ? config.wsPath! : '/';
    final host = config.wsHost ?? '';
    switch (config.transport) {
      case VpnTransport.ws:
        final uri = Uri.parse(path);
        final earlyData = int.tryParse(uri.queryParameters['ed'] ?? '');
        final rest = Map.of(uri.queryParameters)..remove('ed');
        return {
          'type': 'ws',
          'path': earlyData == null ? path : Uri(path: uri.path, queryParameters: rest.isEmpty ? null : rest).toString(),
          if (host.isNotEmpty) 'headers': {'Host': host},
          if (earlyData != null) ...{
            'max_early_data': earlyData,
            'early_data_header_name': 'Sec-WebSocket-Protocol',
          },
        };
      case VpnTransport.grpc:
        return {'type': 'grpc', 'service_name': config.grpcServiceName ?? ''};
      case VpnTransport.http2:
        return {'type': 'http', if (host.isNotEmpty) 'host': [host], 'path': path};
      case VpnTransport.httpupgrade:
        return {'type': 'httpupgrade', if (host.isNotEmpty) 'host': host, 'path': path};
      case VpnTransport.quic:
        return {'type': 'quic'};
      case VpnTransport.tcp:
      case VpnTransport.xhttp:
      case VpnTransport.splithttp:
        return null;
    }
  }
}
