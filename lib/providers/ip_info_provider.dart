import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/interfaces/vpn_engine.dart';
import '../core/services/app_http.dart';
import '../core/services/ip_lookup.dart';
import '../core/services/tunnel_socks.dart';
import 'config_provider.dart';
import 'vpn_provider.dart';
import '../core/services/platform_service.dart';

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
  static const _maxBodyBytes = 64 * 1024;

  @override
  Future<IpInfo?> build() async {
    final connectionState = ref.watch(vpnConnectionStateProvider);
    if (connectionState == VpnState.connected) {
      final vpnState = ref.read(vpnProvider);
      if (vpnState.activeSocksPort > 0) {
        return _fetch(TunnelSocks(vpnState.activeSocksPort, vpnState.activeSocksUser, vpnState.activeSocksPassword));
      }
    }
    return null;
  }

  /// Only through the tunnel: the lookup is about the tunnel's exit IP.
  Future<IpInfo?> _fetch(TunnelSocks socks) async {
    final configId = ref.read(effectiveConfigProvider)?.id ?? '';
    // One client for the chain: closing it ends the requests the lookup stopped waiting for.
    final client = AppHttp.client(socks: socks);
    Future<String> fetch(Uri url) async {
      final resp = await AppHttp.get(
        url,
        client: client,
        headers: const {HttpHeaders.userAgentHeader: 'TeapodStream'},
        maxBytes: _maxBodyBytes,
      );
      if (resp.statusCode != HttpStatus.ok) throw HttpException('HTTP ${resp.statusCode}', uri: url);
      return resp.body;
    }

    final IpLookupResult? r;
    try {
      r = await ref.read(ipLookupProvider).lookup(configId, fetch);
    } finally {
      client.close(force: true);
    }
    if (r == null) return null;
    // The service gave no country: take it from the geoip.dat the cores route with.
    final code = r.countryCode ?? await _countryFromGeoip(r.ip);
    return IpInfo(ip: r.ip, country: r.country, countryCode: code);
  }

  Future<String?> _countryFromGeoip(String ip) async {
    try {
      return await ref.read(platformServiceProvider).countryForIp(ip);
    } catch (_) {
      return null;
    }
  }
}

final ipInfoProvider = AsyncNotifierProvider<IpInfoNotifier, IpInfo?>(IpInfoNotifier.new);
