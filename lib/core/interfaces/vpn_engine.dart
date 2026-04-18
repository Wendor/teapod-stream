import '../models/vpn_config.dart';
import '../models/vpn_log_entry.dart';
import '../models/dns_config.dart';
import '../models/routing_settings.dart';
import '../services/settings_service.dart';

enum VpnState { disconnected, connecting, connected, disconnecting, error }

abstract class VpnEngine {
  String get protocolName;

  Future<void> connect(VpnConfig config, VpnEngineOptions options);
  Future<void> disconnect();

  Future<int?> pingConfig(VpnConfig config);
  bool supportsConfig(VpnConfig config);
}

class VpnEngineOptions {
  final int socksPort;
  final int httpPort;
  final String socksUser;
  final String socksPassword;
  final Set<String> excludedPackages;
  final Set<String> includedPackages;
  final LogLevel logLevel;
  final bool enableUdp;
  final DnsMode dnsMode;
  final DnsServerConfig dnsServer;
  final VpnMode vpnMode;
  final bool proxyOnly;
  final bool showNotification;
  final bool killSwitch;
  final RoutingSettings routing;

  const VpnEngineOptions({
    required this.socksPort,
    required this.httpPort,
    required this.socksUser,
    required this.socksPassword,
    this.excludedPackages = const {},
    this.includedPackages = const {},
    this.logLevel = LogLevel.info,
    this.enableUdp = true,
    this.dnsMode = DnsMode.proxy,
    this.dnsServer = const DnsServerConfig(type: DnsType.udp, address: '1.1.1.1'),
    this.vpnMode = VpnMode.allExcept,
    this.proxyOnly = false,
    this.showNotification = true,
    this.killSwitch = false,
    this.routing = const RoutingSettings(),
  });
}
