import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';
import '../models/vpn_log_entry.dart';
import '../models/dns_config.dart';
import '../models/heartbeat_settings.dart';
import '../models/core_kind.dart';
import '../models/routing_settings.dart';
import '../models/xray_tuning.dart';
import '../constants/app_constants.dart';
import 'storage_secure_service.dart';
import 'storage_migration_service.dart';

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
  static const _geoipUrlKey = 'geoip_url';
  static const _geositeUrlKey = 'geosite_url';
  static const _sniffingEnabledKey = 'sniffing_enabled';
  static const _mtuKey = 'mtu';
  static const _subAutoRefreshKey = 'sub_auto_refresh';
  static const _subAutoRefreshHoursKey = 'sub_auto_refresh_hours';
  static const _subUserAgentKey = 'sub_user_agent';
  static const _obsProbeIntervalKey = 'obs_probe_interval_sec';
  static const _dnsQueryStrategyKey = 'dns_query_strategy';
  static const _blockQuicKey = 'block_quic';
  static const _ipv6EnabledKey = 'ipv6_enabled';
  static const _allowTetheringKey = 'allow_tethering';
  static const _autoStartOnBootKey = 'auto_start_on_boot';
  static const _automationEnabledKey = 'automation_enabled';
  static const _tlsFingerprintKey = 'tls_fingerprint';
  static const _fragmentKey = 'xray_fragment';
  static const _noiseKey = 'xray_noise';
  static const _muxKey = 'xray_mux';
  static const _heartbeatKey = 'heartbeat_settings';
  static const _logsEnabledKey = 'logs_enabled';

  /// Before priorities — a single selected core; read only for migration.
  static const _legacyCoreKey = 'core_kind';
  static const _coreOrderKey = 'core_order';
  static const _disabledCoresKey = 'cores_disabled';

  final _secure = StorageSecureService();

  Future<AppSettings> load() async {
    await StorageMigrationService.runIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    final creds = await _secure.readSocksCredentials();
    final excluded = (prefs.getStringList(_excludedPackagesKey) ?? []).toSet();
    final included = (prefs.getStringList(_includedPackagesKey) ?? []).toSet();
    return AppSettings(
      socksPort: prefs.getInt(_socksPortKey) ?? AppConstants.defaultSocksPort,
      logLevel: LogLevel.values.firstWhere((e) => e.name == prefs.getString(_logLevelKey), orElse: () => LogLevel.info),
      excludedPackages: excluded,
      includedPackages: included,
      vpnMode: VpnMode.values.firstWhere(
        (e) => e.name == prefs.getString(_vpnModeKey),
        orElse: () => VpnMode.onlySelected,
      ),
      splitTunnelingEnabled: prefs.getBool(_splitTunnelingKey) ?? false,
      randomPort: prefs.getBool(_randomPortKey) ?? true,
      autoConnect: prefs.getBool(_autoConnectKey) ?? false,
      dnsMode: DnsMode.values.firstWhere((e) => e.name == prefs.getString(_dnsModeKey), orElse: () => DnsMode.proxy),
      dnsPreset: prefs.getString(_dnsPresetKey) ?? 'cf_udp',
      customDnsAddress: prefs.getString(_customDnsAddressKey) ?? '1.1.1.1',
      customDnsType: prefs.getString(_customDnsTypeKey) ?? 'udp',
      enableUdp: prefs.getBool(_enableUdpKey) ?? true,
      allowIcmp: prefs.getBool(_allowIcmpKey) ?? false,
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
      geoipUrl: prefs.getString(_geoipUrlKey) ?? GeoPresets.defaultGeoipUrl,
      geositeUrl: prefs.getString(_geositeUrlKey) ?? GeoPresets.defaultGeositeUrl,
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
      allowTethering: prefs.getBool(_allowTetheringKey) ?? false,
      autoStartOnBoot: prefs.getBool(_autoStartOnBootKey) ?? false,
      automationEnabled: prefs.getBool(_automationEnabledKey) ?? false,
      tlsFingerprint: TlsFingerprint.values.firstWhere(
        (e) => e.name == prefs.getString(_tlsFingerprintKey),
        orElse: () => TlsFingerprint.defaultFp,
      ),
      fragment: _decodeOr(prefs.getString(_fragmentKey), FragmentSettings.fromJson, const FragmentSettings()),
      noise: _decodeOr(prefs.getString(_noiseKey), NoiseSettings.fromJson, const NoiseSettings()),
      mux: _decodeOr(prefs.getString(_muxKey), MuxSettings.fromJson, const MuxSettings()),
      heartbeat: _decodeOr(prefs.getString(_heartbeatKey), HeartbeatSettings.fromJson, const HeartbeatSettings()),
      logsEnabled: prefs.getBool(_logsEnabledKey) ?? true,
      coreOrder: CoreKind.parseOrder(prefs.getStringList(_coreOrderKey), first: prefs.getString(_legacyCoreKey)),
      disabledCores: CoreKind.setOf(prefs.getStringList(_disabledCoresKey)),
    );
  }

  /// Parses a nested setting from a JSON string in prefs; on any error — the default.
  static T _decodeOr<T>(String? raw, T Function(Map<String, dynamic>) parse, T fallback) {
    if (raw == null || raw.isEmpty) return fallback;
    try {
      return parse(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return fallback;
    }
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
    await prefs.setStringList(_excludedPackagesKey, settings.excludedPackages.toList());
    await prefs.setStringList(_includedPackagesKey, settings.includedPackages.toList());
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
    await prefs.setString(_geoipUrlKey, settings.geoipUrl);
    await prefs.setString(_geositeUrlKey, settings.geositeUrl);
    await prefs.setBool(_sniffingEnabledKey, settings.sniffingEnabled);
    await prefs.setInt(_mtuKey, settings.mtu);
    await prefs.setBool(_subAutoRefreshKey, settings.subAutoRefresh);
    await prefs.setInt(_subAutoRefreshHoursKey, settings.subAutoRefreshHours);
    await prefs.setString(_subUserAgentKey, settings.subUserAgent);
    await prefs.setInt(_obsProbeIntervalKey, settings.obsProbeIntervalSec);
    await prefs.setString(_dnsQueryStrategyKey, settings.dnsQueryStrategy.name);
    await prefs.setBool(_blockQuicKey, settings.blockQuic);
    await prefs.setBool(_ipv6EnabledKey, settings.ipv6Enabled);
    await prefs.setBool(_allowTetheringKey, settings.allowTethering);
    await prefs.setBool(_autoStartOnBootKey, settings.autoStartOnBoot);
    await prefs.setBool(_automationEnabledKey, settings.automationEnabled);
    await prefs.setString(_tlsFingerprintKey, settings.tlsFingerprint.name);
    await prefs.setString(_fragmentKey, jsonEncode(settings.fragment.toJson()));
    await prefs.setString(_noiseKey, jsonEncode(settings.noise.toJson()));
    await prefs.setString(_muxKey, jsonEncode(settings.mux.toJson()));
    await prefs.setString(_heartbeatKey, jsonEncode(settings.heartbeat.toJson()));
    await prefs.setBool(_logsEnabledKey, settings.logsEnabled);
    await prefs.setStringList(_coreOrderKey, [for (final k in settings.coreOrder) k.name]);
    await prefs.setStringList(_disabledCoresKey, [for (final k in settings.disabledCores) k.name]);
    // SOCKS credentials go to encrypted storage
    await _secure.writeSocksCredentials(settings.socksUser, settings.socksPassword);
  }
}
