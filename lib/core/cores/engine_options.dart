import 'dart:convert';

import '../constants/app_constants.dart';
import '../interfaces/vpn_engine.dart';
import '../models/vpn_config.dart';
import '../models/app_settings.dart';
import 'core_backend.dart';

/// Connection options for [config] on core [backend] from settings.
VpnEngineOptions buildEngineOptions(
  AppSettings settings,
  VpnConfig config,
  CoreBackend backend, {
  int socksPort = AppConstants.defaultSocksPort,
  ({String user, String password}) credentials = (user: '', password: ''),
}) => VpnEngineOptions(
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
  // Vision rejects UDP/443: browsers retry QUIC for ~30 s before falling back to
  // TCP. The blocking policy belongs to the core.
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

/// The config's Vision flow (including from a full JSON) — such outbounds reject
/// UDP/443, QUIC must be refused on the TUN side.
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
