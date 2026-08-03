import 'dart:convert';
import '../services/settings_service.dart';

/// Детерминированный отпечаток настроек, влияющих на активное соединение.
/// Изменился после подключения — нужен reconnect. Косметика (тема, шрифт,
/// autoConnect, параметры подписок, geo-URL) не входит.
String connectionFingerprint(AppSettings s) {
  final map = <String, Object?>{
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
    // switchSource не влияет на активную сессию — он читается уже после срыва.
    'heartbeatProbe': s.heartbeat.probe.name,
    'heartbeatAction': s.heartbeat.failAction.name,
    'heartbeatThreshold': s.heartbeat.failureThreshold,
    'heartbeatUrl': s.heartbeat.url,
  };
  return jsonEncode(map);
}
