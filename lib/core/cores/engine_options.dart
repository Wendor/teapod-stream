import 'dart:convert';

import '../constants/app_constants.dart';
import '../interfaces/vpn_engine.dart';
import '../models/vpn_config.dart';
import '../services/settings_service.dart';
import 'core_backend.dart';

/// Опции подключения [config] на ядре [backend] из настроек.
VpnEngineOptions buildEngineOptions(
  AppSettings settings,
  VpnConfig config,
  CoreBackend backend, {
  int socksPort = AppConstants.defaultSocksPort,
  ({String user, String password}) credentials = (user: '', password: ''),
}) =>
    VpnEngineOptions(
      socksPort: socksPort,
      httpPort: 0,
      socksUser: credentials.user,
      socksPassword: credentials.password,
      excludedPackages: settings.splitTunnelingEnabled
          ? (settings.vpnMode == VpnMode.allExcept ? settings.excludedPackages : <String>{})
          : {},
      includedPackages: settings.splitTunnelingEnabled
          ? (settings.vpnMode == VpnMode.onlySelected ? settings.includedPackages : <String>{})
          : {},
      logLevel: settings.logLevel,
      enableUdp: settings.enableUdp,
      allowIcmp: settings.allowIcmp,
      dnsMode: settings.dnsMode,
      dnsServer: settings.dnsServer,
      vpnMode: settings.splitTunnelingEnabled ? settings.vpnMode : VpnMode.allExcept,
      proxyOnly: settings.proxyOnly,
      showNotification: settings.showNotification,
      killSwitch: settings.killSwitchEnabled,
      routing: settings.routing,
      sniffingEnabled: settings.sniffingEnabled,
      mtu: settings.mtu,
      dnsQueryStrategy: settings.dnsQueryStrategy,
      // Vision отвергает UDP/443: браузеры ретраят QUIC ~30 с перед откатом на
      // TCP. Политика блокировки — у ядра.
      blockQuic: backend.effectiveQuicBlock(requested: settings.blockQuic, flow: _visionFlow(config)),
      ipv6Enabled: settings.ipv6Enabled,
      allowTethering: settings.allowTethering,
      obsProbeIntervalSec: settings.obsProbeIntervalSec,
      tlsFingerprint: settings.tlsFingerprint,
      fragment: settings.fragment,
      noise: settings.noise,
      mux: settings.mux,
      heartbeat: settings.heartbeat,
    );

/// Vision-flow конфига (в т.ч. из полного JSON) — такие outbound'ы отвергают
/// UDP/443, QUIC нужно отбивать на стороне TUN.
String? _visionFlow(VpnConfig config) {
  final flow = config.flow;
  if (flow != null && flow.contains('vision')) return flow;
  final raw = config.rawXrayConfig;
  if (raw == null) return null;
  try {
    final cfg = jsonDecode(raw) as Map<String, dynamic>;
    final outbounds = cfg['outbounds'] as List<dynamic>? ?? [];
    for (final o in outbounds.whereType<Map<String, dynamic>>()) {
      if (o['protocol'] != 'vless') continue;
      final vnext = (o['settings'] as Map<String, dynamic>?)?['vnext'] as List<dynamic>? ?? [];
      for (final v in vnext.whereType<Map<String, dynamic>>()) {
        final users = v['users'] as List<dynamic>? ?? [];
        for (final u in users.whereType<Map<String, dynamic>>()) {
          final userFlow = u['flow'] as String?;
          if (userFlow != null && userFlow.contains('vision')) return userFlow;
        }
      }
    }
  } catch (_) {}
  return null;
}
