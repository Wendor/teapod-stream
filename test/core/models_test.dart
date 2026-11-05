import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/models/app_info.dart';
import 'package:teapodstream/core/models/heartbeat_settings.dart';
import 'package:teapodstream/core/models/routing_settings.dart';
import 'package:teapodstream/core/models/vpn_log_entry.dart';
import 'package:teapodstream/core/models/vpn_stats.dart';
import 'package:teapodstream/core/models/xray_tuning.dart';

void main() {
  group('VpnStats formatting', () {
    test('formatBytes picks the unit', () {
      expect(VpnStats.formatBytes(0), '0 B');
      expect(VpnStats.formatBytes(1023), '1023 B');
      expect(VpnStats.formatBytes(1024), '1.0 KB');
      expect(VpnStats.formatBytes(1536), '1.5 KB');
      expect(VpnStats.formatBytes(1024 * 1024), '1.0 MB');
      expect(VpnStats.formatBytes(3 * 1024 * 1024 * 1024), '3.00 GB');
    });

    test('formatSpeed converts bytes to bits', () {
      expect(VpnStats.formatSpeed(0), '0 bit/s');
      expect(VpnStats.formatSpeed(100), '800 bit/s');
      expect(VpnStats.formatSpeed(128), '1.0 Kbit/s');
      expect(VpnStats.formatSpeed(128 * 1024), '1.0 Mbit/s');
    });

    test('formatDuration pads every part', () {
      expect(VpnStats.formatDuration(Duration.zero), '00:00:00');
      expect(VpnStats.formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '01:02:03');
      expect(VpnStats.formatDuration(const Duration(hours: 100, seconds: 59)), '100:00:59');
    });

    test('copyWith keeps untouched fields', () {
      const s = VpnStats(uploadBytes: 1, downloadBytes: 2, connectedServer: 'srv',
          speedHistory: [SpeedPoint(uploadSpeed: 5)]);
      final c = s.copyWith(downloadBytes: 9);
      expect(c.uploadBytes, 1);
      expect(c.downloadBytes, 9);
      expect(c.connectedServer, 'srv');
      expect(c.speedHistory.single.uploadSpeed, 5);
    });

    test('SpeedPoint.fromMap accepts nums and missing keys', () {
      final p = SpeedPoint.fromMap({'uploadSpeed': 10.7, 'downloadSpeed': 3});
      expect(p.uploadSpeed, 10);
      expect(p.downloadSpeed, 3);
      expect(SpeedPoint.fromMap(const {}).uploadSpeed, 0);
    });
  });

  group('VpnLogEntry', () {
    test('json round trip', () {
      final e = VpnLogEntry(
          timestamp: DateTime(2026, 1, 2, 3, 4, 5), level: LogLevel.warning, message: 'm', source: 's');
      final back = VpnLogEntry.fromJson(e.toJson());
      expect(back.timestamp, e.timestamp);
      expect(back.level, LogLevel.warning);
      expect(back.message, 'm');
      expect(back.source, 's');
    });

    test('unknown level falls back to info', () {
      final e = VpnLogEntry.fromJson(
          {'timestamp': '2026-01-01T00:00:00.000', 'level': 'fatal', 'message': 'x'});
      expect(e.level, LogLevel.info);
      expect(e.source, isNull);
    });

    test('factories set the level', () {
      expect(VpnLogEntry.info('a').level, LogLevel.info);
      expect(VpnLogEntry.error('a').level, LogLevel.error);
      expect(VpnLogEntry.warning('a').level, LogLevel.warning);
      expect(VpnLogEntry.debug('a', source: 'x').source, 'x');
    });
  });

  test('AppInfo.copyWith keeps identity', () {
    const a = AppInfo(packageName: 'p', appName: 'n');
    final b = a.copyWith(isExcluded: true);
    expect(b.packageName, 'p');
    expect(b.appName, 'n');
    expect(b.isExcluded, isTrue);
    expect(b.isSystem, isFalse);
  });

  group('HeartbeatSettings', () {
    test('url uses preset or trimmed custom value', () {
      expect(const HeartbeatSettings().url, HeartbeatTarget.cloudflare.url);
      expect(const HeartbeatSettings(target: HeartbeatTarget.google).url,
          'http://connectivitycheck.gstatic.com/generate_204');
      expect(const HeartbeatSettings(target: HeartbeatTarget.custom, customUrl: ' http://x/ ').url,
          'http://x/');
      expect(const HeartbeatSettings(target: HeartbeatTarget.custom, customUrl: '  ').url,
          HeartbeatTarget.cloudflare.url);
    });

    test('json round trip keeps every field', () {
      const s = HeartbeatSettings(
        probe: HeartbeatProbe.passive,
        failureThreshold: 7,
        failAction: HeartbeatFailAction.switchConfig,
        switchSource: SwitchSource.pinned,
        target: HeartbeatTarget.apple,
        customUrl: 'http://c',
      );
      expect(HeartbeatSettings.fromJson(s.toJson()).toJson(), s.toJson());
    });

    test('empty json gives defaults', () {
      expect(HeartbeatSettings.fromJson(const {}).toJson(), const HeartbeatSettings().toJson());
    });

    test('pre-1.6.4 action/source keys are migrated', () {
      final s = HeartbeatSettings.fromJson(const {'action': 'urltest', 'source': 'all'});
      expect(s.failAction, HeartbeatFailAction.switchConfig);
      expect(s.switchSource, SwitchSource.all);
      expect(HeartbeatSettings.fromJson(const {'action': 'reconnect'}).failAction,
          HeartbeatFailAction.reconnect);
    });

    test('copyWith changes only given fields', () {
      final s = const HeartbeatSettings().copyWith(failureThreshold: 5);
      expect(s.failureThreshold, 5);
      expect(s.probe, HeartbeatProbe.socks);
    });
  });

  group('RoutingSettings', () {
    const full = RoutingSettings(
      direction: RoutingDirection.bypass,
      bypassLocal: true,
      geoEnabled: true,
      geoCodes: ['ru', 'by', 'kz'],
      domainEnabled: true,
      domainZones: ['ru', 'xn--p1ai', 'gov.spb.ru'],
      geositeEnabled: true,
      geositeCodes: ['a', 'b'],
      adBlockEnabled: true,
      sitesEnabled: true,
      sites: ['x.com'],
      ruServicesEnabled: true,
    );

    test('json round trip keeps every field', () {
      expect(RoutingSettings.fromJson(full.toJson()).toJson(), full.toJson());
      expect(RoutingSettings.fromJson(const {}).toJson(), const RoutingSettings().toJson());
    });

    test('isActive only for non-global direction', () {
      expect(const RoutingSettings().isActive, isFalse);
      expect(const RoutingSettings(direction: RoutingDirection.onlySelected).isActive, isTrue);
    });

    test('summary for global', () {
      expect(const RoutingSettings().summary, 'Глобальный');
      expect(const RoutingSettings(adBlockEnabled: true).summary, 'Ads✗');
    });

    test('summary lists every enabled part', () {
      expect(full.summary,
          'Обход: ru, by…, .ru, .рф…, geosite:2, sites:1, RU+, LAN, Ads✗');
    });

    test('summary keeps multi-level zones and handles empty only-mode', () {
      const s = RoutingSettings(
          direction: RoutingDirection.onlySelected, domainEnabled: true, domainZones: ['gov.spb.ru']);
      expect(s.summary, 'Только: gov.spb.ru');
      expect(const RoutingSettings(direction: RoutingDirection.onlySelected).summary, 'Только');
    });

    test('disabled lists do not show in summary', () {
      const s = RoutingSettings(direction: RoutingDirection.bypass, geoCodes: ['ru']);
      expect(s.summary, 'Обход');
    });
  });

  group('FragmentSettings', () {
    test('defaults are valid', () => expect(const FragmentSettings().isValid, isTrue));

    test('packets accept tlshello, empty or positive range', () {
      expect(const FragmentSettings(packets: '').isValid, isTrue);
      expect(const FragmentSettings(packets: '1-3').isValid, isTrue);
      expect(const FragmentSettings(packets: '0-3').isValid, isFalse);
      expect(const FragmentSettings(packets: 'abc').isValid, isFalse);
    });

    test('length and interval must be ranges', () {
      expect(const FragmentSettings(length: ' 10 - 20 ').isValid, isTrue);
      expect(const FragmentSettings(length: '20-10').isValid, isFalse);
      expect(const FragmentSettings(length: '0-10').isValid, isFalse);
      expect(const FragmentSettings(length: '').isValid, isFalse);
      expect(const FragmentSettings(interval: '0-0').isValid, isTrue);
      expect(const FragmentSettings(interval: '5').isValid, isFalse);
    });

    test('json round trip', () {
      const f = FragmentSettings(enabled: true, packets: '1-2', length: '5-6', interval: '7-8');
      expect(FragmentSettings.fromJson(f.toJson()).toJson(), f.toJson());
      expect(FragmentSettings.fromJson(const {}).toJson(), const FragmentSettings().toJson());
      expect(f.copyWith(enabled: false).packets, '1-2');
    });
  });

  group('NoiseSettings', () {
    test('rand needs a positive length range', () {
      expect(const NoiseSettings().isValid, isTrue);
      expect(const NoiseSettings(packet: '0-10').isValid, isFalse);
      expect(const NoiseSettings(packet: 'hello').isValid, isFalse);
    });

    test('other types accept any non-empty payload', () {
      expect(const NoiseSettings(type: NoiseType.str, packet: 'hello').isValid, isTrue);
      expect(const NoiseSettings(type: NoiseType.hex, packet: '  ').isValid, isFalse);
    });

    test('delay must be a range', () {
      expect(const NoiseSettings(delay: '10').isValid, isFalse);
    });

    test('json round trip and unknown type', () {
      const n = NoiseSettings(enabled: true, type: NoiseType.base64, packet: 'AA==', delay: '1-2');
      expect(NoiseSettings.fromJson(n.toJson()).toJson(), n.toJson());
      expect(NoiseSettings.fromJson(const {'type': 'bogus'}).type, NoiseType.rand);
      expect(n.copyWith(delay: '3-4').type, NoiseType.base64);
    });
  });

  test('MuxSettings json round trip', () {
    const m = MuxSettings(
        enabled: true, concurrency: 4, xudpConcurrency: 32, xudpProxyUDP443: XudpUdp443.skip);
    expect(MuxSettings.fromJson(m.toJson()).toJson(), m.toJson());
    expect(MuxSettings.fromJson(const {}).toJson(), const MuxSettings().toJson());
    expect(m.copyWith(concurrency: 1).xudpProxyUDP443, XudpUdp443.skip);
  });
}
