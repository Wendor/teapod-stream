import 'dart:convert';
import '../models/app_settings.dart';
import 'core_kind.dart';

/// Deterministic fingerprint of the settings that affect the active connection.
/// Changed after connecting — a reconnect is needed. Cosmetics (theme, font,
/// autoConnect, subscription parameters, geo URLs) are not included.
/// [core] — the core the active profile runs (will run) on.
String connectionFingerprint(AppSettings s, {CoreKind? core}) {
  final map = <String, Object?>{
    'core': core?.name,
    'socksPort': s.socksPort,
    'randomPort': s.randomPort,
    'randomCredentials': s.randomCredentials,
    'socksUser': s.socksUser,
    'socksPassword': s.socksPassword,
    'proxyOnly': s.proxyOnly,
    'enableUdp': s.enableUdp,
    'allowIcmp': s.allowIcmp,
    'blockQuic': s.blockQuic,
    'mtu': s.mtu,
    'ipv6Enabled': s.ipv6Enabled,
    'allowTethering': s.allowTethering,
    'tlsFingerprint': s.tlsFingerprint.name,
    'obsProbeIntervalSec': s.obsProbeIntervalSec,
    'logLevel': s.logLevel.name,
    'sniffingEnabled': s.sniffingEnabled,
    'dnsMode': s.dnsMode.name,
    'dnsPreset': s.dnsPreset,
    'customDnsAddress': s.customDnsAddress,
    'customDnsType': s.customDnsType,
    'dnsQueryStrategy': s.dnsQueryStrategy.name,
    'routing': s.routing.toJson(),
    'splitTunnelingEnabled': s.splitTunnelingEnabled,
    'vpnMode': s.vpnMode.name,
    'includedPackages': s.includedPackages.toList()..sort(),
    'excludedPackages': s.excludedPackages.toList()..sort(),
    'killSwitchEnabled': s.killSwitchEnabled,
    'showNotification': s.showNotification,
    'fragment': s.fragment.toJson(),
    'noise': s.noise.toJson(),
    'mux': s.mux.toJson(),
    // switchSource doesn't affect the active session — it is read only after a failure.
    'heartbeatProbe': s.heartbeat.probe.name,
    'heartbeatAction': s.heartbeat.failAction.name,
    'heartbeatThreshold': s.heartbeat.failureThreshold,
    'heartbeatUrl': s.heartbeat.url,
  };
  return jsonEncode(map);
}
