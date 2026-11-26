import '../constants/app_constants.dart';
import 'core_kind.dart';
import 'dns_config.dart';
import 'heartbeat_settings.dart';
import 'routing_settings.dart';
import 'setting_limits.dart';
import 'vpn_log_entry.dart';
import 'xray_tuning.dart';

enum UpdateChannel { stable, beta }

/// VPN operating mode
enum VpnMode {
  allExcept, // Everything through VPN except the selected ones
  onlySelected, // Only the selected through VPN, the rest bypass it
}

enum FontScale { normal, large }

enum DnsQueryStrategy { ipv4Only, ipv6Only, auto }

/// uTLS fingerprint override for TLS/REALITY outbounds.
/// `defaultFp` — don't override (the value from the config/URI is used).
enum TlsFingerprint {
  defaultFp,
  chrome,
  firefox,
  safari,
  ios,
  android,
  edge,
  random,
  randomized;

  /// Value for the `fingerprint` field in xray streamSettings; null = don't override.
  String? get xrayValue => this == defaultFp ? null : name;
}

class GeoPresets {
  static const _lsGeoip = 'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat';
  static const _lsGeosite = 'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat';
  static const _rfGeoip = 'https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat';
  static const _rfGeosite =
      'https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat';
  static const _v2Geoip = 'https://github.com/v2fly/geoip/releases/latest/download/geoip.dat';
  static const _v2Geosite = 'https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat';

  static const defaultGeoipUrl = _lsGeoip;
  static const defaultGeositeUrl = _lsGeosite;

  static const loyalsoldier = (name: 'Loyalsoldier', geoipUrl: _lsGeoip, geositeUrl: _lsGeosite);
  static const runetfreedom = (name: 'runetfreedom', geoipUrl: _rfGeoip, geositeUrl: _rfGeosite);
  static const v2fly = (name: 'v2fly', geoipUrl: _v2Geoip, geositeUrl: _v2Geosite);
  static final all = [loyalsoldier, runetfreedom, v2fly];

  /// [nameOf] for URLs that match no preset; the UI shows its own label for it.
  static const custom = 'custom';

  static String nameOf(String geoipUrl, String geositeUrl) {
    for (final p in all) {
      if (p.geoipUrl == geoipUrl && p.geositeUrl == geositeUrl) return p.name;
    }
    return custom;
  }
}

class AppSettings {
  static const SettingLimits socksPortLimits = (min: 1024, max: 65535);

  /// The same limits as native (`ConnectionParams.fromJson`).
  static const SettingLimits mtuLimits = (min: 576, max: 9000);
  static const SettingLimits obsProbeIntervalLimits = (min: 0, max: 86400);

  final int socksPort;
  final LogLevel logLevel;
  final Set<String> excludedPackages;
  final Set<String> includedPackages;
  final VpnMode vpnMode;
  final bool splitTunnelingEnabled;
  final bool randomPort;
  final bool autoConnect;
  final DnsMode dnsMode;
  final String dnsPreset;
  final String customDnsAddress;
  final String customDnsType;
  final bool enableUdp;
  final bool allowIcmp;
  final bool randomCredentials;
  final String socksUser;
  final String socksPassword;
  final bool proxyOnly;
  final bool showNotification;
  final bool killSwitchEnabled;
  final bool hwidEnabled;
  final RoutingSettings routing;
  final UpdateChannel updateChannel;
  final FontScale fontScale;
  final String geoipUrl;
  final String geositeUrl;
  final bool sniffingEnabled;
  final int mtu;
  final bool subAutoRefresh;
  final int subAutoRefreshHours;
  final String subUserAgent;
  final int obsProbeIntervalSec;
  final DnsQueryStrategy dnsQueryStrategy;
  final bool blockQuic;
  final bool ipv6Enabled;

  /// allExcept: let ownerless flows into the tunnel (hotspot tethering).
  /// Weakens protection: excluded apps can go out through tun0.
  final bool allowTethering;
  final bool autoStartOnBoot;

  /// Tasker/Anubis: CONNECT/DISCONNECT broadcast commands and STATE_CHANGED.
  /// Visible to any app, so off by default. Read by native
  /// (`flutter.automation_enabled`).
  final bool automationEnabled;
  final TlsFingerprint tlsFingerprint;
  final FragmentSettings fragment;
  final NoiseSettings noise;
  final MuxSettings mux;
  final HeartbeatSettings heartbeat;

  /// Logging (file + UI). When off, the native layer
  /// writes only warning/error.
  final bool logsEnabled;

  /// Cores in priority order: a profile runs on the first one that can run it.
  final List<CoreKind> coreOrder;

  /// Cores excluded from selection.
  final Set<CoreKind> disabledCores;

  const AppSettings({
    this.socksPort = AppConstants.defaultSocksPort,
    this.logLevel = LogLevel.info,
    this.excludedPackages = const {},
    this.includedPackages = const {},
    this.vpnMode = VpnMode.onlySelected,
    this.splitTunnelingEnabled = false,
    this.randomPort = true,
    this.autoConnect = false,
    this.dnsMode = DnsMode.proxy,
    this.dnsPreset = 'cf_udp',
    this.customDnsAddress = '1.1.1.1',
    this.customDnsType = 'udp',
    this.enableUdp = true,
    this.allowIcmp = false,
    this.randomCredentials = true,
    this.socksUser = '',
    this.socksPassword = '',
    this.proxyOnly = false,
    this.showNotification = true,
    this.killSwitchEnabled = false,
    this.hwidEnabled = false,
    this.routing = const RoutingSettings(),
    this.updateChannel = UpdateChannel.stable,
    this.fontScale = FontScale.normal,
    this.geoipUrl = GeoPresets.defaultGeoipUrl,
    this.geositeUrl = GeoPresets.defaultGeositeUrl,
    this.sniffingEnabled = true,
    this.mtu = 1500,
    this.subAutoRefresh = false,
    this.subAutoRefreshHours = 6,
    this.subUserAgent = '',
    this.obsProbeIntervalSec = 600,
    this.dnsQueryStrategy = DnsQueryStrategy.ipv4Only,
    this.blockQuic = false,
    this.ipv6Enabled = false,
    this.allowTethering = false,
    this.autoStartOnBoot = false,
    this.automationEnabled = false,
    this.tlsFingerprint = TlsFingerprint.defaultFp,
    this.fragment = const FragmentSettings(),
    this.noise = const NoiseSettings(),
    this.mux = const MuxSettings(),
    this.heartbeat = const HeartbeatSettings(),
    this.logsEnabled = true,
    this.coreOrder = CoreKind.defaultOrder,
    this.disabledCores = const {},
  });

  AppSettings copyWith({
    int? socksPort,
    LogLevel? logLevel,
    Set<String>? excludedPackages,
    Set<String>? includedPackages,
    VpnMode? vpnMode,
    bool? splitTunnelingEnabled,
    bool? randomPort,
    bool? autoConnect,
    DnsMode? dnsMode,
    String? dnsPreset,
    String? customDnsAddress,
    String? customDnsType,
    bool? enableUdp,
    bool? allowIcmp,
    bool? randomCredentials,
    String? socksUser,
    String? socksPassword,
    bool? proxyOnly,
    bool? showNotification,
    bool? killSwitchEnabled,
    bool? hwidEnabled,
    RoutingSettings? routing,
    UpdateChannel? updateChannel,
    FontScale? fontScale,
    String? geoipUrl,
    String? geositeUrl,
    bool? sniffingEnabled,
    int? mtu,
    bool? subAutoRefresh,
    int? subAutoRefreshHours,
    String? subUserAgent,
    int? obsProbeIntervalSec,
    DnsQueryStrategy? dnsQueryStrategy,
    bool? blockQuic,
    bool? ipv6Enabled,
    bool? allowTethering,
    bool? autoStartOnBoot,
    bool? automationEnabled,
    TlsFingerprint? tlsFingerprint,
    FragmentSettings? fragment,
    NoiseSettings? noise,
    MuxSettings? mux,
    HeartbeatSettings? heartbeat,
    bool? logsEnabled,
    List<CoreKind>? coreOrder,
    Set<CoreKind>? disabledCores,
  }) {
    return AppSettings(
      socksPort: socksPort ?? this.socksPort,
      logLevel: logLevel ?? this.logLevel,
      excludedPackages: excludedPackages ?? this.excludedPackages,
      includedPackages: includedPackages ?? this.includedPackages,
      vpnMode: vpnMode ?? this.vpnMode,
      splitTunnelingEnabled: splitTunnelingEnabled ?? this.splitTunnelingEnabled,
      randomPort: randomPort ?? this.randomPort,
      autoConnect: autoConnect ?? this.autoConnect,
      dnsMode: dnsMode ?? this.dnsMode,
      dnsPreset: dnsPreset ?? this.dnsPreset,
      customDnsAddress: customDnsAddress ?? this.customDnsAddress,
      customDnsType: customDnsType ?? this.customDnsType,
      enableUdp: enableUdp ?? this.enableUdp,
      allowIcmp: allowIcmp ?? this.allowIcmp,
      randomCredentials: randomCredentials ?? this.randomCredentials,
      socksUser: socksUser ?? this.socksUser,
      socksPassword: socksPassword ?? this.socksPassword,
      proxyOnly: proxyOnly ?? this.proxyOnly,
      showNotification: showNotification ?? this.showNotification,
      killSwitchEnabled: killSwitchEnabled ?? this.killSwitchEnabled,
      hwidEnabled: hwidEnabled ?? this.hwidEnabled,
      routing: routing ?? this.routing,
      updateChannel: updateChannel ?? this.updateChannel,
      fontScale: fontScale ?? this.fontScale,
      geoipUrl: geoipUrl ?? this.geoipUrl,
      geositeUrl: geositeUrl ?? this.geositeUrl,
      sniffingEnabled: sniffingEnabled ?? this.sniffingEnabled,
      mtu: mtu ?? this.mtu,
      subAutoRefresh: subAutoRefresh ?? this.subAutoRefresh,
      subAutoRefreshHours: subAutoRefreshHours ?? this.subAutoRefreshHours,
      subUserAgent: subUserAgent ?? this.subUserAgent,
      obsProbeIntervalSec: obsProbeIntervalSec ?? this.obsProbeIntervalSec,
      dnsQueryStrategy: dnsQueryStrategy ?? this.dnsQueryStrategy,
      blockQuic: blockQuic ?? this.blockQuic,
      ipv6Enabled: ipv6Enabled ?? this.ipv6Enabled,
      allowTethering: allowTethering ?? this.allowTethering,
      autoStartOnBoot: autoStartOnBoot ?? this.autoStartOnBoot,
      automationEnabled: automationEnabled ?? this.automationEnabled,
      tlsFingerprint: tlsFingerprint ?? this.tlsFingerprint,
      fragment: fragment ?? this.fragment,
      noise: noise ?? this.noise,
      mux: mux ?? this.mux,
      heartbeat: heartbeat ?? this.heartbeat,
      logsEnabled: logsEnabled ?? this.logsEnabled,
      coreOrder: coreOrder ?? this.coreOrder,
      disabledCores: disabledCores ?? this.disabledCores,
    );
  }

  Map<String, dynamic> toJson() => {
    'socksPort': socksPort,
    'logLevel': logLevel.name,
    'excludedPackages': excludedPackages.toList(),
    'includedPackages': includedPackages.toList(),
    'vpnMode': vpnMode.name,
    'splitTunnelingEnabled': splitTunnelingEnabled,
    'randomPort': randomPort,
    'autoConnect': autoConnect,
    'dnsMode': dnsMode.name,
    'dnsPreset': dnsPreset,
    'customDnsAddress': customDnsAddress,
    'customDnsType': customDnsType,
    'enableUdp': enableUdp,
    'allowIcmp': allowIcmp,
    'randomCredentials': randomCredentials,
    'socksUser': socksUser,
    'socksPassword': socksPassword,
    'proxyOnly': proxyOnly,
    'showNotification': showNotification,
    'killSwitchEnabled': killSwitchEnabled,
    'hwidEnabled': hwidEnabled,
    'routing': routing.toJson(),
    'updateChannel': updateChannel.name,
    'fontScale': fontScale.name,
    'geoipUrl': geoipUrl,
    'geositeUrl': geositeUrl,
    'sniffingEnabled': sniffingEnabled,
    'mtu': mtu,
    'subAutoRefresh': subAutoRefresh,
    'subAutoRefreshHours': subAutoRefreshHours,
    'subUserAgent': subUserAgent,
    'obsProbeIntervalSec': obsProbeIntervalSec,
    'dnsQueryStrategy': dnsQueryStrategy.name,
    'blockQuic': blockQuic,
    'ipv6Enabled': ipv6Enabled,
    'allowTethering': allowTethering,
    'autoStartOnBoot': autoStartOnBoot,
    'automationEnabled': automationEnabled,
    'tlsFingerprint': tlsFingerprint.name,
    'fragment': fragment.toJson(),
    'noise': noise.toJson(),
    'mux': mux.toJson(),
    'heartbeat': heartbeat.toJson(),
    'logsEnabled': logsEnabled,
    'coreOrder': [for (final k in coreOrder) k.name],
    'disabledCores': [for (final k in disabledCores) k.name],
  };

  static AppSettings fromJson(Map<String, dynamic> json) {
    final routingJson = json['routing'] as Map<String, dynamic>?;
    return AppSettings(
      socksPort: socksPortLimits.clamp(json['socksPort'] as int? ?? AppConstants.defaultSocksPort),
      logLevel: LogLevel.values.firstWhere((e) => e.name == json['logLevel'], orElse: () => LogLevel.info),
      excludedPackages: (json['excludedPackages'] as List<dynamic>?)?.cast<String>().toSet() ?? {},
      includedPackages: (json['includedPackages'] as List<dynamic>?)?.cast<String>().toSet() ?? {},
      vpnMode: VpnMode.values.firstWhere((e) => e.name == json['vpnMode'], orElse: () => VpnMode.onlySelected),
      splitTunnelingEnabled: json['splitTunnelingEnabled'] as bool? ?? false,
      randomPort: json['randomPort'] as bool? ?? true,
      autoConnect: json['autoConnect'] as bool? ?? false,
      dnsMode: DnsMode.values.firstWhere((e) => e.name == json['dnsMode'], orElse: () => DnsMode.proxy),
      dnsPreset: json['dnsPreset'] as String? ?? 'cf_udp',
      customDnsAddress: json['customDnsAddress'] as String? ?? '1.1.1.1',
      customDnsType: json['customDnsType'] as String? ?? 'udp',
      enableUdp: json['enableUdp'] as bool? ?? true,
      allowIcmp: json['allowIcmp'] as bool? ?? false,
      randomCredentials: json['randomCredentials'] as bool? ?? true,
      socksUser: json['socksUser'] as String? ?? '',
      socksPassword: json['socksPassword'] as String? ?? '',
      proxyOnly: json['proxyOnly'] as bool? ?? false,
      showNotification: json['showNotification'] as bool? ?? true,
      killSwitchEnabled: json['killSwitchEnabled'] as bool? ?? false,
      hwidEnabled: json['hwidEnabled'] as bool? ?? false,
      routing: routingJson != null ? RoutingSettings.fromJson(routingJson) : const RoutingSettings(),
      updateChannel: UpdateChannel.values.firstWhere(
        (e) => e.name == json['updateChannel'],
        orElse: () => UpdateChannel.stable,
      ),
      fontScale: FontScale.values.firstWhere((e) => e.name == json['fontScale'], orElse: () => FontScale.normal),
      geoipUrl: json['geoipUrl'] as String? ?? GeoPresets.defaultGeoipUrl,
      geositeUrl: json['geositeUrl'] as String? ?? GeoPresets.defaultGeositeUrl,
      sniffingEnabled: json['sniffingEnabled'] as bool? ?? true,
      mtu: mtuLimits.clamp(json['mtu'] as int? ?? 1500),
      subAutoRefresh: json['subAutoRefresh'] as bool? ?? false,
      subAutoRefreshHours: json['subAutoRefreshHours'] as int? ?? 6,
      subUserAgent: json['subUserAgent'] as String? ?? '',
      obsProbeIntervalSec: obsProbeIntervalLimits.clamp(json['obsProbeIntervalSec'] as int? ?? 600),
      dnsQueryStrategy: DnsQueryStrategy.values.firstWhere(
        (e) => e.name == json['dnsQueryStrategy'],
        orElse: () => DnsQueryStrategy.ipv4Only,
      ),
      blockQuic: json['blockQuic'] as bool? ?? false,
      ipv6Enabled: json['ipv6Enabled'] as bool? ?? false,
      allowTethering: json['allowTethering'] as bool? ?? false,
      autoStartOnBoot: json['autoStartOnBoot'] as bool? ?? false,
      automationEnabled: json['automationEnabled'] as bool? ?? false,
      tlsFingerprint: TlsFingerprint.values.firstWhere(
        (e) => e.name == json['tlsFingerprint'],
        orElse: () => TlsFingerprint.defaultFp,
      ),
      fragment: json['fragment'] is Map<String, dynamic>
          ? FragmentSettings.fromJson(json['fragment'] as Map<String, dynamic>)
          : const FragmentSettings(),
      noise: json['noise'] is Map<String, dynamic>
          ? NoiseSettings.fromJson(json['noise'] as Map<String, dynamic>)
          : const NoiseSettings(),
      mux: json['mux'] is Map<String, dynamic>
          ? MuxSettings.fromJson(json['mux'] as Map<String, dynamic>)
          : const MuxSettings(),
      heartbeat: json['heartbeat'] is Map<String, dynamic>
          ? HeartbeatSettings.fromJson(json['heartbeat'] as Map<String, dynamic>)
          : const HeartbeatSettings(),
      logsEnabled: json['logsEnabled'] as bool? ?? true,
      coreOrder: CoreKind.parseOrder((json['coreOrder'] as List?)?.cast<String>(), first: json['core'] as String?),
      disabledCores: CoreKind.setOf((json['disabledCores'] as List?)?.cast<String>()),
    );
  }

  DnsServerConfig get dnsServer => DnsServerConfig.fromPreset(
    dnsPreset,
    customAddress: customDnsAddress,
    customType: customDnsType == 'doh'
        ? DnsType.doh
        : customDnsType == 'dot'
        ? DnsType.dot
        : DnsType.udp,
  );
}
