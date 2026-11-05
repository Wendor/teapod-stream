import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teapodstream/core/models/pinned_ref.dart';
import 'package:teapodstream/core/models/profile.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/services/config_storage_service.dart';
import 'package:teapodstream/core/services/profile_storage_service.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/core/services/storage_secure_service.dart';

VpnConfig _cfg(String id, {String? subId}) => VpnConfig(
      id: id,
      name: 'n$id',
      protocol: VpnProtocol.vless,
      address: 'h$id',
      port: 443,
      uuid: 'u',
      security: VpnSecurity.none,
      transport: VpnTransport.tcp,
      createdAt: DateTime(2026),
      subscriptionId: subId,
    );

Subscription _sub(String id, {String url = 'https://s'}) =>
    Subscription(id: id, name: 'S$id', url: url, createdAt: DateTime(2026));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'storage_migrated_v2': true});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('ConfigStorageService configs', () {
    final s = ConfigStorageService();

    test('empty storage loads nothing', () async {
      expect(await s.loadConfigs(), isEmpty);
      expect(await s.loadSubscriptions(), isEmpty);
      expect(await s.loadPins(), isEmpty);
      expect(await s.loadActiveConfigId(), isNull);
      expect(await s.loadActiveSubscriptionId(), isNull);
    });

    test('add, batch add, update, remove', () async {
      await s.addConfig(_cfg('1'));
      await s.addConfigsBatch([_cfg('2'), _cfg('3')]);
      await s.addConfigsBatch(const []);
      expect((await s.loadConfigs()).map((c) => c.id), ['1', '2', '3']);

      await s.updateConfig(_cfg('2').copyWith(name: 'renamed'));
      await s.updateConfig(_cfg('missing'));
      final loaded = await s.loadConfigs();
      expect(loaded[1].name, 'renamed');
      expect(loaded.length, 3);

      await s.removeConfig('1');
      await s.removeConfigsBatch(['3', 'nope']);
      await s.removeConfigsBatch(const []);
      expect((await s.loadConfigs()).map((c) => c.id), ['2']);
    });

    test('standalone vs subscription configs', () async {
      await s.saveConfigs([_cfg('a'), _cfg('b', subId: 's1'), _cfg('c', subId: 's2')]);
      expect((await s.getStandaloneConfigs()).map((c) => c.id), ['a']);
      expect((await s.getConfigsForSubscription('s1')).map((c) => c.id), ['b']);
    });

    test('active ids can be set and cleared', () async {
      await s.saveActiveConfigId('x');
      await s.saveActiveSubscriptionId('y');
      expect(await s.loadActiveConfigId(), 'x');
      expect(await s.loadActiveSubscriptionId(), 'y');
      await s.saveActiveConfigId(null);
      await s.saveActiveSubscriptionId(null);
      expect(await s.loadActiveConfigId(), isNull);
      expect(await s.loadActiveSubscriptionId(), isNull);
    });
  });

  group('ConfigStorageService subscriptions', () {
    final s = ConfigStorageService();

    test('add, update, find by url', () async {
      await s.addSubscription(_sub('1', url: 'https://one'));
      await s.addSubscription(_sub('2', url: 'https://two'));
      await s.updateSubscription(_sub('2', url: 'https://two').copyWith(name: 'Two'));
      await s.updateSubscription(_sub('ghost'));
      final subs = await s.loadSubscriptions();
      expect(subs.map((x) => x.name), ['S1', 'Two']);
      expect((await s.findSubscriptionByUrl('https://two'))?.id, '2');
      expect(await s.findSubscriptionByUrl('https://none'), isNull);
    });

    test('removing a subscription removes its configs', () async {
      await s.addSubscription(_sub('1'));
      await s.saveConfigs([_cfg('a'), _cfg('b', subId: '1'), _cfg('c', subId: '2')]);
      await s.removeSubscription('1');
      expect(await s.loadSubscriptions(), isEmpty);
      expect((await s.loadConfigs()).map((c) => c.id), ['a', 'c']);
    });

    test('pins round trip', () async {
      const pins = [
        PinnedRef(subscriptionId: null, name: 'a', endpoint: 'h:1'),
        PinnedRef(subscriptionId: 's', name: 'b'),
      ];
      await s.savePins(pins);
      expect(await s.loadPins(), pins);
    });

    test('data is stored in secure storage only', () async {
      await s.addConfig(_cfg('1'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {'storage_migrated_v2'});
      final raw = await const FlutterSecureStorage().read(key: 'vpn_configs_v2');
      expect((jsonDecode(raw!) as List).single['id'], '1');
    });
  });

  group('StorageSecureService', () {
    test('socks credentials default to empty', () async {
      final s = StorageSecureService();
      final c = await s.readSocksCredentials();
      expect(c.user, '');
      expect(c.password, '');
      await s.writeSocksCredentials('u', 'p');
      final c2 = await s.readSocksCredentials();
      expect((c2.user, c2.password), ('u', 'p'));
    });

    test('device id and info', () async {
      final s = StorageSecureService();
      await s.writeDeviceId('dev');
      await s.writeDeviceInfoRaw('{}');
      expect(await s.readDeviceId(), 'dev');
      expect(await s.readDeviceInfoRaw(), '{}');
      await s.writeDeviceId(null);
      expect(await s.readDeviceId(), isNull);
    });
  });

  group('ProfileStorageService', () {
    final s = ProfileStorageService();
    Profile profile(String id) => Profile(
        id: id, name: id, settings: const AppSettings(), createdAt: DateTime(2026));

    test('active profile defaults to "default"', () async {
      expect(await s.loadActiveProfileId(), 'default');
      await s.saveActiveProfileId('p2');
      expect(await s.loadActiveProfileId(), 'p2');
    });

    test('profiles round trip and settings update', () async {
      expect(await s.loadProfiles(), isEmpty);
      await s.saveProfiles([profile('a'), profile('b')]);
      await s.updateProfileSettings('b', const AppSettings(mtu: 1300));
      await s.updateProfileSettings('ghost', const AppSettings(mtu: 1));
      final loaded = await s.loadProfiles();
      expect(loaded.map((p) => p.id), ['a', 'b']);
      expect(loaded[0].settings.mtu, 1500);
      expect(loaded[1].settings.mtu, 1300);
    });
  });
}
