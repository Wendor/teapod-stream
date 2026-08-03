import '../models/vpn_config.dart';
import '../models/vpn_log_entry.dart';
import '../models/dns_config.dart';
import '../models/heartbeat_settings.dart';
import '../models/routing_settings.dart';
import '../models/xray_tuning.dart';
import '../services/settings_service.dart';

/// blocked — kill switch удерживает TUN-sink после обрыва: трафик заблокирован.
enum VpnState { disconnected, connecting, connected, disconnecting, error, blocked }

abstract class VpnEngine {
  String get protocolName;

  /// [xrayConfigWifi] / [xrayConfigCellular] — конфиги сетевых правил,
  /// native выбирает их при реконнекте по текущему транспорту.
  /// [suspendNetworkRule] — сервер правила текущей сети не отвечает (failover):
  /// native не возвращается к нему, пока сеть не сменится.
  Future<void> connect(
    VpnConfig config,
    VpnEngineOptions options, {
    String? xrayConfigWifi,
    String? xrayConfigCellular,
    bool suspendNetworkRule,
  });
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
  final bool allowIcmp;
  final DnsMode dnsMode;
  final DnsServerConfig dnsServer;
  final VpnMode vpnMode;
  final bool proxyOnly;
  final bool showNotification;
  final bool killSwitch;
  final RoutingSettings routing;
  final bool sniffingEnabled;
  final int mtu;
  final DnsQueryStrategy dnsQueryStrategy;
  final bool blockQuic;
  final bool ipv6Enabled;
  final int obsProbeIntervalSec;
  final TlsFingerprint tlsFingerprint;
  final FragmentSettings fragment;
  final NoiseSettings noise;
  final MuxSettings mux;
  final HeartbeatSettings heartbeat;

  const VpnEngineOptions({
    required this.socksPort,
    required this.httpPort,
    required this.socksUser,
    required this.socksPassword,
    this.excludedPackages = const {},
    this.includedPackages = const {},
    this.logLevel = LogLevel.info,
    this.enableUdp = true,
    this.allowIcmp = false,
    this.dnsMode = DnsMode.proxy,
    this.dnsServer = const DnsServerConfig(type: DnsType.udp, address: '1.1.1.1'),
    this.vpnMode = VpnMode.allExcept,
    this.proxyOnly = false,
    this.showNotification = true,
    this.killSwitch = false,
    this.routing = const RoutingSettings(),
    this.sniffingEnabled = true,
    this.mtu = 1500,
    this.dnsQueryStrategy = DnsQueryStrategy.ipv4Only,
    this.blockQuic = false,
    this.ipv6Enabled = false,
    this.obsProbeIntervalSec = 600,
    this.tlsFingerprint = TlsFingerprint.defaultFp,
    this.fragment = const FragmentSettings(),
    this.noise = const NoiseSettings(),
    this.mux = const MuxSettings(),
    this.heartbeat = const HeartbeatSettings(),
  });
}
