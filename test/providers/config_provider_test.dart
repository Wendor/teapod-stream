import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teapodstream/core/models/connections_bundle.dart';
import 'package:teapodstream/core/models/core_kind.dart';
import 'package:teapodstream/core/models/pinned_ref.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/models/vpn_log_entry.dart';
import 'package:teapodstream/core/services/config_storage_service.dart';
import 'package:teapodstream/core/services/device_service.dart';
import 'package:teapodstream/core/models/subscription.dart';
import 'package:teapodstream/core/services/log_service.dart';
import 'package:teapodstream/core/services/subscription_service.dart';
import 'package:teapodstream/providers/config_provider.dart';
import 'package:teapodstream/providers/settings_provider.dart';

import '../helpers/local_server.dart';

VpnConfig _cfg(
  String id, {
  String? subId,
  String? name,
  String address = '',
  int port = 443,
  int? latency,
  String? rawUri,
}) => VpnConfig(
  id: id,
  name: name ?? 'n$id',
  protocol: VpnProtocol.trojan,
  address: address.isEmpty ? 'h$id' : address,
  port: port,
  uuid: '',
  password: 'p',
  security: VpnSecurity.tls,
  transport: VpnTransport.tcp,
  createdAt: DateTime(2026),
  subscriptionId: subId,
  latencyMs: latency,
  rawUri: rawUri,
);

Subscription _sub(String id, {String? url, String? pin, DateTime? fetched}) => Subscription(
  id: id,
  name: 'S$id',
  url: url ?? 'https://$id',
  createdAt: DateTime(2026),
  lastFetchedAt: fetched,
  pinnedCertDer: pin,
);

String _trojan(String host, String name, {int port = 443}) =>
    'trojan://pw@$host:$port?security=tls#${Uri.encodeComponent(name)}';

/// Storage whose list writes fail on demand.
class _FailingStorage extends ConfigStorageService {
  bool failConfigs = false;
  bool failSubscriptions = false;

  @override
  Future<void> saveConfigs(List<VpnConfig> configs) =>
      failConfigs ? Future.error(StateError('configs')) : super.saveConfigs(configs);

  @override
  Future<void> saveSubscriptions(List<Subscription> subs) =>
      failSubscriptions ? Future.error(StateError('subscriptions')) : super.saveSubscriptions(subs);
}

void main() {
  late ProviderContainer c;
  final storage = ConfigStorageService();

  ConfigNotifier n() => c.read(configProvider.notifier);
  ConfigState s() => c.read(configProvider).value!;

  Future<void> boot({
    List<VpnConfig> configs = const [],
    List<Subscription> subs = const [],
    List<PinnedRef> pins = const [],
    String? activeId,
    String? activeSubId,
    Map<String, Object> prefs = const {},
    Map<String, String> secure = const {},
  }) async {
    SharedPreferences.setMockInitialValues({...prefs});
    FlutterSecureStorage.setMockInitialValues({});
    await DeviceService.clearCache();
    FlutterSecureStorage.setMockInitialValues({...secure});
    await storage.saveConfigs(configs);
    await storage.saveSubscriptions(subs);
    await storage.savePins(pins);
    await storage.saveActiveConfigId(activeId);
    await storage.saveActiveSubscriptionId(activeSubId);
    c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(configProvider.future);
  }

  group('ConfigState.withSubscription (pure)', () {
    final sub = _sub('s');
    VpnConfig old(String id, String name, String host, {int? latency, CoreKind? core}) =>
        _cfg(id, subId: 's', name: name, address: host, latency: latency).copyWith(core: core);
    VpnConfig fresh(String id, String name, String host) => _cfg(id, subId: 's', name: name, address: host);

    // (case, old configs, active id, fetched, expected [id, latency, core] per fetched, expected active)
    final cases = <(String, List<VpnConfig>, String?, List<VpnConfig>, List<(String, int?, CoreKind?)>, String)>[
      (
        'ping by endpoint, core by name+endpoint',
        [old('o1', 'A', 'h1', latency: 10, core: CoreKind.singBox), old('o2', 'B', 'h1', latency: 20)],
        null,
        [fresh('n1', 'A', 'h1'), fresh('n2', 'B', 'h1')],
        [('n1', 10, CoreKind.singBox), ('n2', 20, null)],
        'n1',
      ),
      (
        'renamed but unique endpoint keeps ping and core',
        [old('o1', 'A', 'h1', latency: 10, core: CoreKind.xrayRust)],
        null,
        [fresh('n1', 'A2', 'h1')],
        [('n1', 10, CoreKind.xrayRust)],
        'n1',
      ),
      (
        'ambiguous endpoint: last ping, no core',
        [old('o1', 'A', 'h1', latency: 10, core: CoreKind.singBox), old('o2', 'B', 'h1', latency: 20)],
        null,
        [fresh('n1', 'C', 'h1')],
        [('n1', 20, null)],
        'n1',
      ),
      (
        'selection by name+endpoint',
        [old('o1', 'A', 'h1'), old('o2', 'B', 'h1')],
        'o2',
        [fresh('n1', 'A', 'h1'), fresh('n2', 'B', 'h1')],
        [('n1', null, null), ('n2', null, null)],
        'n2',
      ),
      (
        'selection by endpoint when renamed',
        [old('o1', 'A', 'h1'), old('o2', 'B', 'h2')],
        'o2',
        [fresh('n1', 'A', 'h1'), fresh('n2', 'B2', 'h2')],
        [('n1', null, null), ('n2', null, null)],
        'n2',
      ),
      (
        'selection by name when moved',
        [old('o1', 'A', 'h1'), old('o2', 'B', 'h2')],
        'o2',
        [fresh('n1', 'A', 'h1'), fresh('n2', 'B', 'h3')],
        [('n1', null, null), ('n2', null, null)],
        'n2',
      ),
      (
        'vanished selection falls back to the first',
        [old('o1', 'A', 'h1')],
        'o1',
        [fresh('n1', 'X', 'h9'), fresh('n2', 'Y', 'h8')],
        [('n1', null, null), ('n2', null, null)],
        'n1',
      ),
      (
        'a dangling selection id falls back to the first',
        [old('o1', 'A', 'h1')],
        'gone',
        [fresh('n1', 'A', 'h1')],
        [('n1', null, null)],
        'n1',
      ),
      (
        'a selection outside the subscription stays',
        [old('o1', 'A', 'h1'), _cfg('mine')],
        'mine',
        [fresh('n1', 'A', 'h1')],
        [('n1', null, null)],
        'mine',
      ),
    ];

    for (final (name, olds, active, fetched, expected, expectedActive) in cases) {
      test(name, () {
        final before = ConfigState(
          configs: olds,
          subscriptions: [sub],
          activeConfigId: active,
          activeSubscriptionId: 'mode',
        );
        final after = before.withSubscription(sub.copyWith(name: 'renamed'), fetched);
        final merged = after.configs.where((c) => c.subscriptionId == 's').toList();
        expect([for (final c in merged) (c.id, c.latencyMs, c.core)], expected);
        expect(
          after.configs.where((c) => c.subscriptionId != 's').map((c) => c.id),
          olds.where((c) => c.subscriptionId != 's').map((c) => c.id),
        );
        expect(after.activeConfigId, expectedActive);
        expect(after.activeSubscriptionId, 'mode', reason: 'the subscription mode is left as it is');
        expect(after.subscriptions.single.name, 'renamed');
        expect(before.configs, olds, reason: 'pure');
      });
    }

    test('a new subscription is appended', () {
      final after = ConfigState(subscriptions: [_sub('a')]).withSubscription(sub, [fresh('n1', 'A', 'h1')]);
      expect(after.subscriptions.map((s) => s.id), ['a', 's']);
      expect(after.activeConfigId, 'n1');
    });

    test('withoutSubscription drops its configs, pins and the selection pointing into it', () {
      final before = ConfigState(
        configs: [
          _cfg('a'),
          _cfg('b', subId: 's'),
        ],
        subscriptions: [sub],
        pins: [
          const PinnedRef(subscriptionId: 's', name: 'nb'),
          const PinnedRef(subscriptionId: null, name: 'na'),
        ],
        activeConfigId: 'b',
        activeSubscriptionId: 's',
      );
      final after = before.withoutSubscription('s');
      expect(after.configs.map((c) => c.id), ['a']);
      expect(after.subscriptions, isEmpty);
      expect(after.pins.map((p) => p.name), ['na']);
      expect(after.activeConfigId, isNull);
      expect(after.activeSubscriptionId, isNull);
    });

    test('withoutSubscription clears a selection that resolves to nothing', () {
      final before = ConfigState(configs: [_cfg('a')], subscriptions: [sub], activeConfigId: 'gone');
      expect(before.withoutSubscription('s').activeConfigId, isNull);
    });
  });

  group('a failed write', () {
    late _FailingStorage failing;
    setUp(() {
      final original = ConfigNotifier.storage;
      ConfigNotifier.storage = failing = _FailingStorage();
      addTearDown(() => ConfigNotifier.storage = original);
    });

    test('in a removal publishes the configs saved before it; the next mutation keeps them', () async {
      await boot(
        configs: [
          _cfg('a'),
          _cfg('b', subId: 's'),
        ],
        subs: [_sub('s')],
      );
      failing.failSubscriptions = true;
      await expectLater(n().removeSubscription('s'), throwsStateError);
      expect(s().configs.map((x) => x.id), ['a']);
      expect(s().subscriptions.map((x) => x.id), ['s']);

      failing.failSubscriptions = false;
      await n().addConfig(_cfg('c'));
      expect((await storage.loadConfigs()).map((x) => x.id), ['a', 'c']);
      expect((await storage.loadSubscriptions()).map((x) => x.id), ['s']);
    });

    test('in an addition publishes the subscription saved before it; the next mutation keeps it', () async {
      await boot(configs: [_cfg('a')]);
      failing.failConfigs = true;
      final bundle = ConnectionsBundle(
        exportedAt: DateTime(2026),
        configs: [_cfg('x', subId: 'remote')],
        subscriptions: [_sub('remote', url: 'https://new')],
      );
      await expectLater(n().importBundle(bundle), throwsStateError);
      expect(s().subscriptions.map((x) => x.url), ['https://new']);
      expect(s().configs.map((x) => x.id), ['a']);

      failing.failConfigs = false;
      await n().addConfig(_cfg('c'));
      expect((await storage.loadSubscriptions()).map((x) => x.url), ['https://new']);
      expect((await storage.loadConfigs()).map((x) => x.id), ['a', 'c']);
    });
  });

  test('a mutation queued before build() finishes is kept', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await storage.saveConfigs([_cfg('1')]);
    c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(configProvider);
    await n().addConfig(_cfg('2'));
    expect(s().configs.map((c) => c.id), ['1', '2']);
    expect((await storage.loadConfigs()).map((c) => c.id), ['1', '2']);
  });

  test('after a failed load a mutation fails and stored configs stay', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await storage.saveConfigs([_cfg('1'), _cfg('2')]);
    // The configs read fine, the subscriptions don't.
    await const FlutterSecureStorage().write(key: 'subscriptions_v2', value: 'not json');
    c = ProviderContainer();
    addTearDown(c.dispose);
    c.listen(configProvider, (_, _) {});
    while (!c.read(configProvider).hasError) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await expectLater(n().addConfig(_cfg('3')), throwsA(anything));
    expect((await storage.loadConfigs()).map((c) => c.id), ['1', '2']);
  });

  test('build loads persisted state', () async {
    await boot(
      configs: [_cfg('1')],
      subs: [_sub('s')],
      activeId: '1',
      activeSubId: 's',
      pins: [const PinnedRef(subscriptionId: null, name: 'n1')],
    );
    expect(s().configs.single.id, '1');
    expect(s().subscriptions.single.id, 's');
    expect(s().activeConfig?.id, '1');
    expect(s().activeSubscriptionId, 's');
    expect(s().pins, hasLength(1));
  });

  group('configs', () {
    test('add, update, remove are persisted', () async {
      await boot();
      await n().addConfig(_cfg('1'));
      await n().addConfigs([_cfg('2'), _cfg('3')]);
      await n().updateConfig(_cfg('2', name: 'two'));
      await n().removeConfig('3');
      expect(s().configs.map((c) => c.name), ['n1', 'two']);
      expect((await storage.loadConfigs()).map((c) => c.name), ['n1', 'two']);
    });

    test('removing the active config clears selection', () async {
      await boot(configs: [_cfg('1'), _cfg('2')], activeId: '1');
      await n().removeConfig('2');
      expect(s().activeConfigId, '1');
      await n().removeConfig('1');
      expect(s().activeConfigId, isNull);
      expect(await storage.loadActiveConfigId(), isNull);
    });

    test('concurrent mutations are serialized and all persisted', () async {
      await boot();
      await Future.wait([for (var i = 0; i < 10; i++) n().addConfig(_cfg('$i'))]);
      expect((await storage.loadConfigs()).length, 10);
      expect(s().configs.length, 10);
    });

    test('selecting a config leaves subscription mode', () async {
      await boot(configs: [_cfg('1')], activeSubId: 's');
      await n().setActiveConfig('1');
      expect(s().activeConfigId, '1');
      expect(s().activeSubscriptionId, isNull);
      expect(await storage.loadActiveSubscriptionId(), isNull);
      await n().setActiveSubscription('s2');
      expect(s().activeSubscriptionId, 's2');
      expect(await storage.loadActiveSubscriptionId(), 's2');
      await n().setActiveSubscription(null);
      expect(s().activeSubscriptionId, isNull);
      await n().setActiveConfig(null);
      expect(s().activeConfigId, isNull);
    });
  });

  group('ConfigState', () {
    test('groups configs by subscription', () {
      final st = ConfigState(
        configs: [
          _cfg('a'),
          _cfg('b', subId: 's'),
          _cfg('c', subId: 's'),
        ],
      );
      expect(st.standaloneConfigs.map((c) => c.id), ['a']);
      expect(st.configsBySubscription['s']!.map((c) => c.id), ['b', 'c']);
      expect(st.activeConfig, isNull);
    });

    test('copyWith clear flags', () {
      final st = ConfigState(activeConfigId: 'a', activeSubscriptionId: 's');
      expect(st.copyWith(clearActive: true).activeConfigId, isNull);
      expect(st.copyWith(clearActiveSub: true).activeSubscriptionId, isNull);
      expect(st.copyWith().activeSubscriptionId, 's');
    });
  });

  group('effectiveConfigProvider', () {
    test('subscription mode picks the lowest latency, unknown last', () async {
      await boot(
        configs: [
          _cfg('a', subId: 's'),
          _cfg('b', subId: 's', latency: 300),
          _cfg('c', subId: 's', latency: 50),
          _cfg('d', latency: 1),
        ],
        activeId: 'd',
        activeSubId: 's',
      );
      expect(c.read(effectiveConfigProvider)?.id, 'c');
    });

    test('subscription without configs falls back to the selected config', () async {
      await boot(configs: [_cfg('d')], activeId: 'd', activeSubId: 'empty');
      expect(c.read(effectiveConfigProvider)?.id, 'd');
    });

    test('nothing selected', () async {
      await boot(
        configs: [_cfg('a', subId: 's')],
        activeSubId: 's',
      );
      expect(c.read(effectiveConfigProvider)?.id, 'a');
      await n().setActiveConfig(null);
      expect(c.read(effectiveConfigProvider), isNull);
    });
  });

  group('pins', () {
    test('toggle pins and unpins a config', () async {
      await boot(configs: [_cfg('1', subId: 's')]);
      final cfg = s().configs.single;
      await n().togglePin(cfg);
      expect(s().isPinned(cfg), isTrue);
      expect(await storage.loadPins(), [PinnedRef.of(cfg)]);
      await n().togglePin(cfg);
      expect(s().isPinned(cfg), isFalse);
      expect(await storage.loadPins(), isEmpty);
    });

    test('legacy name-only pin resolves and is removed by toggle', () async {
      const legacy = PinnedRef(subscriptionId: 's', name: 'n1');
      await boot(
        configs: [_cfg('1', subId: 's')],
        pins: [legacy],
      );
      final cfg = s().configs.single;
      expect(s().resolvedPins.single.$2?.id, '1');
      await n().togglePin(cfg);
      expect(s().pins, isEmpty);
    });

    test('lost pin stays until explicitly unpinned', () async {
      const lost = PinnedRef(subscriptionId: 's', name: 'gone', endpoint: 'x:1');
      await boot(configs: [_cfg('1')], pins: [lost]);
      expect(s().resolvedPins.single.$2, isNull);
      expect(s().pinnedIds, isEmpty);
      await n().unpin(lost);
      expect(s().pins, isEmpty);
      expect(await storage.loadPins(), isEmpty);
    });
  });

  group('importBundle', () {
    test('review lists hosts of new subscriptions, full and compact', () async {
      await boot(subs: [_sub('k', url: 'https://known.example/s')]);
      final review = n().reviewBundle(
        ConnectionsBundle(
          exportedAt: DateTime(2026),
          subscriptions: [
            _sub('a', url: 'https://known.example/s'),
            _sub('b', url: 'https://full.example/s'),
          ],
          subscriptionUrls: ['https://compact.example/s'],
        ),
      );
      expect(review.changes, isEmpty);
      expect(review.subscriptionHosts, ['full.example', 'compact.example']);
    });

    test('dedupes configs, remaps and reuses subscriptions, selects first', () async {
      await boot(
        configs: [
          _cfg('old', rawUri: 'trojan://dup'),
          _cfg('ep', address: 'same.host', port: 8443),
        ],
        subs: [_sub('existing', url: 'https://known')],
      );
      final bundle = ConnectionsBundle(
        exportedAt: DateTime(2026),
        configs: [
          _cfg('x1', rawUri: 'trojan://dup'),
          _cfg('x2', address: 'same.host', port: 8443),
          _cfg('x3', subId: 'remoteKnown'),
          _cfg('x4', subId: 'remoteNew'),
          _cfg('x5', subId: 'unmapped'),
        ],
        subscriptions: [
          _sub('remoteKnown', url: 'https://known'),
          _sub('remoteNew', url: 'https://new', pin: 'FOREIGN-CERT'),
        ],
      );
      final r = await n().importBundle(bundle);
      expect(r.addedConfigs, 3);
      expect(r.skippedConfigs, 2);
      expect(r.addedSubscriptions, 1);

      final newSub = s().subscriptions.firstWhere((x) => x.url == 'https://new');
      expect(newSub.id, isNot('remoteNew'));
      expect(newSub.pinnedCertDer, isNull, reason: 'a foreign certificate pin must not be imported');

      final imported = s().configs.skip(2).toList();
      expect(imported.map((c) => c.subscriptionId), ['existing', newSub.id, 'unmapped']);
      expect(imported.map((c) => c.id).toSet(), hasLength(3));
      expect(imported.every((c) => !['x3', 'x4', 'x5'].contains(c.id)), isTrue);
      expect(s().activeConfigId, imported.first.id);
      expect((await storage.loadConfigs()).length, 5);
      expect((await storage.loadSubscriptions()).length, 2);
    });

    test('keeps the current selection', () async {
      await boot(configs: [_cfg('1')], activeId: '1');
      await n().importBundle(ConnectionsBundle(exportedAt: DateTime(2026), configs: [_cfg('2')]));
      expect(s().activeConfigId, '1');
    });

    test('selects the first one when the selection resolves to nothing', () async {
      await boot(configs: [_cfg('1')], activeId: 'gone');
      await n().importBundle(ConnectionsBundle(exportedAt: DateTime(2026), configs: [_cfg('2')]));
      expect(s().activeConfig?.address, _cfg('2').address);
      expect(s().activeConfigId, isNot('gone'));
    });
  });

  test('batchUpdatePingResults sets and clears latency by endpoint', () async {
    await boot(
      configs: [
        _cfg('a', address: 'h', port: 1, latency: 10),
        _cfg('b', address: 'h', port: 1),
        _cfg('c', address: 'dead', port: 2, latency: 20),
        _cfg('d', address: 'other', port: 3, latency: 30),
      ],
    );
    final at = DateTime(2026, 7);
    await n().batchUpdatePingResults({'h:1': 77, 'dead:2': null}, at);
    final byId = {for (final c in s().configs) c.id: c};
    expect(byId['a']!.latencyMs, 77);
    expect(byId['b']!.latencyMs, 77);
    expect(byId['c']!.latencyMs, isNull);
    expect(byId['c']!.lastPingedAt, at);
    expect(byId['d']!.latencyMs, 30);
    expect(byId['d']!.lastPingedAt, isNull);
    expect((await storage.loadConfigs()).firstWhere((c) => c.id == 'c').latencyMs, isNull);
  });

  group('reorder', () {
    test('subscriptions', () async {
      await boot(subs: [_sub('a'), _sub('b'), _sub('c')]);
      await n().reorderSubscriptions(0, 2);
      expect(s().subscriptions.map((x) => x.id), ['b', 'c', 'a']);
      await n().reorderSubscriptions(2, 0);
      expect((await storage.loadSubscriptions()).map((x) => x.id), ['a', 'b', 'c']);
    });

    test('configs move inside their group', () async {
      await boot(
        configs: [
          _cfg('l1'),
          _cfg('s1', subId: 's'),
          _cfg('l2'),
          _cfg('s2', subId: 's'),
          _cfg('s3', subId: 's'),
        ],
      );
      // The group gathers into a contiguous block at the place of its first config.
      await n().reorderGroupConfigs('s', 2, 0);
      expect(s().configs.map((c) => c.id), ['l1', 's3', 's1', 's2', 'l2']);
      await n().reorderGroupConfigs(null, 0, 1);
      expect(s().configs.map((c) => c.id), ['l2', 'l1', 's3', 's1', 's2']);
      expect((await storage.loadConfigs()).map((c) => c.id), ['l2', 'l1', 's3', 's1', 's2']);
    });
  });

  group('subscription management', () {
    test('rename keeps the rest', () async {
      await boot(subs: [_sub('a', pin: 'CERT')]);
      await n().renameSubscription('a', 'Renamed');
      final sub = (await storage.loadSubscriptions()).single;
      expect(sub.name, 'Renamed');
      expect(sub.pinnedCertDer, 'CERT');
    });

    test('remove drops configs and clears selection that pointed into it', () async {
      await boot(
        configs: [
          _cfg('1', subId: 's'),
          _cfg('2'),
        ],
        subs: [_sub('s'), _sub('t')],
        activeId: '1',
        activeSubId: 's',
      );
      await n().removeSubscription('s');
      expect(s().configs.map((c) => c.id), ['2']);
      expect(s().subscriptions.map((x) => x.id), ['t']);
      expect(s().activeConfigId, isNull);
      expect(s().activeSubscriptionId, isNull);
      expect(await storage.loadActiveSubscriptionId(), isNull);
    });

    test('remove drops pins of the subscription', () async {
      final keep = PinnedRef.of(_cfg('2'));
      await boot(
        configs: [
          _cfg('1', subId: 's'),
          _cfg('2'),
        ],
        subs: [_sub('s')],
        pins: [
          PinnedRef.of(_cfg('1', subId: 's')),
          keep,
        ],
      );
      await n().removeSubscription('s');
      expect(s().pins, [keep]);
      expect(await storage.loadPins(), [keep]);
    });

    test('remove keeps an unrelated selection', () async {
      await boot(
        configs: [
          _cfg('1', subId: 's'),
          _cfg('2'),
        ],
        subs: [_sub('s')],
        activeId: '2',
      );
      await n().removeSubscription('s');
      expect(s().activeConfigId, '2');
    });
  });

  group('addSubscriptionFromUrl', () {
    late LocalServer server;
    setUp(() async => server = await LocalServer.start());
    tearDown(() => server.close());

    test('new subscription: configs tagged, title used, first selected', () async {
      await boot();
      server.serve(
        [_trojan('a.example', 'A'), _trojan('b.example', 'B')].join('\n'),
        headers: {'profile-title': 'Provider', 'subscription-userinfo': 'total=100'},
      );
      await n().addSubscriptionFromUrl(server.url('/sub'));
      final sub = s().subscriptions.single;
      expect(sub.name, 'Provider');
      expect(sub.url, server.url('/sub'));
      expect(sub.totalBytes, 100);
      expect(sub.lastFetchedAt, isNotNull);
      expect(s().configs.map((c) => c.subscriptionId).toSet(), {sub.id});
      expect(s().activeConfigId, s().configs.first.id);
      expect((await storage.loadConfigs()).length, 2);
      expect(server.requests.single.value('x-hwid'), isNull);
    });

    group('HWID', () {
      Future<void> bootWithHwid({List<Subscription> subs = const []}) async {
        await boot(
          subs: subs,
          prefs: {'hwid_enabled': true},
          secure: {'cached_device_id': 'android-id', 'cached_device_info': '{"model":"X1","osVersion":34}'},
        );
        expect((await c.read(settingsProvider.future)).hwidEnabled, isTrue);
      }

      String? sentId() => server.requests.last.value('x-hwid');
      final perHost = const HwidDeviceInfo(
        deviceId: 'android-id',
        deviceModel: 'X1',
        osVersion: 34,
      ).forHost('127.0.0.1').deviceId;

      test('a new subscription sends the id derived for its host', () async {
        await bootWithHwid();
        server.serve(_trojan('a.example', 'A'));
        await n().addSubscriptionFromUrl(server.url('/sub'));
        expect(sentId(), perHost);
        expect(s().subscriptions.single.rawHwid, isFalse);
        server.serve(_trojan('a.example', 'A'));
        await n().addSubscriptionFromUrl(server.url('/sub'));
        expect(sentId(), perHost, reason: 'stable across refreshes');
      });

      test('a subscription stored before per-host ids keeps sending the raw id', () async {
        final old = Subscription.fromJson((_sub('s', url: server.url('/sub')).toJson()..remove('rawHwid')));
        expect(old.rawHwid, isTrue);
        await bootWithHwid(subs: [old]);
        server.serve(_trojan('a.example', 'A'));
        await n().addSubscriptionFromUrl(server.url('/sub'));
        expect(sentId(), 'android-id');
        expect(s().subscriptions.single.rawHwid, isTrue);
        expect((await storage.loadSubscriptions()).single.rawHwid, isTrue);
      });

      Subscription legacy() => Subscription.fromJson(_sub('s', url: server.url('/sub')).toJson()..remove('rawHwid'));

      test('a URL change on the same host keeps the raw id', () async {
        await bootWithHwid(subs: [legacy()]);
        server.serve(_trojan('a.example', 'A'));
        await n().addSubscriptionFromUrl(server.url('/other'), replaceId: 's');
        expect(sentId(), 'android-id');
        expect((await storage.loadSubscriptions()).single.rawHwid, isTrue);
      });

      test('a URL change to another host switches to the per-host id for good', () async {
        await bootWithHwid(subs: [legacy()]);
        final otherHost = server.url('/sub').replaceFirst('127.0.0.1', 'localhost');
        final derived = const HwidDeviceInfo(
          deviceId: 'android-id',
          deviceModel: 'X1',
          osVersion: 34,
        ).forHost('localhost').deviceId;
        server.serve(_trojan('a.example', 'A'));
        await n().addSubscriptionFromUrl(otherHost, replaceId: 's');
        expect(sentId(), derived);
        expect((await storage.loadSubscriptions()).single.rawHwid, isFalse);

        // After a restart the refresh keeps the per-host id.
        c.dispose();
        c = ProviderContainer();
        addTearDown(c.dispose);
        await c.read(configProvider.future);
        await c.read(settingsProvider.future);
        await n().addSubscriptionFromUrl(otherHost);
        expect(sentId(), derived);
      });
    });

    test('an accepted certificate is pinned exactly; another one on the retry is refused', () async {
      await boot();
      final tls = await LocalServer.start(tls: LocalServer.selfSignedContext());
      addTearDown(tls.close);
      tls.serve(_trojan('a.example', 'A'));
      UntrustedCertificateException? presented;
      try {
        await n().addSubscriptionFromUrl(tls.url());
      } on UntrustedCertificateException catch (e) {
        presented = e;
      }
      expect(presented, isNotNull);
      expect(s().subscriptions, isEmpty);

      // The user accepted a certificate the server no longer presents: nothing is trusted.
      final other = base64.encode([...base64.decode(presented!.der)]..[0] ^= 1);
      await expectLater(
        n().addSubscriptionFromUrl(tls.url(), pinnedCertDer: other),
        throwsA(isA<UntrustedCertificateException>()),
      );
      expect(s().subscriptions, isEmpty);

      await n().addSubscriptionFromUrl(tls.url(), pinnedCertDer: presented.der);
      expect(s().subscriptions.single.pinnedCertDer, presented.der);
      // Later refreshes use the stored pin.
      await n().addSubscriptionFromUrl(tls.url());
      expect(s().subscriptions.single.pinnedCertDer, presented.der);
    });

    test('refresh keeps user name, latency and the selected server', () async {
      await boot(
        configs: [
          _cfg('o1', subId: 's', name: 'Same', address: 'a.example', latency: 11),
          _cfg('o2', subId: 's', name: 'Same', address: 'b.example', latency: 22),
          _cfg('local'),
        ],
        subs: [_sub('s', pin: 'CERT')],
        activeId: 'o2',
      );
      final url = server.url('/sub');
      await storage.saveSubscriptions([
        Subscription(id: 's', name: 'My name', url: url, createdAt: DateTime(2020), pinnedCertDer: 'CERT'),
      ]);
      c.invalidate(configProvider);
      await c.read(configProvider.future);

      server.serve(
        [_trojan('b.example', 'Same'), _trojan('a.example', 'Same'), _trojan('c.example', 'New')].join('\n'),
        headers: {'profile-title': 'Ignored'},
      );
      await n().addSubscriptionFromUrl(url);

      final sub = s().subscriptions.single;
      expect(sub.name, 'My name');
      expect(sub.createdAt, DateTime(2020));
      expect(sub.pinnedCertDer, 'CERT');
      final subConfigs = s().configs.where((c) => c.subscriptionId == 's').toList();
      expect(subConfigs, hasLength(3));
      expect(subConfigs.any((c) => c.id == 'o1' || c.id == 'o2'), isFalse);
      expect(
        {for (final c in subConfigs) c.address: c.latencyMs},
        {'b.example': 22, 'a.example': 11, 'c.example': null},
      );
      expect(s().activeConfig!.address, 'b.example');
      expect(await storage.loadActiveConfigId(), s().activeConfigId);
      expect(s().configs.where((c) => c.id == 'local'), hasLength(1));
      expect((await storage.loadConfigs()).length, 4);
    });

    test('refresh keeps a pinned core only on the matching profile', () async {
      final url = server.url('/sub');
      await boot(
        configs: [
          _cfg('o1', subId: 's', name: 'A', address: 'x.example').copyWith(core: CoreKind.singBox),
          _cfg('o2', subId: 's', name: 'B', address: 'x.example'),
          _cfg('o3', subId: 's', name: 'C', address: 'y.example').copyWith(core: CoreKind.xrayRust),
          _cfg('o4', subId: 's', name: 'D', address: 'z.example').copyWith(core: CoreKind.singBox),
          _cfg('o5', subId: 's', name: 'E', address: 'z.example'),
        ],
        subs: [_sub('s', url: url)],
      );
      server.serve(
        [
          _trojan('x.example', 'B'),
          _trojan('x.example', 'A'),
          _trojan('y.example', 'C renamed'),
          _trojan('z.example', 'F'),
        ].join('\n'),
      );
      await n().addSubscriptionFromUrl(url);
      expect(
        {for (final c in s().configs) c.name: c.core},
        {
          'B': null,
          'A': CoreKind.singBox,
          'C renamed': CoreKind.xrayRust, // a single endpoint — the core is carried over
          'F': null, // ambiguous endpoint, the name didn't match
        },
      );
    });

    test('refresh in subscription mode keeps the mode when the selected server is gone', () async {
      final url = server.url('/sub');
      await boot(
        configs: [_cfg('o1', subId: 's', address: 'gone.example')],
        subs: [_sub('s', url: url)],
        activeId: 'o1',
        activeSubId: 's',
      );
      server.serve(_trojan('a.example', 'A'));
      await n().addSubscriptionFromUrl(url);
      expect(s().activeSubscriptionId, 's');
      expect(await storage.loadActiveSubscriptionId(), 's');
      expect(s().activeConfig!.address, 'a.example');
    });

    test('explicit name wins; replaceId changes the URL in place', () async {
      await boot(subs: [_sub('s', url: 'https://old')]);
      server.serve(_trojan('a.example', 'A'));
      await n().addSubscriptionFromUrl(server.url('/new'), name: 'Named', replaceId: 's');
      final sub = s().subscriptions.single;
      expect(sub.id, 's');
      expect(sub.url, server.url('/new'));
      expect(sub.name, 'Named');
    });

    group('state changed during the download', () {
      late Completer<void> arrived;
      late Completer<void> release;

      /// The server answers [body] only after [release]; [arrived] completes when a request comes in.
      void hold(String body) {
        arrived = Completer<void>();
        release = Completer<void>();
        server.handler = (r) async {
          if (!arrived.isCompleted) arrived.complete();
          await release.future;
          r.response.write(body);
          await r.response.close();
        };
      }

      test('a refresh of a subscription removed meanwhile does not bring it back', () async {
        await boot(
          configs: [_cfg('1', subId: 's')],
          subs: [_sub('s', url: server.url('/sub'))],
        );
        hold(_trojan('a.example', 'A'));
        final refresh = n().addSubscriptionFromUrl(server.url('/sub'));
        await arrived.future;
        await n().removeSubscription('s');
        release.complete();
        await refresh;
        expect(s().subscriptions, isEmpty);
        expect(s().configs, isEmpty);
        expect(await storage.loadSubscriptions(), isEmpty);
        expect(await storage.loadConfigs(), isEmpty);
      });

      test('a replaceId update of a subscription removed meanwhile adds nothing', () async {
        await boot(subs: [_sub('s', url: 'https://old')]);
        hold(_trojan('a.example', 'A'));
        final update = n().addSubscriptionFromUrl(server.url('/new'), replaceId: 's');
        await arrived.future;
        await n().removeSubscription('s');
        release.complete();
        await update;
        expect(s().subscriptions, isEmpty);
        expect(s().configs, isEmpty);
      });

      test('a replaceId of a subscription removed before the call touches nothing', () async {
        await boot(
          configs: [_cfg('1', subId: 'other')],
          subs: [_sub('other', url: server.url('/sub'))],
        );
        server.serve(_trojan('a.example', 'A'));
        await n().addSubscriptionFromUrl(server.url('/sub'), replaceId: 'gone');
        expect(s().subscriptions.single.id, 'other');
        expect(s().configs.single.id, '1');
        expect(server.requests, isEmpty);
      });

      test('the same new URL added twice is one subscription', () async {
        await boot();
        hold(_trojan('a.example', 'A'));
        final first = n().addSubscriptionFromUrl(server.url('/sub'));
        await arrived.future;
        final second = n().addSubscriptionFromUrl(server.url('/sub'));
        release.complete();
        await Future.wait([first, second]);
        final sub = s().subscriptions.single;
        expect(s().configs.single.subscriptionId, sub.id);
        expect((await storage.loadSubscriptions()).single.id, sub.id);
        expect((await storage.loadConfigs()).single.subscriptionId, sub.id);
      });

      test('a new URL imported meanwhile keeps the imported id', () async {
        await boot();
        hold(_trojan('a.example', 'A'));
        final add = n().addSubscriptionFromUrl(server.url('/sub'));
        await arrived.future;
        await n().importBundle(
          ConnectionsBundle(
            exportedAt: DateTime(2026),
            subscriptions: [_sub('remote', url: server.url('/sub'))],
          ),
        );
        final imported = s().subscriptions.single.id;
        release.complete();
        await add;
        expect(s().subscriptions.single.id, imported);
        expect(s().configs.single.subscriptionId, imported);
      });
    });

    test('empty or failed fetch throws and leaves state untouched', () async {
      await boot(
        configs: [_cfg('1', subId: 's')],
        subs: [_sub('s', url: server.url())],
      );
      server.serve('nothing useful');
      await expectLater(n().addSubscriptionFromUrl(server.url()), throwsA(isA<Exception>()));
      server.serve('', status: 500);
      await expectLater(n().addSubscriptionFromUrl(server.url()), throwsA(isA<Exception>()));
      expect(s().configs.single.id, '1');
      expect((await storage.loadConfigs()).single.id, '1');
    });

    test('empty answer explains HWID limit or shows the announce', () async {
      await boot();
      server.serve('', headers: {'x-hwid-max-devices-reached': 'true'});
      await expectLater(n().addSubscriptionFromUrl(server.url()), throwsA(predicate((e) => '$e'.contains('HWID'))));
      server.serve('', headers: {'announce': 'base64:${base64Encode(utf8.encode('Please renew your subscription'))}'});
      await expectLater(
        n().addSubscriptionFromUrl(server.url()),
        throwsA(predicate((e) => '$e'.contains('Please renew your subscription'))),
      );
    });

    test('refreshStaleSubscriptions refreshes only stale ones and backs off on failure', () async {
      final now = DateTime.now();
      await boot(
        subs: [
          _sub('fresh', url: server.url('/fresh'), fetched: now),
          _sub('stale', url: server.url('/stale'), fetched: now.subtract(const Duration(hours: 7))),
          _sub('never', url: server.url('/never')),
        ],
      );
      server.handler = (r) async {
        if (r.uri.path == '/never') {
          r.response.statusCode = 500;
        } else {
          r.response.write(_trojan('x.example', 'X'));
        }
        await r.response.close();
      };
      await n().refreshStaleSubscriptions(intervalHours: 6);
      expect(server.paths, ['/stale', '/never']);
      expect(c.read(logServiceProvider).single.level, LogLevel.error);
      expect(s().configs.where((c) => c.subscriptionId == 'stale'), hasLength(1));

      await n().refreshStaleSubscriptions(intervalHours: 6);
      expect(server.paths, ['/stale', '/never'], reason: 'fresh after refresh, failed one waits an hour');
    });
  });
}
