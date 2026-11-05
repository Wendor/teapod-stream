import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teapodstream/core/models/connections_bundle.dart';
import 'package:teapodstream/core/models/pinned_ref.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/models/vpn_log_entry.dart';
import 'package:teapodstream/core/services/config_storage_service.dart';
import 'package:teapodstream/core/services/log_service.dart';
import 'package:teapodstream/providers/config_provider.dart';

import '../helpers/local_server.dart';

VpnConfig _cfg(String id,
        {String? subId, String? name, String address = '', int port = 443, int? latency, String? rawUri}) =>
    VpnConfig(
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
    id: id, name: 'S$id', url: url ?? 'https://$id', createdAt: DateTime(2026),
    lastFetchedAt: fetched, pinnedCertDer: pin);

String _trojan(String host, String name, {int port = 443}) =>
    'trojan://pw@$host:$port?security=tls#${Uri.encodeComponent(name)}';

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
  }) async {
    SharedPreferences.setMockInitialValues({'storage_migrated_v2': true});
    FlutterSecureStorage.setMockInitialValues({});
    await storage.saveConfigs(configs);
    await storage.saveSubscriptions(subs);
    await storage.savePins(pins);
    await storage.saveActiveConfigId(activeId);
    await storage.saveActiveSubscriptionId(activeSubId);
    c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(configProvider.future);
  }

  test('build loads persisted state', () async {
    await boot(configs: [_cfg('1')], subs: [_sub('s')], activeId: '1', activeSubId: 's',
        pins: [const PinnedRef(subscriptionId: null, name: 'n1')]);
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
      final st = ConfigState(configs: [_cfg('a'), _cfg('b', subId: 's'), _cfg('c', subId: 's')]);
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
      await boot(configs: [
        _cfg('a', subId: 's'),
        _cfg('b', subId: 's', latency: 300),
        _cfg('c', subId: 's', latency: 50),
        _cfg('d', latency: 1),
      ], activeId: 'd', activeSubId: 's');
      expect(c.read(effectiveConfigProvider)?.id, 'c');
    });

    test('subscription without configs falls back to the selected config', () async {
      await boot(configs: [_cfg('d')], activeId: 'd', activeSubId: 'empty');
      expect(c.read(effectiveConfigProvider)?.id, 'd');
    });

    test('nothing selected', () async {
      await boot(configs: [_cfg('a', subId: 's')], activeSubId: 's');
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
      await boot(configs: [_cfg('1', subId: 's')], pins: [legacy]);
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
    test('dedupes configs, remaps and reuses subscriptions, selects first', () async {
      await boot(
        configs: [_cfg('old', rawUri: 'trojan://dup'), _cfg('ep', address: 'same.host', port: 8443)],
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
  });

  test('batchUpdatePingResults sets and clears latency by endpoint', () async {
    await boot(configs: [
      _cfg('a', address: 'h', port: 1, latency: 10),
      _cfg('b', address: 'h', port: 1),
      _cfg('c', address: 'dead', port: 2, latency: 20),
      _cfg('d', address: 'other', port: 3, latency: 30),
    ]);
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
      await n().reorderSubscriptions(0, 3);
      expect(s().subscriptions.map((x) => x.id), ['b', 'c', 'a']);
      await n().reorderSubscriptions(2, 0);
      expect((await storage.loadSubscriptions()).map((x) => x.id), ['a', 'b', 'c']);
    });

    test('configs move inside their group', () async {
      await boot(configs: [
        _cfg('l1'),
        _cfg('s1', subId: 's'),
        _cfg('l2'),
        _cfg('s2', subId: 's'),
        _cfg('s3', subId: 's'),
      ]);
      // Группа собирается в непрерывный блок на месте своего первого конфига.
      await n().reorderGroupConfigs('s', 2, 0);
      expect(s().configs.map((c) => c.id), ['l1', 's3', 's1', 's2', 'l2']);
      await n().reorderGroupConfigs(null, 0, 2);
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
        configs: [_cfg('1', subId: 's'), _cfg('2')],
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

    test('remove keeps an unrelated selection', () async {
      await boot(configs: [_cfg('1', subId: 's'), _cfg('2')], subs: [_sub('s')], activeId: '2');
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
      server.serve([_trojan('a.example', 'A'), _trojan('b.example', 'B')].join('\n'),
          headers: {'profile-title': 'Provider', 'subscription-userinfo': 'total=100'});
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
        Subscription(id: 's', name: 'My name', url: url, createdAt: DateTime(2020), pinnedCertDer: 'CERT')
      ]);
      c.invalidate(configProvider);
      await c.read(configProvider.future);

      server.serve([_trojan('b.example', 'Same'), _trojan('a.example', 'Same'), _trojan('c.example', 'New')]
          .join('\n'), headers: {'profile-title': 'Ignored'});
      await n().addSubscriptionFromUrl(url);

      final sub = s().subscriptions.single;
      expect(sub.name, 'My name');
      expect(sub.createdAt, DateTime(2020));
      expect(sub.pinnedCertDer, 'CERT');
      final subConfigs = s().configs.where((c) => c.subscriptionId == 's').toList();
      expect(subConfigs, hasLength(3));
      expect(subConfigs.any((c) => c.id == 'o1' || c.id == 'o2'), isFalse);
      expect({for (final c in subConfigs) c.address: c.latencyMs},
          {'b.example': 22, 'a.example': 11, 'c.example': null});
      expect(s().activeConfig!.address, 'b.example');
      expect(await storage.loadActiveConfigId(), s().activeConfigId);
      expect(s().configs.where((c) => c.id == 'local'), hasLength(1));
      expect((await storage.loadConfigs()).length, 4);
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

    test('empty or failed fetch throws and leaves state untouched', () async {
      await boot(configs: [_cfg('1', subId: 's')], subs: [_sub('s', url: server.url())]);
      server.serve('nothing useful');
      await expectLater(n().addSubscriptionFromUrl(server.url()), throwsA(isA<Exception>()));
      server.serve('', status: 500);
      await expectLater(n().addSubscriptionFromUrl(server.url()), throwsA(isA<Exception>()));
      expect(s().configs.single.id, '1');
      expect((await storage.loadConfigs()).single.id, '1');
    });

    test('refreshStaleSubscriptions refreshes only stale ones and backs off on failure', () async {
      final now = DateTime.now();
      await boot(subs: [
        _sub('fresh', url: server.url('/fresh'), fetched: now),
        _sub('stale', url: server.url('/stale'), fetched: now.subtract(const Duration(hours: 7))),
        _sub('never', url: server.url('/never')),
      ]);
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
      expect(server.paths, ['/stale', '/never'],
          reason: 'fresh after refresh, failed one waits an hour');
    });
  });
}
