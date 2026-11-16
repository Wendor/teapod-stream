import 'dart:convert';

import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/protocol_settings.dart';
import '../../core/models/vpn_config.dart';
import '../../core/models/vpn_log_entry.dart';
import '../xray/vless_parser.dart';
import 'singbox_outbound.dart';
import 'singbox_route.dart';
import '../../l10n/l10n.dart';

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
  static String? unsupportedReason(VpnConfig config) {
    if (config.rawXrayConfig != null) return L10n.current.singboxNoRawConfig;
    if (config.transport == VpnTransport.xhttp || config.transport == VpnTransport.splithttp) {
      return L10n.current.singboxNoXhttp;
    }
    if ((config.xhttpExtra?.isNotEmpty ?? false) || (config.finalmask?.isNotEmpty ?? false)) {
      return L10n.current.singboxNoXrayExtra;
    }
    if (config.pinSHA256?.trim().isNotEmpty ?? false) {
      return L10n.current.singboxNoCertPin;
    }
    switch (config.protocol) {
      case VpnProtocol.vless:
        final encryption = config.encryption?.trim() ?? '';
        if (encryption.isNotEmpty && encryption != 'none') return L10n.current.singboxNoVlessEncryption;
        final flow = config.flow?.trim() ?? '';
        if (flow.isNotEmpty && flow != 'xtls-rprx-vision') return L10n.current.singboxFlow(flow);
      case VpnProtocol.shadowsocks:
        if (VlessParser.linkParams(config)['plugin']?.trim().isNotEmpty ?? false) {
          return L10n.current.singboxNoSsPlugins;
        }
        final method = config.method ?? 'chacha20-ietf-poly1305';
        if (!ssMethods.contains(method)) return L10n.current.singboxSsMethod(method);
      case VpnProtocol.vmess || VpnProtocol.trojan || VpnProtocol.hysteria2:
        break;
      case VpnProtocol.wireguard || VpnProtocol.ssh || VpnProtocol.naive:
        if (config.validate() case final error?) return error;
        if (config.protocolSettings case WireGuardSettings(:final amnezia?, :final reserved)) {
          if (reserved?.isNotEmpty ?? false) return L10n.current.singboxAwgReserved;
          final paddings = [amnezia.s1, amnezia.s2, amnezia.s3, amnezia.s4];
          if ((amnezia.headerProtectionKey?.isNotEmpty ?? false) && paddings.any((s) => (s ?? 0) < 12)) {
            return L10n.current.singboxAwgHeaders;
          }
        }
    }
    if (_tcpHttpHeader(config)) return L10n.current.singboxNoTcpHttp;
    return null;
  }

  static bool _tcpHttpHeader(VpnConfig config) {
    if (config.transport != VpnTransport.tcp || config.protocol == VpnProtocol.hysteria2) return false;
    final type = config.protocol == VpnProtocol.vmess
        ? VlessParser.vmessJson(config)['type']?.toString()
        : VlessParser.linkParams(config)['headerType'];
    return type?.trim().toLowerCase() == 'http';
  }
}
