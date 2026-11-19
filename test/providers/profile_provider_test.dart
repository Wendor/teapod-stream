import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teapodstream/core/models/config_selection.dart';
import 'package:teapodstream/core/models/heartbeat_settings.dart';
import 'package:teapodstream/core/models/pinned_ref.dart';
import 'package:teapodstream/core/models/profile.dart';
import 'package:teapodstream/core/models/profile_bundle.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/services/config_storage_service.dart';
import 'package:teapodstream/core/services/profile_storage_service.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/providers/config_provider.dart';
import 'package:teapodstream/providers/profile_provider.dart';
import 'package:teapodstream/providers/settings_provider.dart';

const _local = AppSettings(
  socksPort: 1111,
  randomPort: false,
  randomCredentials: false,
  socksUser: 'localUser',
  socksPassword: 'localPass',
  hwidEnabled: false,
  heartbeat: HeartbeatSettings(target: HeartbeatTarget.apple),
);

/// Foreign settings try to expose the tunnel: an open SOCKS, proxy-only, a custom probe URL.
const _foreign = AppSettings(
  mtu: 1280,
  killSwitchEnabled: true,
  socksPort: 9999,
  randomPort: true,
  randomCredentials: true,
  socksUser: 'evil',
  socksPassword: 'evil',
  proxyOnly: true,
  hwidEnabled: true,
  automationEnabled: true,
  heartbeat: HeartbeatSettings(failureThreshold: 8, target: HeartbeatTarget.custom, customUrl: 'http://attacker/log'),
);

VpnConfig _cfg(String id, {String? name, String? subId}) => VpnConfig(
  id: id,
  name: name ?? id,
  subscriptionId: subId,
  protocol: VpnProtocol.trojan,
  address: 'h$id',
  port: 443,
  uuid: '',
  password: 'p',
  security: VpnSecurity.tls,
  transport: VpnTransport.tcp,
  createdAt: DateTime(2026),
);

ProfileBundle _bundle({AppSettings settings = _foreign, bool withConfigs = false}) => ProfileBundle(
  exportedAt: DateTime(2026),
  profile: Profile(id: 'remote', name: 'Remote', settings: settings, createdAt: DateTime(2026)),
  configs: withConfigs ? [_cfg('r1')] : null,
);

void main() {
  late ProviderContainer c;
  final profiles = ProfileStorageService();

  ProfileNotifier n() => c.read(profileProvider.notifier);
  ProfileState s() => c.read(profileProvider).value!;
  Future<AppSettings> settings() => c.read(settingsProvider.future);

  /// [keepStorage] — storage was already seeded by the test.
  Future<void> boot({List<Profile>? stored, String? activeId, bool keepStorage = false}) async {
    if (!keepStorage) {
      SharedPreferences.setMockInitialValues({'storage_migrated_v2': true});
      FlutterSecureStorage.setMockInitialValues({});
    }
    await SettingsService().save(_local);
    if (stored != null) await profiles.saveProfiles(stored);
    if (activeId != null) await profiles.saveActiveProfileId(activeId);
    c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(profileProvider.future);
    await settings();
  }

  Profile profile(String id, {bool isDefault = false, AppSettings settings = const AppSettings()}) =>
      Profile(id: id, name: id, isDefault: isDefault, settings: settings, createdAt: DateTime(2026));

  group('build', () {
    test('first launch creates the default profile from current settings', () async {
      await boot();
      final p = s().activeProfile!;
      expect(p.id, 'default');
      expect(p.isDefault, isTrue);
      expect(p.settings.socksPort, 1111);
      expect((await profiles.loadProfiles()).single.id, 'default');
      expect(await profiles.loadActiveProfileId(), 'default');
    });

    test('missing active profile falls back to the first one', () async {
      await boot(stored: [profile('a'), profile('b')], activeId: 'ghost');
      expect(s().activeProfileId, 'a');
      expect(await profiles.loadActiveProfileId(), 'a');
    });
  });

  group('crud', () {
    test('create copies current settings or uses defaults', () async {
      await boot();
      await n().createProfile('Copy');
      await n().createProfile('Clean', copyFromCurrent: false);
      final byName = {for (final p in s().profiles) p.name: p};
      expect(byName['Copy']!.settings.socksPort, 1111);
      expect(byName['Clean']!.settings.socksPort, const AppSettings().socksPort);
      expect((await profiles.loadProfiles()).length, 3);
    });

    test('rename and toggle readonly', () async {
      await boot(stored: [profile('a', isDefault: true), profile('b')], activeId: 'a');
      await n().renameProfile('b', 'Bee');
      await n().toggleReadonly('b');
      final b = (await profiles.loadProfiles()).last;
      expect(b.name, 'Bee');
      expect(b.readonly, isTrue);
      await n().toggleReadonly('b');
      expect(s().profiles.last.readonly, isFalse);
    });

    test('default and active profiles cannot be deleted', () async {
      await boot(stored: [profile('def', isDefault: true), profile('act'), profile('other')], activeId: 'act');
      await n().deleteProfile('def');
      await n().deleteProfile('act');
      expect(s().profiles, hasLength(3));
      await n().deleteProfile('other');
      expect(s().profiles.map((p) => p.id), ['def', 'act']);
      expect((await profiles.loadProfiles()).length, 2);
    });
  });

  test('switchProfile applies its settings', () async {
    await boot(
      stored: [
        profile('a', settings: _local),
        profile('b', settings: const AppSettings(mtu: 1300)),
      ],
      activeId: 'a',
    );
    await n().switchProfile('b');
    expect(s().activeProfileId, 'b');
    expect(await profiles.loadActiveProfileId(), 'b');
    expect((await settings()).mtu, 1300);
    expect((await SettingsService().load()).mtu, 1300);
  });

  group('switchProfile and the selected server', () {
    final storage = ConfigStorageService();
    ConfigState configs() => c.read(configProvider).value!;

    Future<void> seed(List<VpnConfig> list, {String? activeId}) async {
      await storage.saveConfigs(list);
      await storage.saveActiveConfigId(activeId);
      await storage.saveSubscriptions([
        Subscription(id: 's1', name: 'S', url: 'https://s1', createdAt: DateTime(2026)),
      ]);
    }

    test('each profile keeps its own server', () async {
      SharedPreferences.setMockInitialValues({'storage_migrated_v2': true});
      FlutterSecureStorage.setMockInitialValues({});
      await seed([_cfg('x'), _cfg('y')], activeId: 'x');
      await boot(stored: [profile('a'), profile('b')], activeId: 'a', keepStorage: true);

      // b has no remembered server yet — it takes the current one
      await n().switchProfile('b');
      expect(configs().activeConfigId, 'x');
      await c.read(configProvider.notifier).setActiveConfig('y');

      await n().switchProfile('a');
      expect(configs().activeConfigId, 'x');
      expect(await storage.loadActiveConfigId(), 'x');

      await n().switchProfile('b');
      expect(configs().activeConfigId, 'y');
      final stored = {for (final p in await profiles.loadProfiles()) p.id: p.selection};
      expect(stored['a']!.config!.name, 'x');
      expect(stored['b']!.config!.name, 'y');
    });

    test('the remembered server survives new config ids and restores auto-select', () async {
      SharedPreferences.setMockInitialValues({'storage_migrated_v2': true});
      FlutterSecureStorage.setMockInitialValues({});
      // a subscription refresh issued new ids: the profile resolves by name and endpoint
      await seed([_cfg('new1', name: 'NL', subId: 's1'), _cfg('loc')], activeId: 'loc');
      final remembered = ConfigSelection(
        config: PinnedRef.of(_cfg('old1', name: 'NL', subId: 's1')),
        subscriptionId: 's1',
      );
      await boot(
        stored: [
          profile('a'),
          profile('b').copyWith(selection: remembered),
        ],
        activeId: 'a',
        keepStorage: true,
      );

      await n().switchProfile('b');
      expect(configs().activeConfigId, 'new1');
      expect(configs().activeSubscriptionId, 's1');
      expect(await storage.loadActiveSubscriptionId(), 's1');
    });

    test('of two configs with the same name and endpoint the chosen one is restored', () async {
      SharedPreferences.setMockInitialValues({'storage_migrated_v2': true});
      FlutterSecureStorage.setMockInitialValues({});
      await seed([_cfg('d1', name: 'Dup'), _cfg('d2', name: 'Dup')], activeId: 'd1');
      final twin = _cfg('d2', name: 'Dup');
      await boot(
        stored: [
          profile('a'),
          profile('b').copyWith(
            selection: ConfigSelection(configId: 'd2', config: PinnedRef.of(twin)),
          ),
        ],
        activeId: 'a',
        keepStorage: true,
      );
      await n().switchProfile('b');
      expect(configs().activeConfigId, 'd2');
    });

    test('a settings sync started before the switch is not lost', () async {
      await boot(
        stored: [
          profile('a', settings: _local),
          profile('b'),
        ],
        activeId: 'a',
      );
      final sync = n().syncActiveSettings(_local.copyWith(mtu: 1234));
      await n().switchProfile('b');
      await sync;
      expect((await profiles.loadProfiles()).first.settings.mtu, 1234);
      expect(s().profiles.first.settings.mtu, 1234);
    });

    test('a settings sync saved during the switch stays with the outgoing profile', () async {
      await boot(
        stored: [
          profile('a', settings: _local),
          profile('b'),
        ],
        activeId: 'a',
      );
      final switching = n().switchProfile('b');
      final sync = n().syncActiveSettings(_local.copyWith(mtu: 1234));
      await switching;
      await sync;
      final stored = await profiles.loadProfiles();
      expect(stored.first.settings.mtu, 1234);
      expect(stored.last.settings.mtu, const AppSettings().mtu);
    });

    test('two quick switches keep each profile its own server', () async {
      SharedPreferences.setMockInitialValues({'storage_migrated_v2': true});
      FlutterSecureStorage.setMockInitialValues({});
      await seed([_cfg('x'), _cfg('y'), _cfg('z')], activeId: 'x');
      ConfigSelection sel(String id) => ConfigSelection(configId: id, config: PinnedRef.of(_cfg(id)));
      await boot(
        stored: [
          profile('a'),
          profile('b').copyWith(selection: sel('y')),
          profile('c').copyWith(selection: sel('z')),
        ],
        activeId: 'a',
        keepStorage: true,
      );
      await c.read(configProvider.future);
      // a config mutation delays restoring b's server
      final busy = c.read(configProvider.notifier).updateConfig(_cfg('x'));
      final toB = n().switchProfile('b');
      final toC = n().switchProfile('c');
      await Future.wait([busy, toB, toC]);
      expect(configs().activeConfigId, 'z');
      final stored = {for (final p in await profiles.loadProfiles()) p.id: p.selection?.configId};
      expect(stored, {'a': 'x', 'b': 'y', 'c': 'z'});
    });

    test('a vanished server leaves the current selection', () async {
      SharedPreferences.setMockInitialValues({'storage_migrated_v2': true});
      FlutterSecureStorage.setMockInitialValues({});
      await seed([_cfg('x')], activeId: 'x');
      final gone = ConfigSelection(config: PinnedRef.of(_cfg('gone')), subscriptionId: 'deleted');
      await boot(
        stored: [
          profile('a'),
          profile('b').copyWith(selection: gone),
        ],
        activeId: 'a',
        keepStorage: true,
      );

      await n().switchProfile('b');
      expect(configs().activeConfigId, 'x');
      expect(configs().activeSubscriptionId, isNull);
    });
  });

  group('settingsProvider', () {
    test('save persists and syncs the active profile', () async {
      await boot();
      await c.read(settingsProvider.notifier).save(_local.copyWith(mtu: 1350));
      expect((await SettingsService().load()).mtu, 1350);
      await Future<void>.delayed(Duration.zero);
      expect(s().activeProfile!.settings.mtu, 1350);
      expect((await profiles.loadProfiles()).single.settings.mtu, 1350);
    });

    test('readonly profile blocks saving', () async {
      await boot(
        stored: [profile('ro', settings: _local).copyWith(readonly: true)],
        activeId: 'ro',
      );
      expect(s().isReadonly, isTrue);
      await c.read(settingsProvider.notifier).save(_local.copyWith(mtu: 1000));
      expect((await settings()).mtu, 1500);
      expect((await SettingsService().load()).mtu, 1500);
    });

    test('toggleExcludedPackage and cleanGhostPackages', () async {
      await boot();
      final sn = c.read(settingsProvider.notifier);
      await sn.save(_local.copyWith(includedPackages: {'in.a', 'in.gone'}, excludedPackages: {'ex.a'}));
      await sn.toggleExcludedPackage('ex.b');
      await sn.toggleExcludedPackage('ex.a');
      expect((await settings()).excludedPackages, {'ex.b'});

      await sn.cleanGhostPackages({'in.a', 'ex.b'});
      final cleaned = await settings();
      expect(cleaned.includedPackages, {'in.a'});
      expect(cleaned.excludedPackages, {'ex.b'});
      expect((await SettingsService().load()).includedPackages, {'in.a'});
    });
  });

  group('importBundle', () {
    test('foreign profile cannot change tunnel-critical settings', () async {
      await boot();
      final id = (await n().importBundle(_bundle(), sourceUrl: 'https://src'))!;
      final p = s().profiles.firstWhere((p) => p.id == id);
      expect(s().activeProfileId, id);
      expect(p.sourceUrl, 'https://src');
      expect(p.lastFetchedAt, isNotNull);

      final applied = await settings();
      expect(applied.mtu, 1280);
      expect(applied.killSwitchEnabled, isTrue);
      expect(applied.heartbeat.failureThreshold, 8);
      expect(applied.socksPort, 1111);
      expect(applied.randomPort, isFalse);
      expect(applied.randomCredentials, isFalse);
      expect(applied.socksUser, 'localUser');
      expect(applied.socksPassword, 'localPass');
      expect(applied.proxyOnly, isFalse);
      expect(applied.hwidEnabled, isFalse);
      expect(applied.automationEnabled, isFalse);
      expect(applied.heartbeat.target, HeartbeatTarget.apple);
      expect(applied.heartbeat.customUrl, '');
    });

    test('readonly import without switching, connections imported', () async {
      await boot();
      final id = await n().importBundle(_bundle(withConfigs: true), switchToProfile: false, makeReadonly: true);
      expect(s().activeProfileId, 'default');
      expect(s().profiles.firstWhere((p) => p.id == id).readonly, isTrue);
      expect((await ConfigStorageService().loadConfigs()).single.name, 'r1');
    });
  });

  test('exportBundle with and without connections', () async {
    await boot();
    await c.read(configProvider.future);
    await c.read(configProvider.notifier).addConfig(_cfg('mine'));
    await n().createProfile('Other');
    await n().switchProfile(s().profiles.last.id);
    expect((await profiles.loadProfiles()).first.selection, isNotNull);
    final plain = n().exportBundle('default');
    expect(plain.profile.selection, isNull);
    expect(plain.hasConnections, isFalse);
    expect(plain.profile.id, 'default');
    final full = n().exportBundle('default', includeConnections: true);
    expect(full.configs!.single.id, 'mine');
    expect(full.subscriptions, isEmpty);
  });

  group('refreshProfile', () {
    Future<String?> refresh(String id, http.Response Function() respond) => http.runWithClient(
      () => n().refreshProfile(id, 'https://src/profile.json'),
      () => MockClient((_) async => respond()),
    );

    test('updates name and settings, applies them to the active profile', () async {
      await boot(
        stored: [profile('p', settings: _local)],
        activeId: 'p',
      );
      final r = await refresh('p', () => http.Response(jsonEncode(_bundle().toJson()), 200));
      expect(r, 'p');
      final p = s().activeProfile!;
      expect(p.name, 'Remote');
      expect(p.lastFetchedAt, isNotNull);
      expect(p.settings.mtu, 1280);
      expect(p.settings.socksUser, 'localUser');
      expect(p.settings.proxyOnly, isFalse);
      final applied = await settings();
      expect(applied.mtu, 1280);
      expect(applied.proxyOnly, isFalse);
    });

    test('inactive profile is updated but not applied', () async {
      await boot(
        stored: [
          profile('a', settings: _local),
          profile('b', settings: _local),
        ],
        activeId: 'a',
      );
      await refresh('b', () => http.Response(jsonEncode(_bundle().toJson()), 200));
      expect(s().profiles.last.settings.mtu, 1280);
      expect((await settings()).mtu, 1500);
    });

    test('bad response or unknown profile gives null', () async {
      await boot();
      expect(await refresh('default', () => http.Response('', 500)), isNull);
      expect(await refresh('default', () => http.Response('not json', 200)), isNull);
      expect(await refresh('ghost', () => http.Response(jsonEncode(_bundle().toJson()), 200)), isNull);
      expect(s().activeProfile!.name, 'Default');
    });
  });
}
