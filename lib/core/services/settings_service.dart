import 'package:shared_preferences/shared_preferences.dart';
import '../models/vpn_log_entry.dart';
import '../models/dns_config.dart';
import '../models/routing_settings.dart';
import '../constants/app_constants.dart';
import 'storage_secure_service.dart';
import 'storage_migration_service.dart';
import 'update_service.dart' show UpdateChannel;

/// Режим работы VPN
enum VpnMode {
  allExcept,    // Все через VPN, кроме выбранных
  onlySelected, // Только выбранные через VPN, остальные мимо
}

enum FontScale { normal, large }

enum DnsQueryStrategy { ipv4Only, ipv6Only, auto }

/// uTLS fingerprint override for TLS/REALITY outbounds.
/// `defaultFp` — не переопределять (используется значение из конфига/URI).
enum TlsFingerprint {
  defaultFp, chrome, firefox, safari, ios, android, edge, random, randomized;

  /// Значение для поля `fingerprint` в xray streamSettings; null = не переопределять.
  String? get xrayValue => this == defaultFp ? null : name;
}

class GeoPresets {
  static const _lsGeoip    = 'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat';
  static const _lsGeosite  = 'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat';
  static const _rfGeoip    = 'https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat';
  static const _rfGeosite  = 'https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat';
  static const _v2Geoip    = 'https://github.com/v2fly/geoip/releases/latest/download/geoip.dat';
  static const _v2Geosite  = 'https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat';

  static const defaultGeoipUrl    = _lsGeoip;
  static const defaultGeositeUrl  = _lsGeosite;

  static const loyalsoldier = (name: 'Loyalsoldier', geoipUrl: _lsGeoip,  geositeUrl: _lsGeosite);
  static const runetfreedom = (name: 'runetfreedom', geoipUrl: _rfGeoip,  geositeUrl: _rfGeosite);
  static const v2fly         = (name: 'v2fly',        geoipUrl: _v2Geoip,  geositeUrl: _v2Geosite);
  static final all = [loyalsoldier, runetfreedom, v2fly];

  static String nameOf(String geoipUrl, String geositeUrl) {
    for (final p in all) {
      if (p.geoipUrl == geoipUrl && p.geositeUrl == geositeUrl) return p.name;
    }
    return 'custom';
  }
}

class AppSettings {
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
  final bool autoStartOnBoot;
  final TlsFingerprint tlsFingerprint;

  /// Ведение журнала (файл + UI). При выключении нативный слой
  /// пишет только warning/error.
  final bool logsEnabled;

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
    this.autoStartOnBoot = false,
    this.tlsFingerprint = TlsFingerprint.defaultFp,
    this.logsEnabled = true,
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
    bool? autoStartOnBoot,
    TlsFingerprint? tlsFingerprint,
    bool? logsEnabled,
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
      autoStartOnBoot: autoStartOnBoot ?? this.autoStartOnBoot,
      tlsFingerprint: tlsFingerprint ?? this.tlsFingerprint,
      logsEnabled: logsEnabled ?? this.logsEnabled,
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
    'autoStartOnBoot': autoStartOnBoot,
    'tlsFingerprint': tlsFingerprint.name,
    'logsEnabled': logsEnabled,
  };

  static AppSettings fromJson(Map<String, dynamic> json) {
    final routingJson = json['routing'] as Map<String, dynamic>?;
    return AppSettings(
      socksPort: json['socksPort'] as int? ?? AppConstants.defaultSocksPort,
      logLevel: LogLevel.values.firstWhere(
        (e) => e.name == json['logLevel'], orElse: () => LogLevel.info),
      excludedPackages: (json['excludedPackages'] as List<dynamic>?)?.cast<String>().toSet() ?? {},
      includedPackages: (json['includedPackages'] as List<dynamic>?)?.cast<String>().toSet() ?? {},
      vpnMode: VpnMode.values.firstWhere(
        (e) => e.name == json['vpnMode'], orElse: () => VpnMode.onlySelected),
      splitTunnelingEnabled: json['splitTunnelingEnabled'] as bool? ?? false,
      randomPort: json['randomPort'] as bool? ?? true,
      autoConnect: json['autoConnect'] as bool? ?? false,
      dnsMode: DnsMode.values.firstWhere(
        (e) => e.name == json['dnsMode'], orElse: () => DnsMode.proxy),
      dnsPreset: json['dnsPreset'] as String? ?? 'cf_udp',
      customDnsAddress: json['customDnsAddress'] as String? ?? '1.1.1.1',
      customDnsType: json['customDnsType'] as String? ?? 'udp',
      enableUdp: json['enableUdp'] as bool? ?? true,
      allowIcmp: json['allowIcmp'] as bool? ?? true,
      randomCredentials: json['randomCredentials'] as bool? ?? true,
      socksUser: json['socksUser'] as String? ?? '',
      socksPassword: json['socksPassword'] as String? ?? '',
      proxyOnly: json['proxyOnly'] as bool? ?? false,
      showNotification: json['showNotification'] as bool? ?? true,
      killSwitchEnabled: json['killSwitchEnabled'] as bool? ?? false,
      hwidEnabled: json['hwidEnabled'] as bool? ?? false,
      routing: routingJson != null ? RoutingSettings.fromJson(routingJson) : const RoutingSettings(),
      updateChannel: UpdateChannel.values.firstWhere(
        (e) => e.name == json['updateChannel'], orElse: () => UpdateChannel.stable),
      fontScale: FontScale.values.firstWhere(
        (e) => e.name == json['fontScale'], orElse: () => FontScale.normal),
      geoipUrl: json['geoipUrl'] as String? ?? GeoPresets.defaultGeoipUrl,
      geositeUrl: json['geositeUrl'] as String? ?? GeoPresets.defaultGeositeUrl,
      sniffingEnabled: json['sniffingEnabled'] as bool? ?? true,
      mtu: json['mtu'] as int? ?? 1500,
      subAutoRefresh: json['subAutoRefresh'] as bool? ?? false,
      subAutoRefreshHours: json['subAutoRefreshHours'] as int? ?? 6,
      subUserAgent: json['subUserAgent'] as String? ?? '',
      obsProbeIntervalSec: json['obsProbeIntervalSec'] as int? ?? 600,
      dnsQueryStrategy: DnsQueryStrategy.values.firstWhere(
        (e) => e.name == json['dnsQueryStrategy'], orElse: () => DnsQueryStrategy.ipv4Only),
      blockQuic: json['blockQuic'] as bool? ?? false,
      ipv6Enabled: json['ipv6Enabled'] as bool? ?? false,
      autoStartOnBoot: json['autoStartOnBoot'] as bool? ?? false,
      tlsFingerprint: TlsFingerprint.values.firstWhere(
        (e) => e.name == json['tlsFingerprint'], orElse: () => TlsFingerprint.defaultFp),
      logsEnabled: json['logsEnabled'] as bool? ?? true,
    );
  }

  DnsServerConfig get dnsServer => DnsServerConfig.fromPreset(
    dnsPreset,
    customAddress: customDnsAddress,
    customType: customDnsType == 'doh' ? DnsType.doh : customDnsType == 'dot' ? DnsType.dot : DnsType.udp,
  );
}

class SettingsService {
  static const _socksPortKey = 'socks_port';
  static const _logLevelKey = 'log_level';
  static const _excludedPackagesKey = 'excluded_packages';
  static const _splitTunnelingKey = 'split_tunneling_enabled';
  static const _randomPortKey = 'random_port';
  static const _autoConnectKey = 'auto_connect';
  static const _dnsModeKey = 'dns_mode';
  static const _dnsPresetKey = 'dns_preset';
  static const _customDnsAddressKey = 'custom_dns_address';
  static const _customDnsTypeKey = 'custom_dns_type';
  static const _enableUdpKey = 'enable_udp';
  static const _allowIcmpKey = 'allow_icmp';
  static const _randomCredentialsKey = 'random_credentials';
  static const _proxyOnlyKey = 'proxy_only';
  static const _showNotificationKey = 'show_notification';
  static const _vpnModeKey = 'vpn_mode';
  static const _includedPackagesKey = 'included_packages';
  static const _killSwitchKey = 'kill_switch';
  static const _hwidEnabledKey = 'hwid_enabled';
  static const _routingDirectionKey = 'routing_direction';
  static const _routingBypassLocalKey = 'routing_bypass_local';
  static const _routingGeoEnabledKey = 'routing_geo_enabled';
  static const _routingGeoCodesKey = 'routing_geo_codes';
  static const _routingDomainEnabledKey = 'routing_domain_enabled';
  static const _routingDomainZonesKey = 'routing_domain_zones';
  static const _routingGeositeEnabledKey = 'routing_geosite_enabled';
  static const _routingGeositeCodesKey = 'routing_geosite_codes';
  static const _routingAdBlockEnabledKey = 'routing_adblock_enabled';
  static const _routingSitesEnabledKey = 'routing_sites_enabled';
  static const _routingSitesKey = 'routing_sites';
  static const _routingRuServicesKey = 'routing_ru_services_enabled';
  static const _updateChannelKey = 'update_channel';
  static const _fontScaleKey = 'font_scale';
  static const _sniffingEnabledKey = 'sniffing_enabled';
  static const _mtuKey = 'mtu';
  static const _subAutoRefreshKey = 'sub_auto_refresh';
  static const _subAutoRefreshHoursKey = 'sub_auto_refresh_hours';
  static const _subUserAgentKey = 'sub_user_agent';
  static const _obsProbeIntervalKey = 'obs_probe_interval_sec';
  static const _dnsQueryStrategyKey = 'dns_query_strategy';
  static const _blockQuicKey = 'block_quic';
  static const _ipv6EnabledKey = 'ipv6_enabled';
  static const _autoStartOnBootKey = 'auto_start_on_boot';
  static const _tlsFingerprintKey = 'tls_fingerprint';
  static const _logsEnabledKey = 'logs_enabled';

  final _secure = StorageSecureService();

  Future<AppSettings> load() async {
    await StorageMigrationService.runIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    final creds = await _secure.readSocksCredentials();
    final excluded = (prefs.getStringList(_excludedPackagesKey) ?? []).toSet();
    final included = (prefs.getStringList(_includedPackagesKey) ?? []).toSet();
    return AppSettings(
      socksPort: prefs.getInt(_socksPortKey) ?? AppConstants.defaultSocksPort,
      logLevel: LogLevel.values.firstWhere(
        (e) => e.name == prefs.getString(_logLevelKey),
        orElse: () => LogLevel.info,
      ),
      excludedPackages: excluded,
      includedPackages: included,
      vpnMode: VpnMode.values.firstWhere(
        (e) => e.name == prefs.getString(_vpnModeKey),
        orElse: () => VpnMode.onlySelected,
      ),
      splitTunnelingEnabled: prefs.getBool(_splitTunnelingKey) ?? false,
      randomPort: prefs.getBool(_randomPortKey) ?? true,
      autoConnect: prefs.getBool(_autoConnectKey) ?? false,
      dnsMode: DnsMode.values.firstWhere(
        (e) => e.name == prefs.getString(_dnsModeKey),
        orElse: () => DnsMode.proxy,
      ),
      dnsPreset: prefs.getString(_dnsPresetKey) ?? 'cf_udp',
      customDnsAddress: prefs.getString(_customDnsAddressKey) ?? '1.1.1.1',
      customDnsType: prefs.getString(_customDnsTypeKey) ?? 'udp',
      enableUdp: prefs.getBool(_enableUdpKey) ?? true,
      allowIcmp: prefs.getBool(_allowIcmpKey) ?? true,
      randomCredentials: prefs.getBool(_randomCredentialsKey) ?? true,
      socksUser: creds.user,
      socksPassword: creds.password,
      proxyOnly: prefs.getBool(_proxyOnlyKey) ?? false,
      showNotification: prefs.getBool(_showNotificationKey) ?? true,
      killSwitchEnabled: prefs.getBool(_killSwitchKey) ?? false,
      hwidEnabled: prefs.getBool(_hwidEnabledKey) ?? false,
      routing: _loadRouting(prefs),
      updateChannel: UpdateChannel.values.firstWhere(
        (e) => e.name == prefs.getString(_updateChannelKey),
        orElse: () => UpdateChannel.stable,
      ),
      fontScale: FontScale.values.firstWhere(
        (e) => e.name == prefs.getString(_fontScaleKey),
        orElse: () => FontScale.normal,
      ),
      sniffingEnabled: prefs.getBool(_sniffingEnabledKey) ?? true,
      mtu: prefs.getInt(_mtuKey) ?? 1500,
      subAutoRefresh: prefs.getBool(_subAutoRefreshKey) ?? false,
      subAutoRefreshHours: prefs.getInt(_subAutoRefreshHoursKey) ?? 6,
      subUserAgent: prefs.getString(_subUserAgentKey) ?? '',
      obsProbeIntervalSec: prefs.getInt(_obsProbeIntervalKey) ?? 600,
      dnsQueryStrategy: DnsQueryStrategy.values.firstWhere(
        (e) => e.name == prefs.getString(_dnsQueryStrategyKey),
        orElse: () => DnsQueryStrategy.ipv4Only,
      ),
      blockQuic: prefs.getBool(_blockQuicKey) ?? false,
      ipv6Enabled: prefs.getBool(_ipv6EnabledKey) ?? false,
      autoStartOnBoot: prefs.getBool(_autoStartOnBootKey) ?? false,
      tlsFingerprint: TlsFingerprint.values.firstWhere(
        (e) => e.name == prefs.getString(_tlsFingerprintKey),
        orElse: () => TlsFingerprint.defaultFp,
      ),
      logsEnabled: prefs.getBool(_logsEnabledKey) ?? true,
    );
  }

  static RoutingSettings _loadRouting(SharedPreferences prefs) {
    return RoutingSettings(
      direction: RoutingDirection.values.firstWhere(
        (e) => e.name == prefs.getString(_routingDirectionKey),
        orElse: () => RoutingDirection.global,
      ),
      bypassLocal: prefs.getBool(_routingBypassLocalKey) ?? false,
      geoEnabled: prefs.getBool(_routingGeoEnabledKey) ?? false,
      geoCodes: prefs.getStringList(_routingGeoCodesKey) ?? [],
      domainEnabled: prefs.getBool(_routingDomainEnabledKey) ?? false,
      domainZones: prefs.getStringList(_routingDomainZonesKey) ?? [],
      geositeEnabled: prefs.getBool(_routingGeositeEnabledKey) ?? false,
      geositeCodes: prefs.getStringList(_routingGeositeCodesKey) ?? [],
      adBlockEnabled: prefs.getBool(_routingAdBlockEnabledKey) ?? false,
      sitesEnabled: prefs.getBool(_routingSitesEnabledKey) ?? false,
      sites: prefs.getStringList(_routingSitesKey) ?? [],
      ruServicesEnabled: prefs.getBool(_routingRuServicesKey) ?? false,
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_socksPortKey, settings.socksPort);
    await prefs.setString(_logLevelKey, settings.logLevel.name);
    await prefs.setStringList(
        _excludedPackagesKey, settings.excludedPackages.toList());
    await prefs.setStringList(
        _includedPackagesKey, settings.includedPackages.toList());
    await prefs.setString(_vpnModeKey, settings.vpnMode.name);
    await prefs.setBool(_splitTunnelingKey, settings.splitTunnelingEnabled);
    await prefs.setBool(_randomPortKey, settings.randomPort);
    await prefs.setBool(_autoConnectKey, settings.autoConnect);
    await prefs.setString(_dnsModeKey, settings.dnsMode.name);
    await prefs.setString(_dnsPresetKey, settings.dnsPreset);
    await prefs.setString(_customDnsAddressKey, settings.customDnsAddress);
    await prefs.setString(_customDnsTypeKey, settings.customDnsType);
    await prefs.setBool(_enableUdpKey, settings.enableUdp);
    await prefs.setBool(_allowIcmpKey, settings.allowIcmp);
    await prefs.setBool(_randomCredentialsKey, settings.randomCredentials);
    await prefs.setBool(_proxyOnlyKey, settings.proxyOnly);
    await prefs.setBool(_showNotificationKey, settings.showNotification);
    await prefs.setBool(_killSwitchKey, settings.killSwitchEnabled);
    await prefs.setBool(_hwidEnabledKey, settings.hwidEnabled);
    await prefs.setString(_routingDirectionKey, settings.routing.direction.name);
    await prefs.setBool(_routingBypassLocalKey, settings.routing.bypassLocal);
    await prefs.setBool(_routingGeoEnabledKey, settings.routing.geoEnabled);
    await prefs.setStringList(_routingGeoCodesKey, settings.routing.geoCodes);
    await prefs.setBool(_routingDomainEnabledKey, settings.routing.domainEnabled);
    await prefs.setStringList(_routingDomainZonesKey, settings.routing.domainZones);
    await prefs.setBool(_routingGeositeEnabledKey, settings.routing.geositeEnabled);
    await prefs.setStringList(_routingGeositeCodesKey, settings.routing.geositeCodes);
    await prefs.setBool(_routingAdBlockEnabledKey, settings.routing.adBlockEnabled);
    await prefs.setBool(_routingSitesEnabledKey, settings.routing.sitesEnabled);
    await prefs.setStringList(_routingSitesKey, settings.routing.sites);
    await prefs.setBool(_routingRuServicesKey, settings.routing.ruServicesEnabled);
    await prefs.setString(_updateChannelKey, settings.updateChannel.name);
    await prefs.setString(_fontScaleKey, settings.fontScale.name);
    await prefs.setBool(_sniffingEnabledKey, settings.sniffingEnabled);
    await prefs.setInt(_mtuKey, settings.mtu);
    await prefs.setBool(_subAutoRefreshKey, settings.subAutoRefresh);
    await prefs.setInt(_subAutoRefreshHoursKey, settings.subAutoRefreshHours);
    await prefs.setString(_subUserAgentKey, settings.subUserAgent);
    await prefs.setInt(_obsProbeIntervalKey, settings.obsProbeIntervalSec);
    await prefs.setString(_dnsQueryStrategyKey, settings.dnsQueryStrategy.name);
    await prefs.setBool(_blockQuicKey, settings.blockQuic);
    await prefs.setBool(_ipv6EnabledKey, settings.ipv6Enabled);
    await prefs.setBool(_autoStartOnBootKey, settings.autoStartOnBoot);
    await prefs.setString(_tlsFingerprintKey, settings.tlsFingerprint.name);
    await prefs.setBool(_logsEnabledKey, settings.logsEnabled);
    // SOCKS credentials go to encrypted storage
    await _secure.writeSocksCredentials(settings.socksUser, settings.socksPassword);
  }
}
