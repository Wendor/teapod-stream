import 'dart:convert';

import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/dns_config.dart';
import '../../core/models/routing_settings.dart';
import '../../core/models/vpn_config.dart';
import 'xray_config_builder.dart';

/// The deliberately small, validated surface of the first Rust build.
class RustConfigBuilder {
  static bool supports(VpnConfig config) =>
      config.rawXrayConfig == null &&
      config.protocol == VpnProtocol.vless &&
      (config.transport == VpnTransport.xhttp ||
          config.transport == VpnTransport.splithttp) &&
      config.security == VpnSecurity.reality &&
      (config.encryption == null || config.encryption == 'none') &&
      (config.flow == null || config.flow!.isEmpty);

  static Map<String, dynamic> build(
    VpnConfig config,
    VpnEngineOptions options,
  ) {
    if (!supports(config)) {
      throw const FormatException(
        'Пробная Rust-сборка поддерживает VLESS + xHTTP + Reality '
        'с encryption=none и без Vision. Импорт полного JSON пока недоступен.',
      );
    }
    if (options.proxyOnly || options.httpPort != 0) {
      throw const FormatException(
        'В Rust-пробнике доступен только режим VPN (TUN).',
      );
    }
    if (options.mux.enabled ||
        options.fragment.enabled ||
        options.noise.enabled ||
        config.finalmask != null) {
      throw const FormatException(
        'Отключи Mux, фрагментацию, noise и finalmask для Rust-пробника.',
      );
    }
    if (options.routing.adBlockEnabled) {
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
    if (options.dnsMode != DnsMode.proxy) {
      throw const FormatException('Для Rust-пробника выбери DNS «Через VPN».');
    }
    if (options.blockQuic || !options.enableUdp || options.mtu != 1500) {
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
    // Both share-link spellings select the same transport in Rust.
    final stream = outbounds.first['streamSettings'] as Map<String, dynamic>;
    stream['network'] = 'xhttp';
    stream.remove('splithttpSettings');
    stream['xhttpSettings'] = {
      'host': config.wsHost ?? '',
      'path': config.wsPath ?? '/',
      'mode': config.xhttpMode ?? 'auto',
      if (config.xhttpExtra != null) 'extra': config.xhttpExtra,
    };
    if (options.routing.direction == RoutingDirection.onlySelected) {
      final direct = outbounds.singleWhere(
        (dynamic out) => out['tag'] == 'direct',
      );
      outbounds.remove(direct);
      outbounds.insert(0, direct);
    }
    return result;
  }

  static String buildJson(VpnConfig config, VpnEngineOptions options) =>
      jsonEncode(build(config, options));
}
