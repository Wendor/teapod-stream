import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socks5_proxy/socks.dart';
import '../core/interfaces/vpn_engine.dart';
import '../core/services/ip_lookup.dart';
import '../protocols/xray/xray_engine.dart';
import 'config_provider.dart';
import 'vpn_provider.dart';

class IpInfo {
  final String ip;

  /// Null when the service that answered doesn't report the country.
  final String? country;
  final String? countryCode;

  const IpInfo({required this.ip, this.country, this.countryCode});
}

/// The lookup chain with its per-config order; lives as long as the app (the order is memory only).
final ipLookupProvider = Provider<IpLookup>((ref) => IpLookup());

class IpInfoNotifier extends AsyncNotifier<IpInfo?> {
  @override
  Future<IpInfo?> build() async {
    final connectionState = ref.watch(vpnConnectionStateProvider);
    if (connectionState == VpnState.connected) {
      final vpnState = ref.read(vpnProvider);
      if (vpnState.activeSocksPort > 0) {
        return _fetch(
          socksPort: vpnState.activeSocksPort,
          socksUser: vpnState.activeSocksUser,
          socksPassword: vpnState.activeSocksPassword,
        );
      }
    }
    // Fallback: Quick Tile started VPN — native state may be ahead of Flutter state
    final engine = ref.read(xrayEngineProvider);
    final nativeState = await engine.getVpnState();
    if (nativeState.state == VpnState.connected && nativeState.socksPort > 0) {
      return _fetch(
        socksPort: nativeState.socksPort,
        socksUser: nativeState.socksUser,
        socksPassword: nativeState.socksPassword,
      );
    }
    return null;
  }

  Future<IpInfo?> _fetch({required int socksPort, required String socksUser, required String socksPassword}) async {
    if (socksPort <= 0) return null;
    final configId = ref.read(effectiveConfigProvider)?.id ?? '';
    final client = HttpClient();
    SocksTCPClient.assignToHttpClient(client, [
      ProxySettings(
        InternetAddress.loopbackIPv4,
        socksPort,
        username: socksUser.isNotEmpty ? socksUser : null,
        password: socksUser.isNotEmpty ? socksPassword : null,
      ),
    ]);
    Future<String> fetch(Uri url) async {
      final req = await client.getUrl(url);
      req.headers.set(HttpHeaders.userAgentHeader, 'TeapodStream');
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != HttpStatus.ok) throw HttpException('HTTP ${resp.statusCode}', uri: url);
      return body;
    }

    try {
      final r = await ref.read(ipLookupProvider).lookup(configId, fetch);
      return r == null ? null : IpInfo(ip: r.ip, country: r.country, countryCode: r.countryCode);
    } finally {
      client.close(force: true);
    }
  }
}

final ipInfoProvider = AsyncNotifierProvider<IpInfoNotifier, IpInfo?>(IpInfoNotifier.new);
