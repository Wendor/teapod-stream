import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teapodstream/core/constants/app_constants.dart';
import 'package:teapodstream/core/models/core_kind.dart';
import 'package:teapodstream/core/models/dns_config.dart';
import 'package:teapodstream/core/models/heartbeat_settings.dart';
import 'package:teapodstream/core/models/routing_settings.dart';
import 'package:teapodstream/core/models/vpn_log_entry.dart';
import 'package:teapodstream/core/models/xray_tuning.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/core/services/update_service.dart';

/// Every field differs from its default, so a field lost in (de)serialization shows up.
const _custom = AppSettings(
  socksPort: 2000,
  logLevel: LogLevel.debug,
  excludedPackages: {'a.ex'},
  includedPackages: {'a.in', 'b.in'},
  vpnMode: VpnMode.allExcept,
  splitTunnelingEnabled: true,
  randomPort: false,
  autoConnect: true,
  dnsMode: DnsMode.direct,
  dnsPreset: 'custom',
  customDnsAddress: 'dns.example',
  customDnsType: 'dot',
  enableUdp: false,
  allowIcmp: true,
  randomCredentials: false,
  socksUser: 'user',
  socksPassword: 's3cr3t-pw',
  proxyOnly: true,
  showNotification: false,
  killSwitchEnabled: true,
  hwidEnabled: true,
  routing: RoutingSettings(
    direction: RoutingDirection.bypass,
    bypassLocal: true,
    geoEnabled: true,
    geoCodes: ['ru'],
    domainEnabled: true,
    domainZones: ['su'],
    geositeEnabled: true,
    geositeCodes: ['g'],
    adBlockEnabled: true,
    sitesEnabled: true,
    sites: ['s.example'],
    ruServicesEnabled: true,
  ),
  updateChannel: UpdateChannel.beta,
  fontScale: FontScale.large,
  geoipUrl: 'https://geo/ip',
  geositeUrl: 'https://geo/site',
  sniffingEnabled: false,
  mtu: 1280,
  subAutoRefresh: true,
  subAutoRefreshHours: 12,
  subUserAgent: 'UA',
  obsProbeIntervalSec: 60,
  dnsQueryStrategy: DnsQueryStrategy.auto,
  blockQuic: true,
  ipv6Enabled: true,
  allowTethering: true,
  autoStartOnBoot: true,
  automationEnabled: true,
  tlsFingerprint: TlsFingerprint.firefox,
  fragment: FragmentSettings(enabled: true, packets: '1-2'),
  noise: NoiseSettings(enabled: true, type: NoiseType.str, packet: 'x'),
  mux: MuxSettings(enabled: true, concurrency: 2),
  heartbeat: HeartbeatSettings(probe: HeartbeatProbe.passive, failureThreshold: 9),
  logsEnabled: false,
  coreOrder: [CoreKind.xrayRust, CoreKind.xrayGo, CoreKind.singBox],
  disabledCores: {CoreKind.singBox},
);

void main() {
  group('AppSettings', () {
    test('custom settings differ from defaults in every field', () {
      final defaults = const AppSettings().toJson();
      final custom = _custom.toJson();
      expect(custom.keys, unorderedEquals(defaults.keys));
      for (final k in defaults.keys) {
        expect(custom[k], isNot(equals(defaults[k])), reason: k);
      }
    });

    test('json round trip keeps every field', () {
      expect(AppSettings.fromJson(_custom.toJson()).toJson(), _custom.toJson());
    });

    test('empty json gives constructor defaults', () {
      expect(AppSettings.fromJson(const {}).toJson(), const AppSettings().toJson());
    });

    test('copyWith with no arguments is identity', () {
      expect(_custom.copyWith().toJson(), _custom.toJson());
    });

    test('unknown enum names fall back to defaults', () {
      final s = AppSettings.fromJson(const {
        'logLevel': 'x', 'vpnMode': 'x', 'dnsMode': 'x', 'updateChannel': 'x',
        'fontScale': 'x', 'dnsQueryStrategy': 'x', 'tlsFingerprint': 'x', 'core': 'x',
        'fragment': 'not a map',
      });
      expect(s.toJson(), const AppSettings().toJson());
    });

    test('dnsServer maps preset and custom type', () {
      expect(const AppSettings().dnsServer.address, '1.1.1.1');
      expect(const AppSettings(dnsPreset: 'google_doh').dnsServer.type, DnsType.doh);
      final dot = const AppSettings(dnsPreset: 'custom', customDnsAddress: 'd.example', customDnsType: 'dot')
          .dnsServer;
      expect(dot.type, DnsType.dot);
      expect(dot.port, 853);
      expect(const AppSettings(dnsPreset: 'custom', customDnsType: 'doh').dnsServer.type, DnsType.doh);
      expect(const AppSettings(dnsPreset: 'custom', customDnsType: 'junk').dnsServer.type, DnsType.udp);
    });
  });

  test('TlsFingerprint.xrayValue', () {
    expect(TlsFingerprint.defaultFp.xrayValue, isNull);
    expect(TlsFingerprint.chrome.xrayValue, 'chrome');
    expect(TlsFingerprint.randomized.xrayValue, 'randomized');
  });

  test('GeoPresets.nameOf', () {
    expect(GeoPresets.nameOf(GeoPresets.defaultGeoipUrl, GeoPresets.defaultGeositeUrl), 'Loyalsoldier');
    expect(GeoPresets.nameOf(GeoPresets.v2fly.geoipUrl, GeoPresets.v2fly.geositeUrl), 'v2fly');
    expect(GeoPresets.nameOf(GeoPresets.v2fly.geoipUrl, GeoPresets.runetfreedom.geositeUrl), 'custom');
  });

  group('AppConstants.subscriptionUserAgent', () {
    tearDown(() {
      AppConstants.appVersion = '';
      AppConstants.xrayCoreVersion = '';
    });

    test('unknown versions', () {
      expect(AppConstants.subscriptionUserAgent,
          'TeapodStream/unknown (Android; XrayNG-compatible) Xray-core/unknown');
    });

    test('known versions', () {
      AppConstants.appVersion = '1.2.3';
      AppConstants.xrayCoreVersion = '26.1.1';
      expect(AppConstants.subscriptionUserAgent,
          'TeapodStream/1.2.3 (Android; XrayNG-compatible) Xray-core/26.1.1');
    });
  });

  group('SettingsService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({'storage_migrated_v2': true});
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('fresh install loads constructor defaults', () async {
      expect((await SettingsService().load()).toJson(), const AppSettings().toJson());
    });

    test('save/load round trip keeps every field', () async {
      await SettingsService().save(_custom);
      expect((await SettingsService().load()).toJson(), _custom.toJson());
    });

    test('SOCKS credentials go to secure storage, not prefs', () async {
      await SettingsService().save(_custom);
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys()) {
        expect(prefs.get(k).toString(), isNot(contains('s3cr3t-pw')), reason: k);
      }
      final secure = await const FlutterSecureStorage().readAll();
      expect(secure['socks_password_v2'], 's3cr3t-pw');
      expect(secure['socks_user_v2'], 'user');
    });

    test('corrupt nested json falls back to defaults', () async {
      SharedPreferences.setMockInitialValues({
        'storage_migrated_v2': true,
        'xray_fragment': '{broken',
        'xray_noise': '[]',
        'xray_mux': '',
        'heartbeat_settings': '{"probe":"passive"}',
      });
      final s = await SettingsService().load();
      expect(s.fragment.toJson(), const FragmentSettings().toJson());
      expect(s.noise.toJson(), const NoiseSettings().toJson());
      expect(s.mux.toJson(), const MuxSettings().toJson());
      expect(s.heartbeat.probe, HeartbeatProbe.passive);
    });
  });
}
