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
  final bool randomCredentials;
  final String socksUser;
  final String socksPassword;
  final bool proxyOnly;
  final bool showNotification;
  final bool killSwitchEnabled;
  final bool hwidEnabled;
  final RoutingSettings routing;
  final UpdateChannel updateChannel;

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
    this.randomCredentials = true,
    this.socksUser = '',
    this.socksPassword = '',
    this.proxyOnly = false,
    this.showNotification = true,
    this.killSwitchEnabled = false,
    this.hwidEnabled = false,
    this.routing = const RoutingSettings(),
    this.updateChannel = UpdateChannel.stable,
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
    bool? randomCredentials,
    String? socksUser,
    String? socksPassword,
    bool? proxyOnly,
    bool? showNotification,
    bool? killSwitchEnabled,
    bool? hwidEnabled,
    RoutingSettings? routing,
    UpdateChannel? updateChannel,
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
      randomCredentials: randomCredentials ?? this.randomCredentials,
      socksUser: socksUser ?? this.socksUser,
      socksPassword: socksPassword ?? this.socksPassword,
      proxyOnly: proxyOnly ?? this.proxyOnly,
      showNotification: showNotification ?? this.showNotification,
      killSwitchEnabled: killSwitchEnabled ?? this.killSwitchEnabled,
      hwidEnabled: hwidEnabled ?? this.hwidEnabled,
      routing: routing ?? this.routing,
      updateChannel: updateChannel ?? this.updateChannel,
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
  static const _updateChannelKey = 'update_channel';

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
    await prefs.setString(_updateChannelKey, settings.updateChannel.name);
    // SOCKS credentials go to encrypted storage
    await _secure.writeSocksCredentials(settings.socksUser, settings.socksPassword);
  }
}
