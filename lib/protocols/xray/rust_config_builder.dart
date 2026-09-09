import '../../core/constants/core_features.dart';
import 'dart:convert';

import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/dns_config.dart';
import '../../core/models/routing_settings.dart';
import '../../core/models/vpn_config.dart';
import 'xray_config_builder.dart';

/// Supported VLESS carrier/security combinations integrated with Android TUN.
class RustConfigBuilder {
  static const visionFlows = {'xtls-rprx-vision', 'xtls-rprx-vision-udp443'};
  static const _transports = {
    VpnTransport.tcp,
    VpnTransport.ws,
    VpnTransport.httpupgrade,
    VpnTransport.grpc,
    VpnTransport.xhttp,
    VpnTransport.splithttp,
  };
  static const _urlTransports = {
    'tcp',
    'raw',
    'ws',
    'websocket',
    'httpupgrade',
    'grpc',
    'xhttp',
    'splithttp',
  };

  static bool supports(VpnConfig config) => unsupportedReason(config) == null;

  static String? unsupportedReason(VpnConfig config) {
    if (config.rawXrayConfig != null) {
      return 'Импорт полного JSON в Rust-сборке пока недоступен.';
    }
    if (config.protocol != VpnProtocol.vless) {
      return 'Rust-сборка поддерживает протокол VLESS.';
    }
    if (config.encryption != null && config.encryption != 'none') {
      return 'Rust-сборка пока принимает VLESS с encryption=none.';
    }
    final declaredTransport = Uri.tryParse(
      config.rawUri ?? '',
    )?.queryParameters['type'];
    if (!_transports.contains(config.transport) ||
        (declaredTransport != null &&
            !_urlTransports.contains(declaredTransport.toLowerCase()))) {
      return 'Транспорт не поддерживается. Доступны TCP/RAW, WebSocket, HTTPUpgrade, gRPC и xHTTP.';
    }
    if (config.security != VpnSecurity.tls &&
        config.security != VpnSecurity.reality) {
      return 'Для VLESS в Rust-сборке выбери TLS или Reality.';
    }
    if (config.security == VpnSecurity.reality &&
        (config.transport == VpnTransport.ws ||
            config.transport == VpnTransport.httpupgrade)) {
      return 'Reality поддерживается с TCP/RAW, gRPC и xHTTP. Для WebSocket/HTTPUpgrade нужен TLS.';
    }
    final flow = config.flow ?? '';
    if (flow.isNotEmpty && !visionFlows.contains(flow)) {
      return 'Неизвестный VLESS flow.';
    }
    if (flow.isNotEmpty && config.transport != VpnTransport.tcp) {
      return 'Vision с encryption=none поддерживается только поверх TCP/RAW с TLS или Reality.';
    }
    if (flow.isNotEmpty &&
        config.security == VpnSecurity.tls &&
        !CoreFeatures.rust.supports(CoreFeature.visionWithTls)) {
      return CoreFeatures.rust.unavailableReason(CoreFeature.visionWithTls);
    }
    if (config.security == VpnSecurity.tls && config.allowInsecure) {
      return 'Rust не поддерживает allowInsecure. Используй действительный TLS-сертификат или pinSHA256.';
    }
    if (config.ech?.isNotEmpty ?? false) {
      return 'ECH пока недоступен в Rust-сборке.';
    }
    return null;
  }

  static Map<String, dynamic> build(
    VpnConfig config,
    VpnEngineOptions options,
  ) {
    final reason = unsupportedReason(config);
    if (reason != null) throw FormatException(reason);
    if ((!CoreFeatures.rust.supports(CoreFeature.proxyOnly) &&
            options.proxyOnly) ||
        options.httpPort != 0) {
      throw const FormatException(
        'В Rust-пробнике доступен только режим VPN (TUN).',
      );
    }
    if ((!CoreFeatures.rust.supports(CoreFeature.mux) && options.mux.enabled) ||
        (!CoreFeatures.rust.supports(CoreFeature.fragmentation) &&
            options.fragment.enabled) ||
        (!CoreFeatures.rust.supports(CoreFeature.noise) &&
            options.noise.enabled) ||
        config.finalmask != null) {
      throw const FormatException(
        'Отключи Mux, фрагментацию, noise и finalmask для Rust-пробника.',
      );
    }
    if (!CoreFeatures.rust.supports(CoreFeature.adBlocking) &&
        options.routing.adBlockEnabled) {
      throw const FormatException(
        'Блокировка рекламы пока недоступна в Rust-пробнике.',
      );
    }
    if (options.routing.isActive &&
        !options.sniffingEnabled &&
        (options.routing.geositeEnabled ||
            options.routing.domainEnabled ||
            options.routing.sitesEnabled ||
            options.routing.ruServicesEnabled)) {
      throw const FormatException(
        'Включи определение доменов для GeoSite и доменных правил.',
      );
    }
    if (!CoreFeatures.rust.supports(CoreFeature.directDns) &&
        options.dnsMode != DnsMode.proxy) {
      throw const FormatException('Для Rust-пробника выбери DNS «Через VPN».');
    }
    if ((!CoreFeatures.rust.supports(CoreFeature.quicBlocking) &&
            options.blockQuic) ||
        (!CoreFeatures.rust.supports(CoreFeature.udpToggle) &&
            !options.enableUdp) ||
        (!CoreFeatures.rust.supports(CoreFeature.customMtu) &&
            options.mtu != 1500)) {
      throw const FormatException(
        'Для Rust-пробника нужны UDP, MTU 1500 и выключенная блокировка QUIC.',
      );
    }

    // Reuse the existing profile and domain-routing translation, then replace
    // the Go-specific inbound and policy. Native TUN traffic never uses SOCKS.
    final result = XrayConfigBuilder.build(config, options);
    result.remove('policy');
    // Resolve for IP rules only. Domain-only routing can pass the name to
    // VLESS without an extra client-side DNS round trip for every new host.
    result['routing']['domainStrategy'] =
        options.routing.isActive &&
            (options.routing.geoEnabled || options.routing.bypassLocal)
        ? 'IPIfNonMatch'
        : 'AsIs';
    // Rust 0.6 restores domain identity from FakeDNS before TUN routing.
    // Its TUN TCP sniffer alone does not classify ordinary real-IP targets.
    if (options.routing.isActive &&
        (options.routing.geositeEnabled ||
            options.routing.domainEnabled ||
            options.routing.sitesEnabled ||
            options.routing.ruServicesEnabled)) {
      (result['dns'] as Map<String, dynamic>)['fakeIp'] = {
        'enabled': true,
        'ipv4Pool': '198.18.0.0/15',
        'poolSize': 4096,
        'ttl': 300,
      };
    }

    final inbounds = result['inbounds'] as List<dynamic>;
    final socks = inbounds.single as Map<String, dynamic>;
    socks['listen'] = '127.0.0.1';
    socks['settings'] = {'auth': 'noauth', 'udp': true};
    inbounds.insert(0, {
      'tag': 'tun-in',
      'protocol': 'tun',
      'sniffing': Map<String, dynamic>.from(socks['sniffing'] as Map),
    });
    // Loopback SOCKS is retained for the app's IP check and heartbeat only.
    final outbounds = result['outbounds'] as List<dynamic>;
    outbounds.removeWhere((dynamic out) => out['protocol'] == 'blackhole');
    final rules = (result['routing'] as Map)['rules'] as List<dynamic>;
    for (final dynamic rule in rules) {
      final tags = rule['inboundTag'];
      if (tags is List && tags.contains('socks-in')) {
        rule['inboundTag'] = ['tun-in', 'socks-in'];
      }
    }
    // A catch-all rule matches before IPIfNonMatch can resolve a restored
    // domain. Use the core's default outbound instead, leaving the second
    // routing pass available for GeoIP when GeoSite did not match.
    rules.removeLast();
    final stream = outbounds.first['streamSettings'] as Map<String, dynamic>;
    if (config.transport == VpnTransport.xhttp ||
        config.transport == VpnTransport.splithttp) {
      stream['network'] = 'xhttp';
      stream.remove('splithttpSettings');
      stream['xhttpSettings'] = {
        'host': config.wsHost ?? '',
        'path': config.wsPath ?? '/',
        'mode': config.xhttpMode ?? 'auto',
        if (config.xhttpExtra != null) 'extra': config.xhttpExtra,
      };
    }
    if (config.security == VpnSecurity.tls &&
        (config.pinSHA256?.isNotEmpty ?? false)) {
      (stream['tlsSettings'] as Map<String, dynamic>)['pinnedPeerCertSha256'] =
          _certificatePins(config.pinSHA256!);
    }
    if (options.routing.direction == RoutingDirection.onlySelected) {
      final direct = outbounds.singleWhere(
        (dynamic out) => out['tag'] == 'direct',
      );
      outbounds.remove(direct);
      outbounds.insert(0, direct);
    }
    return result;
  }

  /// Native Rust expects SHA-256 of the full DER certificate as hex.
  static String _certificatePins(String value) {
    final pins = <String>[];
    for (final entry in value.split(',')) {
      final raw = entry.trim();
      final hex = raw.replaceAll(':', '');
      if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hex)) {
        pins.add(hex.toLowerCase());
        continue;
      }
      try {
        final bytes = base64.decode(raw);
        if (bytes.length != 32) throw const FormatException();
        pins.add(bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join());
      } on FormatException {
        throw const FormatException(
          'pinSHA256 должен быть SHA-256 сертификата: 64 hex-символа или base64 от 32 байт.',
        );
      }
    }
    return pins.join(',');
  }

  static String buildJson(VpnConfig config, VpnEngineOptions options) =>
      jsonEncode(build(config, options));
}
