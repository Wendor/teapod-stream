import 'dart:convert';

import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/protocol_settings.dart';
import '../../core/models/vpn_config.dart';
import '../../core/models/vpn_log_entry.dart';
import '../xray/vless_parser.dart';
import 'singbox_outbound.dart';
import 'singbox_route.dart';

/// Конфиг sing-box 1.14 для профиля и настроек приложения.
abstract final class SingBoxConfigBuilder {
  /// Методы Shadowsocks, которые есть в sing-box.
  static const ssMethods = {
    'none', 'aes-128-gcm', 'aes-192-gcm', 'aes-256-gcm', 'chacha20-ietf-poly1305', 'xchacha20-ietf-poly1305',
    '2022-blake3-aes-128-gcm', '2022-blake3-aes-256-gcm', '2022-blake3-chacha20-poly1305',
  };

  static Map<String, dynamic> build(VpnConfig config, VpnEngineOptions options) => {
        'log': {
          'level': switch (options.logLevel) {
            LogLevel.debug => 'debug',
            // info у sing-box — строка на каждое соединение (история посещений в vpn_log.txt).
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

  /// Временный инстанс для замера задержки: без inbound'ов и логов.
  static String buildProbeJson(VpnConfig config, VpnEngineOptions options) {
    final json = build(config, options)..remove('inbounds');
    json['log'] = {'disabled': true};
    return jsonEncode(json);
  }

  static Map<String, dynamic> _proxy(VpnConfig config, VpnEngineOptions options) {
    final proxy = SingBoxOutbound.build(config, options);
    const direct = {'type': 'direct', 'tag': SingBoxRoute.directTag};
    return SingBoxOutbound.isEndpoint(config)
        ? {'endpoints': [proxy], 'outbounds': [direct]}
        : {'outbounds': [proxy, direct]};
  }

  /// null — профиль запускается на sing-box; иначе причина.
  static String? unsupportedReason(VpnConfig config) {
    if (config.rawXrayConfig != null) return 'Полный JSON-конфиг Xray недоступен в ядре sing-box.';
    if (config.transport == VpnTransport.xhttp || config.transport == VpnTransport.splithttp) {
      return 'Транспорт XHTTP недоступен в ядре sing-box.';
    }
    if ((config.xhttpExtra?.isNotEmpty ?? false) || (config.finalmask?.isNotEmpty ?? false)) {
      return 'Расширенные настройки Xray (finalmask/extra) недоступны в ядре sing-box.';
    }
    if (config.pinSHA256?.trim().isNotEmpty ?? false) {
      return 'Pin сертификата не поддерживается ядром sing-box: оно проверяет только хеш открытого ключа.';
    }
    switch (config.protocol) {
      case VpnProtocol.vless:
        final encryption = config.encryption?.trim() ?? '';
        if (encryption.isNotEmpty && encryption != 'none') return 'VLESS Encryption недоступен в ядре sing-box.';
        final flow = config.flow?.trim() ?? '';
        if (flow.isNotEmpty && flow != 'xtls-rprx-vision') return 'Flow «$flow» недоступен в ядре sing-box.';
      case VpnProtocol.shadowsocks:
        if (VlessParser.linkParams(config)['plugin']?.trim().isNotEmpty ?? false) {
          return 'Плагины Shadowsocks недоступны в ядре sing-box.';
        }
        final method = config.method ?? 'chacha20-ietf-poly1305';
        if (!ssMethods.contains(method)) return 'Метод Shadowsocks «$method» недоступен в ядре sing-box.';
      case VpnProtocol.vmess || VpnProtocol.trojan || VpnProtocol.hysteria2:
        break;
      case VpnProtocol.wireguard || VpnProtocol.ssh || VpnProtocol.naive:
        if (config.validate() case final error?) return error;
        if (config.protocolSettings case WireGuardSettings(:final amnezia?, :final reserved)) {
          if (reserved?.isNotEmpty ?? false) return 'AmneziaWG не поддерживает reserved.';
          final paddings = [amnezia.s1, amnezia.s2, amnezia.s3, amnezia.s4];
          if ((amnezia.headerProtectionKey?.isNotEmpty ?? false) && paddings.any((s) => (s ?? 0) < 12)) {
            return 'AmneziaWG: защита заголовков требует S1–S4 не меньше 12.';
          }
        }
    }
    if (_tcpHttpHeader(config)) return 'TCP с HTTP-обфускацией недоступен в ядре sing-box.';
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
