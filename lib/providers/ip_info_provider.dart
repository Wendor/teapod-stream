import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/interfaces/vpn_engine.dart';
import '../core/services/ip_lookup.dart';
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
  @override
  Future<IpInfo?> build() async {
    if (ref.watch(vpnConnectionStateProvider) != VpnState.connected) return null;
    // Only through the tunnel: the lookup is about the tunnel's exit IP.
    final socks = ref.read(vpnProvider).tunnelSocks;
    if (socks == null) return null;
    final configId = ref.read(effectiveConfigProvider)?.id ?? '';
    final r = await ref.read(ipLookupProvider).lookupThrough(configId, socks);
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
