import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socks5_proxy/socks.dart';
import '../core/interfaces/vpn_engine.dart';
import 'vpn_provider.dart';

class IpInfo {
  final String ip;
  final String country;
  final String countryCode;

  const IpInfo({
    required this.ip,
    required this.country,
    required this.countryCode,
  });
}

class IpInfoNotifier extends AsyncNotifier<IpInfo?> {
  @override
  Future<IpInfo?> build() async {
    // Watch only connection state — stats ticks must not retrigger a fetch
    final connectionState = ref.watch(vpnConnectionStateProvider);
    if (connectionState != VpnState.connected) return null;
    final vpnState = ref.read(vpnProvider);
    return _fetch(
      socksPort: vpnState.activeSocksPort,
      socksUser: vpnState.activeSocksUser,
      socksPassword: vpnState.activeSocksPassword,
    );
  }

  Future<IpInfo?> _fetch({
    required int socksPort,
    required String socksUser,
    required String socksPassword,
  }) async {
    if (socksPort <= 0) return null;
    final client = HttpClient();
    if (socksPort > 0) {
      SocksTCPClient.assignToHttpClient(client, [
        ProxySettings(
          InternetAddress.loopbackIPv4,
          socksPort,
          username: socksUser.isNotEmpty ? socksUser : null,
          password: socksUser.isNotEmpty ? socksPassword : null,
        ),
      ]);
    }
    try {
      final req = await client
          .getUrl(Uri.parse('http://ip-api.com/json?fields=query,country,countryCode,status'))
          .timeout(const Duration(seconds: 10));
      req.headers.set(HttpHeaders.userAgentHeader, 'TeapodStream');
      final resp = await req.close().timeout(const Duration(seconds: 10));
      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['status'] != 'success') return null;
      return IpInfo(
        ip: json['query'] as String,
        country: json['country'] as String,
        countryCode: json['countryCode'] as String,
      );
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}

final ipInfoProvider = AsyncNotifierProvider<IpInfoNotifier, IpInfo?>(IpInfoNotifier.new);
