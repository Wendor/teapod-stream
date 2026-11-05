import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/models/connections_bundle.dart';
import 'package:teapodstream/core/models/profile.dart';
import 'package:teapodstream/core/models/profile_bundle.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/services/config_storage_service.dart';
import 'package:teapodstream/core/services/settings_service.dart';

VpnConfig _cfg(String id, {String? rawUri, String? subId}) => VpnConfig(
      id: id,
      name: 'n$id',
      protocol: VpnProtocol.trojan,
      address: 'h$id.example',
      port: 443,
      uuid: '',
      password: 'p',
      security: VpnSecurity.tls,
      transport: VpnTransport.tcp,
      createdAt: DateTime(2026),
      rawUri: rawUri,
      subscriptionId: subId,
    );

Subscription _sub({String? pin}) => Subscription(
      id: 's1',
      name: 'Sub',
      url: 'https://sub.example/x',
      createdAt: DateTime(2026),
      lastFetchedAt: DateTime(2026, 2),
      expireAt: DateTime(2027),
      uploadBytes: 1,
      downloadBytes: 2,
      totalBytes: 3,
      announce: 'hi',
      announceUrl: 'https://a',
      pinnedCertDer: pin,
    );

Profile _profile() => Profile(
      id: 'p1',
      name: 'Work',
      readonly: true,
      settings: const AppSettings(mtu: 1400, killSwitchEnabled: true),
      createdAt: DateTime(2026, 3),
      sourceUrl: 'https://p.example/profile.json',
      lastFetchedAt: DateTime(2026, 4),
    );

void main() {
  group('Subscription', () {
    test('json round trip keeps every field', () {
      final s = _sub(pin: 'DER');
      expect(Subscription.fromJson(s.toJson()).toJson(), s.toJson());
    });

    test('nullable fields stay null', () {
      final s = Subscription(id: 'a', name: 'b', url: 'c', createdAt: DateTime(2026));
      final back = Subscription.fromJson(s.toJson());
      expect(back.lastFetchedAt, isNull);
      expect(back.expireAt, isNull);
      expect(back.pinnedCertDer, isNull);
    });

    test('copyWith keeps url, createdAt and the certificate pin', () {
      final s = _sub(pin: 'DER').copyWith(name: 'New', totalBytes: 9);
      expect(s.name, 'New');
      expect(s.totalBytes, 9);
      expect(s.url, 'https://sub.example/x');
      expect(s.pinnedCertDer, 'DER');
      expect(s.announce, 'hi');
    });
  });

  group('Profile', () {
    test('json round trip', () {
      final p = _profile();
      final back = Profile.fromJson(p.toJson());
      expect(back.toJson(), p.toJson());
      expect(back.settings.mtu, 1400);
      expect(back.isFromUrl, isTrue);
    });

    test('optional fields are omitted and defaulted', () {
      final p = Profile(id: 'd', name: 'D', isDefault: true, settings: const AppSettings(),
          createdAt: DateTime(2026));
      final json = p.toJson();
      expect(json.containsKey('sourceUrl'), isFalse);
      expect(json.containsKey('lastFetchedAt'), isFalse);
      final back = Profile.fromJson({...json}..remove('settings')..remove('readonly'));
      expect(back.isDefault, isTrue);
      expect(back.readonly, isFalse);
      expect(back.isFromUrl, isFalse);
    });

    test('copyWith keeps id, isDefault and createdAt', () {
      final p = _profile().copyWith(name: 'X', readonly: false);
      expect(p.id, 'p1');
      expect(p.name, 'X');
      expect(p.readonly, isFalse);
      expect(p.createdAt, DateTime(2026, 3));
    });
  });

  group('ProfileBundle', () {
    test('base64 round trip without padding', () {
      final b = ProfileBundle(
        exportedAt: DateTime(2026, 5),
        profile: _profile(),
        configs: [_cfg('1')],
        subscriptions: [_sub()],
        sourceUrl: 'https://src',
      );
      final b64 = b.toBase64();
      expect(b64.contains('='), isFalse);
      final back = ProfileBundle.fromBase64(b64);
      expect(back.toJson(), b.toJson());
      expect(back.hasConnections, isTrue);
      expect(b.toDeeplink(), 'teapod://import/profile?data=$b64');
    });

    test('settings-only bundle has no connections', () {
      final b = ProfileBundle(exportedAt: DateTime(2026), profile: _profile());
      final json = b.toJson();
      expect(json.containsKey('configs'), isFalse);
      expect(json.containsKey('subscriptions'), isFalse);
      expect(ProfileBundle.fromJson(json).hasConnections, isFalse);
      expect(ProfileBundle(exportedAt: DateTime(2026), profile: _profile(), configs: const [])
          .hasConnections, isFalse);
    });

    test('missing version defaults to 1', () {
      final json = ProfileBundle(exportedAt: DateTime(2026), profile: _profile()).toJson()
        ..remove('version');
      expect(ProfileBundle.fromJson(json).version, 1);
    });
  });

  group('ConnectionsBundle', () {
    final bundle = ConnectionsBundle(
      exportedAt: DateTime(2026, 6),
      label: 'set',
      configs: [_cfg('1', rawUri: 'trojan://a'), _cfg('2')],
      subscriptions: [_sub()],
    );

    test('full format round trip', () {
      final back = ConnectionsBundle.fromBase64(bundle.toBase64());
      expect(back.isCompact, isFalse);
      expect(back.label, 'set');
      expect(back.configs.map((c) => c.id), ['1', '2']);
      expect(back.subscriptions.single.url, 'https://sub.example/x');
      expect(bundle.toDeeplink(), startsWith('teapod://import/connections?data='));
    });

    test('compact format keeps only raw URIs and subscription URLs', () {
      final json = bundle.toCompactJson();
      expect(json['configs'], ['trojan://a']);
      expect(json['subscriptions'], ['https://sub.example/x']);

      final back = ConnectionsBundle.fromBase64(bundle.toCompactBase64());
      expect(back.isCompact, isTrue);
      expect(back.rawUris, ['trojan://a']);
      expect(back.subscriptionUrls, ['https://sub.example/x']);
      expect(back.configs, isEmpty);
      expect(back.subscriptions, isEmpty);
      expect(bundle.toCompactDeeplink(),
          'teapod://import/connections?data=${bundle.toCompactBase64()}');
    });

    test('mixed lists are split and junk entries ignored', () {
      final back = ConnectionsBundle.fromJson({
        'exportedAt': '2026-01-01T00:00:00.000',
        'configs': ['vless://x', _cfg('3').toJson(), 42],
        'subscriptions': ['https://s', _sub().toJson(), null],
      });
      expect(back.version, 1);
      expect(back.rawUris, ['vless://x']);
      expect(back.configs.single.id, '3');
      expect(back.subscriptionUrls, ['https://s']);
      expect(back.subscriptions.single.id, 's1');
    });

    test('missing lists give an empty bundle', () {
      final back = ConnectionsBundle.fromJson({'exportedAt': '2026-01-01T00:00:00.000'});
      expect(back.configs, isEmpty);
      expect(back.isCompact, isFalse);
    });
  });
}
