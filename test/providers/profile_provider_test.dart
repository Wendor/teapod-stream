import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teapodstream/core/models/config_selection.dart';
import 'package:teapodstream/core/models/heartbeat_settings.dart';
import 'package:teapodstream/core/models/import_review.dart';
import 'package:teapodstream/core/models/pinned_ref.dart';
import 'package:teapodstream/core/models/profile.dart';
import 'package:teapodstream/core/models/profile_bundle.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/services/config_storage_service.dart';
import 'package:teapodstream/core/models/subscription.dart';
import 'package:teapodstream/core/services/profile_storage_service.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/core/models/app_message.dart';
import 'package:teapodstream/core/models/app_settings.dart';
import 'package:teapodstream/providers/config_provider.dart';
import 'package:teapodstream/providers/profile_provider.dart';
import 'package:teapodstream/providers/settings_provider.dart';

import '../helpers/local_server.dart';
import '../helpers/stored_settings.dart';

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
  geoipUrl: 'https://attacker/geoip.dat',
  geositeUrl: 'https://attacker/geosite.dat',
);

VpnConfig _cfg(String id, {String? name, String? subId, String? address}) => VpnConfig(
  id: id,
  name: name ?? id,
  subscriptionId: subId,
  protocol: VpnProtocol.trojan,
  address: address ?? 'h$id',
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
  Future<void> boot({
    List<Profile>? stored,
    String? activeId,
    bool keepStorage = false,
    List<Override> overrides = const [],
  }) async {
    if (!keepStorage) {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
    }
    // Stored profiles hold the settings in force; without them the per-key ones of before become the default's.
    if (stored == null) {
      await SettingsService().save(_local);
    } else {
      await SettingsService().markMigrated();
      await profiles.saveProfiles(stored);
    }
    if (activeId != null) await profiles.saveActiveProfileId(activeId);
    c = ProviderContainer(overrides: overrides);
    addTearDown(c.dispose);
    await c.read(profileProvider.future);
    await settings();
  }

  Profile profile(String id, {bool isDefault = false, AppSettings settings = const AppSettings()}) =>
      Profile(id: id, name: id, isDefault: isDefault, settings: settings, createdAt: DateTime(2026));

  group('settings in the active profile', () {
    test('the per-key settings of before become the active profile\'s once', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      // What 1.8.x stored: the settings per key, profiles with their own snapshot.
      await SettingsService().save(_local);
      await profiles.saveProfiles([profile('a'), profile('b', settings: const AppSettings(mtu: 1300))]);
      await profiles.saveActiveProfileId('b');
      c = ProviderContainer();
      addTearDown(c.dispose);

      expect((await settings()).toJson(), _local.toJson());
      final stored = {for (final p in await profiles.loadProfiles()) p.id: p.settings};
      expect(stored['b']!.toJson(), _local.toJson());
      expect(stored['a']!.toJson(), const AppSettings().toJson());

      // Done once: a later change of the old keys is not read again.
      await SettingsService().save(const AppSettings(mtu: 1400));
      c.invalidate(profileProvider);
      expect((await settings()).mtu, _local.mtu);
    });

    test('the flags native reads follow the active profile resolved at start', () async {
      SharedPreferences.setMockInitialValues({'automation_enabled': true});
      FlutterSecureStorage.setMockInitialValues({});
      await SettingsService().markMigrated();
      await profiles.saveProfiles([profile('a', settings: const AppSettings(autoStartOnBoot: true))]);
      await profiles.saveActiveProfileId('gone');
      c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(profileProvider.future);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('automation_enabled'), isFalse);
      expect(prefs.getBool('auto_start_on_boot'), isTrue);
    });

    test('two quick saves both land', () async {
      await boot(stored: [profile('a')], activeId: 'a');
      final notifier = c.read(settingsProvider.notifier);
      await Future.wait([notifier.toggleExcludedPackage('x.one'), notifier.toggleExcludedPackage('x.two')]);
      expect((await settings()).excludedPackages, {'x.one', 'x.two'});
      expect((await storedSettings()).excludedPackages, {'x.one', 'x.two'});
    });

    test('a readonly profile refuses a save', () async {
      await boot(stored: [profile('a').copyWith(readonly: true)], activeId: 'a');
      await c.read(settingsProvider.notifier).save(const AppSettings(mtu: 1300));
      expect((await settings()).mtu, const AppSettings().mtu);
      expect((await storedSettings()).mtu, const AppSettings().mtu);
    });

    test('the flags native reads follow a save and a switch', () async {
      await boot(
        stored: [
          profile('a'),
          profile('b', settings: const AppSettings(autoStartOnBoot: true)),
        ],
        activeId: 'a',
      );
      final prefs = await SharedPreferences.getInstance();
      await c.read(settingsProvider.notifier).save(const AppSettings(automationEnabled: true));
      expect(prefs.getBool('automation_enabled'), isTrue);
      expect(prefs.getBool('auto_start_on_boot'), isFalse);
      await n().switchProfile('b');
      expect(prefs.getBool('automation_enabled'), isFalse);
      expect(prefs.getBool('auto_start_on_boot'), isTrue);
    });
  });

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
    expect((await storedSettings()).mtu, 1300);
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
      SharedPreferences.setMockInitialValues({});
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
      SharedPreferences.setMockInitialValues({});
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
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      // same name and endpoint, different credentials (ids)
      await seed([_cfg('d1', name: 'Dup', address: 'same'), _cfg('d2', name: 'Dup', address: 'same')], activeId: 'd1');
      final twin = _cfg('d2', name: 'Dup', address: 'same');
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
      final sync = c.read(settingsProvider.notifier).save(_local.copyWith(mtu: 1234));
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
      final sync = c.read(settingsProvider.notifier).save(_local.copyWith(mtu: 1234));
      await switching;
      await sync;
      final stored = await profiles.loadProfiles();
      expect(stored.first.settings.mtu, 1234);
      expect(stored.last.settings.mtu, const AppSettings().mtu);
    });

    test('two quick switches keep each profile its own server', () async {
      SharedPreferences.setMockInitialValues({});
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

    test('the outgoing profile remembers a selection still queued in configs', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await seed([_cfg('x'), _cfg('y')], activeId: 'x');
      await boot(stored: [profile('a'), profile('b')], activeId: 'a', keepStorage: true);
      final cn = c.read(configProvider.notifier);
      await c.read(configProvider.future);
      final busy = cn.updateConfig(_cfg('x'));
      final select = cn.setActiveConfig('y');
      await n().switchProfile('b');
      await Future.wait([busy, select]);
      expect((await profiles.loadProfiles()).first.selection!.configId, 'y');
    });

    test('a refresh finishing after a switch keeps the switch', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await seed([_cfg('x')], activeId: 'x');
      await boot(stored: [profile('a'), profile('b')], activeId: 'a', keepStorage: true);
      final server = await LocalServer.start();
      addTearDown(server.close);
      final requested = Completer<void>();
      final respond = Completer<void>();
      server.handler = (r) async {
        requested.complete();
        await respond.future;
        r.response.write(jsonEncode(_bundle().toJson()));
        await r.response.close();
      };
      final refreshing = HttpOverrides.runWithHttpOverrides(
        () => n().refreshProfile('a', 'https://src/profile.json'),
        RedirectHttpOverrides(server.port),
      );
      await requested.future;
      await n().switchProfile('b');
      respond.complete();
      expect(await refreshing, isA<ProfileRefreshed>());

      expect(s().activeProfileId, 'b');
      final stored = await profiles.loadProfiles();
      expect(stored.first.name, 'Remote');
      expect(stored.first.selection!.configId, 'x');
      expect(stored.last.selection!.configId, 'x');
      expect((await settings()).mtu, const AppSettings().mtu);
    });

    test('a failed server restore still applies the profile settings', () async {
      await boot(
        stored: [
          profile('a', settings: _local),
          profile(
            'b',
            settings: const AppSettings(mtu: 1300),
          ).copyWith(selection: const ConfigSelection(configId: 'x')),
        ],
        activeId: 'a',
        overrides: [configProvider.overrideWith(_FailingSelection.new)],
      );
      await expectLater(n().switchProfile('b'), throwsA(isA<StateError>()));
      expect(s().activeProfileId, 'b');
      expect((await settings()).mtu, 1300);
    });

    test('a vanished server leaves the current selection', () async {
      SharedPreferences.setMockInitialValues({});
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
      expect((await storedSettings()).mtu, 1350);
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
      expect((await storedSettings()).mtu, 1500);
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
      expect((await storedSettings()).includedPackages, {'in.a'});
    });
  });

  group('importBundle', () {
    test('foreign profile cannot change tunnel-critical settings', () async {
      await boot();
      final id = (await n().importBundle(_bundle(), sourceUrl: 'https://src'))!;
      await n().switchProfile(id);
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
      expect(applied.geoipUrl, GeoPresets.defaultGeoipUrl);
      expect(applied.geositeUrl, GeoPresets.defaultGeositeUrl);
    });

    test('review lists the traffic settings it changes and the new subscription hosts', () async {
      await boot();
      await c.read(configProvider.future);
      await ConfigStorageService().saveSubscriptions([
        Subscription(id: 'k', name: 'K', url: 'https://known.example/s', createdAt: DateTime(2026)),
      ]);
      c.invalidate(configProvider);
      await c.read(configProvider.future);
      final bundle = ProfileBundle(
        exportedAt: DateTime(2026),
        profile: Profile(id: 'r', name: 'R', settings: _foreign, createdAt: DateTime(2026)),
        subscriptions: [
          Subscription(id: 'a', name: 'A', url: 'https://known.example/s', createdAt: DateTime(2026)),
          Subscription(id: 'b', name: 'B', url: 'https://new.example/s?token=1', createdAt: DateTime(2026)),
        ],
      );
      final review = await n().reviewImport(bundle);
      // SOCKS, proxy-only, heartbeat and geodata stay local: not listed, not applied.
      expect(review.changes, [TrafficSetting.killSwitch]);
      expect(review.subscriptionHosts, ['new.example']);
      expect((await n().reviewImport(_bundle(settings: _local))).isEmpty, isTrue);
    });

    test('readonly import without switching, connections imported', () async {
      await boot();
      final id = await n().importBundle(_bundle(withConfigs: true), makeReadonly: true);
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
    late LocalServer server;
    setUp(() async => server = await LocalServer.start());
    tearDown(() => server.close());

    /// Every request goes to [server], which answers [body] with [status].
    Future<ProfileRefresh> refresh(
      String id,
      String body, {
      int status = 200,
      String url = 'https://src/profile.json',
    }) {
      server.serve(body, status: status);
      return HttpOverrides.runWithHttpOverrides(() => n().refreshProfile(id, url), RedirectHttpOverrides(server.port));
    }

    test('updates name and settings, applies them to the active profile', () async {
      await boot(
        stored: [profile('p', settings: _local)],
        activeId: 'p',
      );
      final r = await refresh('p', jsonEncode(_bundle().toJson()));
      expect(r, isA<ProfileRefreshed>());
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
      await refresh('b', jsonEncode(_bundle().toJson()));
      expect(s().profiles.last.settings.mtu, 1280);
      expect((await settings()).mtu, 1500);
    });

    test('a bad response or an unknown profile fails with the reason', () async {
      await boot();
      AppMessage? failed(ProfileRefresh r) => r is ProfileRefreshFailed ? r.reason : null;
      expect(failed(await refresh('default', '', status: 500)), const AppMessage(MessageCode.bundleFetchFailed));
      expect(failed(await refresh('default', 'not json'))?.code, MessageCode.bundleInvalid);
      expect(
        failed(await refresh('ghost', jsonEncode(_bundle().toJson()))),
        const AppMessage(MessageCode.profileUpdateError),
      );
      expect(s().activeProfile!.name, 'Default');
    });

    test('geodata sources stay the profile\'s own on refresh', () async {
      const mine = AppSettings(geoipUrl: 'https://mine/geoip.dat', geositeUrl: 'https://mine/geosite.dat');
      await boot(
        stored: [profile('p', settings: mine)],
        activeId: 'p',
      );
      expect(await refresh('p', jsonEncode(_bundle().toJson())), isA<ProfileRefreshed>());
      expect(s().activeProfile!.settings.geoipUrl, 'https://mine/geoip.dat');
      expect((await settings()).geositeUrl, 'https://mine/geosite.dat');
    });

    test('a declined review applies nothing; no changes ask nothing', () async {
      await boot(
        stored: [profile('p', settings: _local)],
        activeId: 'p',
      );
      final asked = <ImportReview>[];
      Future<ProfileRefresh> refreshWith(String body, bool answer) {
        server.serve(body);
        return HttpOverrides.runWithHttpOverrides(
          () => n().refreshProfile(
            'p',
            'https://src/profile.json',
            confirm: (r) async {
              asked.add(r);
              return answer;
            },
          ),
          RedirectHttpOverrides(server.port),
        );
      }

      expect(await refreshWith(jsonEncode(_bundle().toJson()), false), isA<ProfileRefreshDeclined>());
      expect(asked.single.changes, [TrafficSetting.killSwitch]);
      expect(s().activeProfile!.name, 'p');
      expect((await settings()).killSwitchEnabled, isFalse);

      asked.clear();
      expect(
        await refreshWith(jsonEncode(_bundle(settings: _local.copyWith(mtu: 1280)).toJson()), false),
        isA<ProfileRefreshed>(),
      );
      expect(asked, isEmpty);
      expect((await settings()).mtu, 1280);
    });

    test('a plain http source is not fetched', () async {
      await boot();
      expect(
        await refresh('default', jsonEncode(_bundle().toJson()), url: 'http://src/profile.json'),
        isA<ProfileRefreshFailed>(),
      );
      expect(server.paths, isEmpty);
      expect(s().activeProfile!.name, 'Default');
    });
  });
}

class _FailingSelection extends ConfigNotifier {
  @override
  Future<void> applySelection(ConfigSelection selection) async => throw StateError('storage write failed');
}
