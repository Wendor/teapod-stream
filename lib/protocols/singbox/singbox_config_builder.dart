import 'dart:convert';

import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/app_message.dart';
import '../../core/models/protocol_settings.dart';
import '../../core/models/vpn_config.dart';
import '../../core/models/vpn_log_entry.dart';
import 'singbox_outbound.dart';
import 'singbox_route.dart';

/// sing-box 1.14 config for a profile and app settings.
abstract final class SingBoxConfigBuilder {
  /// Shadowsocks methods available in sing-box.
  static const ssMethods = {
    'none',
    'aes-128-gcm',
    'aes-192-gcm',
    'aes-256-gcm',
    'chacha20-ietf-poly1305',
    'xchacha20-ietf-poly1305',
    '2022-blake3-aes-128-gcm',
    '2022-blake3-aes-256-gcm',
    '2022-blake3-chacha20-poly1305',
  };

  static Map<String, dynamic> build(VpnConfig config, VpnEngineOptions options) => {
    'log': {
      'level': switch (options.logLevel) {
        LogLevel.debug => 'debug',
        // sing-box info is a line per connection (browsing history in vpn_log.txt).
        LogLevel.info || LogLevel.warning => 'warn',
        LogLevel.error => 'error',
      },
      'timestamp': false,
    },
    'dns': SingBoxRoute.dns(options, tcpOnlyProxy: SingBoxOutbound.isTcpOnly(config)),
    'inbounds': [
      {
        'type': 'mixed',
        'tag': SingBoxRoute.inboundTag,
        'listen': SingBoxRoute.listen,
        'listen_port': options.socksPort,
        if (options.socksUser.isNotEmpty)
          'users': [
            {'username': options.socksUser, 'password': options.socksPassword},
          ],
      },
    ],
    ..._proxy(config, options),
    'route': SingBoxRoute.route(options),
  };

  static String buildJson(VpnConfig config, VpnEngineOptions options) => jsonEncode(build(config, options));

  /// Temporary instance for latency measurement: no inbounds and no logs.
  static String buildProbeJson(VpnConfig config, VpnEngineOptions options) {
    final json = build(config, options)..remove('inbounds');
    json['log'] = {'disabled': true};
    return jsonEncode(json);
  }

  static Map<String, dynamic> _proxy(VpnConfig config, VpnEngineOptions options) {
    final proxy = SingBoxOutbound.build(config, options);
    const direct = {'type': 'direct', 'tag': SingBoxRoute.directTag};
    return SingBoxOutbound.isEndpoint(config)
        ? {
            'endpoints': [proxy],
            'outbounds': [direct],
          }
        : {
            'outbounds': [proxy, direct],
          };
  }

  /// null — the profile runs on sing-box; otherwise the reason.
  static AppMessage? unsupportedReason(VpnConfig config) {
    if (config.rawXrayConfig != null) return AppMessage.l10n((l) => l.singboxNoRawConfig);
    if (config.transport == VpnTransport.xhttp || config.transport == VpnTransport.splithttp) {
      return AppMessage.l10n((l) => l.singboxNoXhttp);
    }
    if ((config.xhttpExtra?.isNotEmpty ?? false) || (config.finalmask?.isNotEmpty ?? false)) {
      return AppMessage.l10n((l) => l.singboxNoXrayExtra);
    }
    if (config.protocol != VpnProtocol.hysteria2 && (config.mux ?? false)) {
      return AppMessage.l10n((l) => l.singboxLinkMux);
    }
    if (config.pinSHA256?.trim().isNotEmpty ?? false) {
      return AppMessage.l10n((l) => l.singboxNoCertPin);
    }
    switch (config.protocol) {
      case VpnProtocol.vless:
        final encryption = config.encryption?.trim() ?? '';
        if (encryption.isNotEmpty && encryption != 'none') return AppMessage.l10n((l) => l.singboxNoVlessEncryption);
        final flow = config.flow?.trim() ?? '';
        if (flow.isNotEmpty && flow != 'xtls-rprx-vision') return AppMessage.l10n((l) => l.singboxFlow(flow));
      case VpnProtocol.shadowsocks:
        if (config.plugin != null) {
          return AppMessage.l10n((l) => l.singboxNoSsPlugins);
        }
        final method = config.method ?? 'chacha20-ietf-poly1305';
        if (!ssMethods.contains(method)) return AppMessage.l10n((l) => l.singboxSsMethod(method));
      case VpnProtocol.vmess || VpnProtocol.trojan || VpnProtocol.hysteria2:
        break;
      case VpnProtocol.wireguard || VpnProtocol.ssh || VpnProtocol.naive:
        if (config.validate() case final error?) return error;
        if (config.protocolSettings case WireGuardSettings(:final amnezia?, :final reserved)) {
          if (reserved?.isNotEmpty ?? false) return AppMessage.l10n((l) => l.singboxAwgReserved);
          final paddings = [amnezia.s1, amnezia.s2, amnezia.s3, amnezia.s4];
          if ((amnezia.headerProtectionKey?.isNotEmpty ?? false) && paddings.any((s) => (s ?? 0) < 12)) {
            return AppMessage.l10n((l) => l.singboxAwgHeaders);
          }
        }
    }
    if (config.tcpHttpHeader) return AppMessage.l10n((l) => l.singboxNoTcpHttp);
    return null;
  }
}
