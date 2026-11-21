import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teapodstream/core/constants/app_constants.dart';
import 'package:teapodstream/core/cores/core_backend.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/config_selection.dart';
import 'package:teapodstream/core/models/connection_fingerprint.dart';
import 'package:teapodstream/core/models/core_kind.dart';
import 'package:teapodstream/core/models/heartbeat_settings.dart';
import 'package:teapodstream/core/models/pinned_ref.dart';
import 'package:teapodstream/core/services/profile_storage_service.dart';
import 'package:teapodstream/core/models/profile.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/models/vpn_log_entry.dart';
import 'package:teapodstream/core/services/config_storage_service.dart';
import 'package:teapodstream/core/services/log_service.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/core/models/app_settings.dart';
import 'package:teapodstream/protocols/xray/xray_rust_backend.dart';
import 'package:teapodstream/providers/config_provider.dart';
import 'package:teapodstream/providers/profile_provider.dart';
import 'package:teapodstream/providers/settings_provider.dart';
import 'package:teapodstream/providers/vpn_provider.dart';

const _method = MethodChannel(AppConstants.methodChannel);
const _events = EventChannel('${AppConstants.methodChannel}/events');
const _permissions = MethodChannel('flutter.baseflow.com/permissions/methods');

const _settings = AppSettings(
  randomPort: false,
  socksPort: 2080,
  randomCredentials: false,
  socksUser: 'su',
  socksPassword: 'sp',
);

const _visionRaw =
    '{"outbounds":[{"tag":"proxy","protocol":"vless","settings":{"vnext":[{"address":'
    '"r.example","port":443,"users":[{"id":"11111111-2222-4333-8444-555555555555",'
    '"encryption":"none","flow":"xtls-rprx-vision"}]}]}}]}';

VpnConfig _cfg(String id, {String? subId, String password = 'p', DateTime? pingedAt, String? rawXray, String? host}) =>
    VpnConfig(
      id: id,
      name: 'n$id',
      protocol: VpnProtocol.trojan,
      address: host ?? 'h$id.example',
      port: 443,
      uuid: '',
      password: password,
      security: VpnSecurity.tls,
      transport: VpnTransport.tcp,
      createdAt: DateTime(2026),
      subscriptionId: subId,
      lastPingedAt: pingedAt,
      rawXrayConfig: rawXray,
    );

VpnConfig _vision(String id) => VpnConfig(
  id: id,
  name: id,
  protocol: VpnProtocol.vless,
  address: 'v.example',
  port: 443,
  uuid: '11111111-2222-4333-8444-555555555555',
  security: VpnSecurity.tls,
  transport: VpnTransport.tcp,
  flow: 'xtls-rprx-vision',
  createdAt: DateTime(2026),
);

/// Native side state and a call log.
class _Native {
  final calls = <MethodCall>[];
  Map<String, Object?> state = {'state': 'disconnected'};
  List<String> logs = [];

  /// host → latency via `measureOutbound`; null — the server is dead.
  Map<String, int?> outboundMs = {};

  /// host → TCP ping latency.
  Map<String, int?> pingMs = {};
  Object? Function()? onConnect;
  Object? Function()? onDisconnect;
  MockStreamHandlerEventSink? sink;

  List<MethodCall> named(String m) => calls.where((c) => c.method == m).toList();
  Map<Object?, Object?> lastConnect() => named('connect').last.arguments as Map;

  Object? handle(MethodCall call) {
    calls.add(call);
    switch (call.method) {
      case 'getState':
        return state;
      case 'getAvailableEngines':
        return ['go', 'rust', 'box'];
      case 'getLogs':
        return logs;
      case 'connect':
        return onConnect?.call();
      case 'disconnect':
        return onDisconnect?.call();
      case 'ping':
        return pingMs[(call.arguments as Map)['address']];
      case 'measureOutbound':
        final cfg = (call.arguments as Map)['config'] as String;
        return outboundMs.entries.where((e) => cfg.contains(e.key)).firstOrNull?.value;
      case 'getStats':
        return {'upload': 10, 'download': 20, 'uploadSpeed': 1, 'downloadSpeed': 2};
    }
    return null;
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _Native native;
  late ProviderContainer c;

  VpnNotifier n() => c.read(vpnProvider.notifier);
  VpnState2 st() => c.read(vpnProvider);
  List<VpnLogEntry> logs() => c.read(logServiceProvider);
  void emit(Map<String, Object?> event) => native.sink!.success(event);

  setUp(() {
    native = _Native();
    messenger.setMockMethodCallHandler(_method, (call) async => native.handle(call));
    messenger.setMockMethodCallHandler(_permissions, (call) async => <int, int>{17: 1});
    messenger.setMockStreamHandler(_events, MockStreamHandler.inline(onListen: (_, sink) => native.sink = sink));
  });

  /// No await: inside fakeAsync it completes via flushMicrotasks.
  Future<void> boot({
    List<VpnConfig> configs = const [],
    String? activeId,
    List<PinnedRef> pins = const [],
    AppSettings settings = _settings,
    List<Override> overrides = const [],
  }) async {
    SharedPreferences.setMockInitialValues({'storage_migrated_v2': true});
    FlutterSecureStorage.setMockInitialValues({});
    await SettingsService().save(settings);
    final storage = ConfigStorageService();
    await storage.saveConfigs(configs);
    await storage.saveActiveConfigId(activeId);
    await storage.savePins(pins);
    final container = c = ProviderContainer(overrides: overrides);
    // Unfinished fire-and-forget operations (syncActiveSettings) must not
    // outlive the container.
    addTearDown(() async {
      await _settle();
      container.dispose();
    });
    await c.read(configProvider.future);
    await c.read(settingsProvider.future);
    c.listen(vpnProvider, (_, _) {});
    await _settle();
  }

  /// Native confirms every connect, like the real service does after the hot switch.
  void confirmConnects([Future<void>? gate]) => native.onConnect = () async {
    await gate;
    Future.microtask(
      () => emit({'type': 'state', 'value': 'connected', 'socksPort': 2080, 'socksUser': 'su', 'socksPassword': 'sp'}),
    );
    return null;
  };

  Future<void> connected({
    List<VpnConfig>? configs,
    AppSettings settings = _settings,
    List<Override> overrides = const [],
  }) async {
    await boot(
      configs: configs ?? [_cfg('a')],
      activeId: (configs ?? [_cfg('a')]).first.id,
      settings: settings,
      overrides: overrides,
    );
    await n().connect();
    emit({'type': 'state', 'value': 'connected', 'socksPort': 2080, 'socksUser': 'su', 'socksPassword': 'sp'});
    await _settle();
    expect(st().isConnected, isTrue);
  }

  group('startup', () {
    test('restores logs and adopts an already running tunnel', () async {
      native.state = {
        'state': 'connected',
        'socksPort': 5555,
        'socksUser': 'nu',
        'socksPassword': 'np',
        'connectedAtMs': DateTime.now().millisecondsSinceEpoch - 60000,
      };
      native.logs = ['1700000000000|warning|from last session'];
      await boot();
      expect(st().isConnected, isTrue);
      expect((st().activeSocksPort, st().activeSocksUser, st().activeSocksPassword), (5555, 'nu', 'np'));
      expect(st().appliedFingerprint, connectionFingerprint(_settings));
      expect(logs().single.message, 'from last session');
      expect(native.named('setLogsEnabled').single.arguments, {'enabled': true});
    });

    test('stays disconnected when native is idle', () async {
      await boot();
      expect(st().connectionState, VpnState.disconnected);
      expect(st().appliedFingerprint, isNull);
    });
  });

  group('connect', () {
    test('without a config fails before native', () async {
      await boot();
      await n().connect();
      expect(st().connectionState, VpnState.error);
      expect(st().error, 'No configuration selected');
      expect(logs().last.level, LogLevel.error);
      expect(native.named('connect'), isEmpty);
    });

    test('invalid config fails validation', () async {
      await boot(
        configs: [_cfg('a', password: '')],
        activeId: 'a',
      );
      await n().connect();
      expect(st().error, 'Empty password');
      expect(native.named('connect'), isEmpty);
    });

    test('sends settings and follows native events', () async {
      await boot(configs: [_cfg('a')], activeId: 'a');
      await n().connect();
      expect(st().connectionState, VpnState.connecting);
      expect(st().activeSocksPort, 2080);
      expect(st().appliedFingerprint, connectionFingerprint(_settings, core: CoreKind.xrayGo));
      final args = native.lastConnect();
      expect(args['engine'], 'go');
      expect(args['socksPort'], 2080);
      expect(args['socksUser'], 'su');
      expect(args['socksPassword'], 'sp');
      expect(args['blockQuic'], isFalse);
      expect(args['xrayConfig'], contains('ha.example'));

      emit({'type': 'state', 'value': 'connected', 'socksPort': 2080, 'socksUser': 'su', 'socksPassword': 'sp'});
      await _settle();
      expect(st().isConnected, isTrue);
      expect(st().error, isNull);
      expect(c.read(vpnConnectionStateProvider), VpnState.connected);
    });

    test('empty manual credentials are replaced in TUN mode only', () async {
      const manual = AppSettings(randomCredentials: false, socksUser: '', socksPassword: '');
      await boot(configs: [_cfg('a')], activeId: 'a', settings: manual);
      await n().connect();
      final args = native.lastConnect();
      expect(args['socksUser'], matches(RegExp(r'^u\w{8}$')));
      expect((args['socksPassword'] as String).length, AppConstants.socksAuthPasswordLength);

      await boot(configs: [_cfg('a')], activeId: 'a', settings: manual.copyWith(proxyOnly: true));
      await n().connect();
      expect(native.lastConnect()['socksUser'], '');
      expect(native.lastConnect()['proxyOnly'], isTrue);
    });

    test('random port and credentials', () async {
      await boot(configs: [_cfg('a')], activeId: 'a', settings: const AppSettings());
      await n().connect();
      final args = native.lastConnect();
      expect(args['socksPort'] as int, inInclusiveRange(10000, 59999));
      expect(args['socksUser'], isNot('su'));
    });

    test('split tunnelling options follow the mode', () async {
      final split = _settings.copyWith(
        splitTunnelingEnabled: true,
        vpnMode: VpnMode.allExcept,
        excludedPackages: {'ex'},
        includedPackages: {'in'},
      );
      await boot(configs: [_cfg('a')], activeId: 'a', settings: split);
      await n().connect();
      List<Object?> split3(Map<Object?, Object?> a) => [a['vpnMode'], a['excludedPackages'], a['includedPackages']];
      expect(split3(native.lastConnect()), [
        'allExcept',
        ['ex'],
        <String>[],
      ]);

      await boot(
        configs: [_cfg('a')],
        activeId: 'a',
        settings: split.copyWith(vpnMode: VpnMode.onlySelected),
      );
      await n().connect();
      expect(split3(native.lastConnect()), [
        'onlySelected',
        <String>[],
        ['in'],
      ]);

      await boot(configs: [_cfg('a')], activeId: 'a', settings: split.copyWith(splitTunnelingEnabled: false));
      await n().connect();
      expect(split3(native.lastConnect()), ['allExcept', <String>[], <String>[]]);
    });

    test('vision flow forces QUIC blocking, also inside raw configs', () async {
      await boot(configs: [_vision('v')], activeId: 'v');
      await n().connect();
      expect(native.lastConnect()['blockQuic'], isTrue);

      await boot(
        configs: [_cfg('r', rawXray: _visionRaw)],
        activeId: 'r',
      );
      await n().connect();
      expect(native.lastConnect()['blockQuic'], isTrue);
    });

    test('native rejection becomes an error', () async {
      native.onConnect = () => throw PlatformException(code: 'X', message: 'denied');
      await boot(configs: [_cfg('a')], activeId: 'a');
      await n().connect();
      expect(st().connectionState, VpnState.error);
      expect(st().error, 'denied');
    });

    test('the first core by priority that can run the profile is used', () async {
      await boot(
        configs: [_cfg('a')],
        activeId: 'a',
        settings: _settings.copyWith(coreOrder: [CoreKind.xrayRust, CoreKind.xrayGo, CoreKind.singBox]),
      );
      await n().connect();
      expect(native.lastConnect()['engine'], 'rust');

      // Rust can't do proxy-only — the profile goes to the next core.
      await boot(
        configs: [_cfg('a')],
        activeId: 'a',
        settings: _settings.copyWith(
          coreOrder: [CoreKind.xrayRust, CoreKind.xrayGo, CoreKind.singBox],
          proxyOnly: true,
        ),
      );
      await n().connect();
      expect(native.lastConnect()['engine'], 'go');

      await boot(
        configs: [_cfg('r', rawXray: _visionRaw)],
        activeId: 'r',
        settings: _settings.copyWith(coreOrder: [CoreKind.xrayRust, CoreKind.xrayGo, CoreKind.singBox]),
      );
      native.calls.clear();
      await n().connect();
      expect(native.lastConnect()['engine'], 'go');
    });

    test('a profile pinned to a core runs on it', () async {
      await boot(
        configs: [_cfg('a').copyWith(core: CoreKind.singBox)],
        activeId: 'a',
      );
      await n().connect();
      expect(native.lastConnect()['engine'], 'box');
    });

    test('no enabled core can run the profile — refused before native', () async {
      await boot(
        configs: [_cfg('a')],
        activeId: 'a',
        settings: _settings.copyWith(proxyOnly: true, disabledCores: {CoreKind.xrayGo, CoreKind.singBox}),
      );
      await n().connect();
      expect(st().error, const XrayRustBackend().unavailableReason(CoreFeature.proxyOnly));
      expect(native.named('connect'), isEmpty);
    });

    test('is ignored while connected or busy', () async {
      await connected();
      await n().connect();
      expect(native.named('connect'), hasLength(1));
    });
  });

  group('switching on a live tunnel', () {
    test('valid config reconnects natively without disconnect', () async {
      await connected(configs: [_cfg('a'), _cfg('b')]);
      await c.read(configProvider.notifier).setActiveConfig('b');
      await n().reconnectWithNewConfig();
      expect(native.named('connect'), hasLength(2));
      expect(native.named('disconnect'), isEmpty);
      expect(native.lastConnect()['xrayConfig'], contains('hb.example'));
    });

    test('invalid config keeps the old session', () async {
      await connected(
        configs: [
          _cfg('a'),
          _cfg('bad', password: ''),
        ],
      );
      await c.read(configProvider.notifier).setActiveConfig('bad');
      await n().reconnectWithNewConfig();
      expect(st().isConnected, isTrue);
      expect(st().error, 'Empty password');
      expect(native.named('connect'), hasLength(1));
    });

    test('profile switch reconnects only when the server or settings change', () async {
      await connected(configs: [_cfg('a'), _cfg('b')]);
      final profiles = c.read(profileProvider.notifier);
      await c.read(profileProvider.future);
      await profiles.createProfile('B');
      final defaultId = c.read(profileProvider).value!.activeProfileId;
      final bId = c.read(profileProvider).value!.profiles.last.id;

      // same server, same settings — the tunnel stays
      await profiles.switchProfile(bId);
      await c.read(configProvider.notifier).setActiveConfig('b');
      await profiles.switchProfile(defaultId);
      await _settle();
      expect(native.named('connect'), hasLength(1));

      // B remembered server b
      await profiles.switchProfile(bId);
      await _settle();
      expect(native.named('connect'), hasLength(2));
      expect(native.lastConnect()['xrayConfig'], contains('hb.example'));
    });

    test('a failed server restore still reconnects to the profile settings', () async {
      await connected(overrides: [configProvider.overrideWith(_FailingSelection.new)]);
      final profiles = c.read(profileProvider.notifier);
      await c.read(profileProvider.future);
      await profiles.createProfile('B');
      final defaultId = c.read(profileProvider).value!.activeProfileId;
      final bId = c.read(profileProvider).value!.profiles.last.id;
      await profiles.switchProfile(bId); // B remembers the current server
      await c.read(settingsProvider.notifier).save(_settings.copyWith(mtu: 1400));
      await profiles.switchProfile(defaultId);
      await _settle();
      final before = native.named('connect').length;

      _FailingSelection.fail = true;
      addTearDown(() => _FailingSelection.fail = false);
      await expectLater(profiles.switchProfile(bId), throwsA(isA<StateError>()));
      await _settle();
      expect(native.named('connect'), hasLength(before + 1));
      expect(native.lastConnect()['mtu'], 1400);
    });

    test('switching between a sing-box profile and a raw-xray one keeps the tunnel up', () async {
      final boxOnly = _settings.copyWith(disabledCores: {CoreKind.xrayGo, CoreKind.xrayRust});
      await connected(
        configs: [
          _cfg('a'),
          _cfg('r', rawXray: _visionRaw),
        ],
        settings: boxOnly,
        overrides: [configProvider.overrideWith(_SlowSelection.new)],
      );
      final profiles = c.read(profileProvider.notifier);
      await c.read(profileProvider.future);
      await profiles.createProfile('B');
      final boxId = c.read(profileProvider).value!.activeProfileId;
      final bId = c.read(profileProvider).value!.profiles.last.id;
      // B: Go enabled, raw xray server
      await profiles.switchProfile(bId);
      await c.read(settingsProvider.notifier).save(_settings);
      await c.read(configProvider.notifier).setActiveConfig('r');
      await _settle();

      // in between, sing-box settings with the raw config (or the reverse) can't run
      await profiles.switchProfile(boxId);
      await _settle();
      expect(native.lastConnect()['engine'], 'box');
      await profiles.switchProfile(bId);
      await _settle();
      expect(native.named('disconnect'), isEmpty);
      expect(st().error, isNull);
      expect(native.lastConnect()['engine'], 'go');
      expect(native.lastConnect()['xrayConfig'], contains('r.example'));
    });

    test('overlapping profile switches end on the last profile, tunnel up', () async {
      final r2 = _cfg('r2', rawXray: _visionRaw.replaceAll('r.example', 'r2.example'));
      await connected(
        configs: [
          _cfg('r', rawXray: _visionRaw),
          r2,
          _cfg('a'),
        ],
        overrides: [configProvider.overrideWith(_SlowSelection.new)],
      );
      ConfigSelection sel(VpnConfig cfg) => ConfigSelection(configId: cfg.id, config: PinnedRef.of(cfg));
      final boxOnly = _settings.copyWith(disabledCores: {CoreKind.xrayGo, CoreKind.xrayRust});
      await ProfileStorageService().saveProfiles([
        Profile(id: 'X', name: 'X', settings: _settings, createdAt: DateTime(2026)),
        Profile(id: 'W', name: 'W', settings: _settings, createdAt: DateTime(2026), selection: sel(r2)),
        // Y's sing-box settings can't run W's raw server: the second switch passes an unsupported pair
        Profile(id: 'Y', name: 'Y', settings: boxOnly, createdAt: DateTime(2026), selection: sel(_cfg('a'))),
      ]);
      await ProfileStorageService().saveActiveProfileId('X');
      final profiles = c.read(profileProvider.notifier);
      await c.read(profileProvider.future);
      confirmConnects();

      await Future.wait([profiles.switchProfile('W'), profiles.switchProfile('Y')]);
      await _settle();
      expect(native.named('disconnect'), isEmpty);
      expect(st().error, isNull);
      expect(native.lastConnect()['engine'], 'box');
      expect(native.lastConnect()['xrayConfig'], contains('ha.example'));
    });

    test('switching to a profile no core runs disconnects like a core change', () async {
      await connected(
        configs: [
          _cfg('a'),
          _cfg('r', rawXray: _visionRaw),
        ],
        overrides: [configProvider.overrideWith(_SlowSelection.new)],
      );
      // B: the raw xray server, but only sing-box allowed — no core runs it
      await ProfileStorageService().saveProfiles([
        Profile(id: 'A', name: 'A', settings: _settings, createdAt: DateTime(2026)),
        Profile(
          id: 'B',
          name: 'B',
          settings: _settings.copyWith(disabledCores: {CoreKind.xrayGo, CoreKind.xrayRust}),
          createdAt: DateTime(2026),
          selection: ConfigSelection(
            configId: 'r',
            config: PinnedRef.of(_cfg('r', rawXray: _visionRaw)),
          ),
        ),
      ]);
      await ProfileStorageService().saveActiveProfileId('A');
      await c.read(profileProvider.future);

      await c.read(profileProvider.notifier).switchProfile('B');
      await _settle();
      expect(native.named('disconnect'), hasLength(1));
      expect(st().error, isNotNull);
    });

    test('a later switch waits for the earlier one\'s connect', () async {
      final r2 = _cfg('r2', rawXray: _visionRaw.replaceAll('r.example', 'r2.example'));
      await connected(
        configs: [
          _cfg('r', rawXray: _visionRaw),
          r2,
          _cfg('a'),
        ],
      );
      ConfigSelection sel(VpnConfig cfg) => ConfigSelection(configId: cfg.id, config: PinnedRef.of(cfg));
      await ProfileStorageService().saveProfiles([
        Profile(id: 'X', name: 'X', settings: _settings, createdAt: DateTime(2026)),
        Profile(id: 'W', name: 'W', settings: _settings, createdAt: DateTime(2026), selection: sel(r2)),
        Profile(id: 'Y', name: 'Y', settings: _settings, createdAt: DateTime(2026), selection: sel(_cfg('a'))),
      ]);
      await ProfileStorageService().saveActiveProfileId('X');
      final profiles = c.read(profileProvider.notifier);
      await c.read(profileProvider.future);
      final before = native.named('connect').length;
      final gate = Completer<void>();
      confirmConnects(gate.future);

      final switches = Future.wait([profiles.switchProfile('W'), profiles.switchProfile('Y')]);
      await _settle();
      expect(native.named('connect'), hasLength(before + 1)); // W's connect is still in flight
      gate.complete();
      await switches;
      await _settle();
      expect(native.named('connect'), hasLength(before + 2));
      expect(native.lastConnect()['xrayConfig'], contains('ha.example'));
      expect(n().runsConfig(_cfg('a')), isTrue);
    });

    test('a core change during a no-op switch is still handled', () async {
      await connected(configs: [_cfg('r', rawXray: _visionRaw)]);
      await c.read(profileProvider.future);
      // nothing runs the raw config any more while a (no-op) switch is in flight
      await n().duringProfileSwitch(() async {
        await c
            .read(settingsProvider.notifier)
            .save(_settings.copyWith(disabledCores: {CoreKind.xrayGo, CoreKind.singBox}));
        await _settle();
        return false;
      });
      await _settle();
      expect(native.named('disconnect'), hasLength(1));
      expect(st().error, isNotNull);
    });

    test('reconnectIfStale rebuilds on changed settings, ignores an idle tunnel', () async {
      await connected();
      await n().reconnectIfStale();
      expect(native.named('connect'), hasLength(1));
      await c.read(settingsProvider.notifier).save(_settings.copyWith(mtu: 1400));
      await n().reconnectIfStale();
      expect(native.named('connect'), hasLength(2));
    });

    test('pending reconnect appears after a connection setting changes', () async {
      await connected();
      expect(c.read(pendingReconnectProvider), isFalse);
      await c.read(settingsProvider.notifier).save(_settings.copyWith(fontScale: FontScale.large));
      expect(c.read(pendingReconnectProvider), isFalse);
      await c.read(settingsProvider.notifier).save(_settings.copyWith(mtu: 1400));
      expect(c.read(pendingReconnectProvider), isTrue);
    });
  });

  group('superseded connect attempts', () {
    /// The first native connect waits for [gate] and then answers with [first]; later ones answer at once.
    void holdFirstConnect(Completer<void> gate, Object? Function() first) {
      var n = 0;
      native.onConnect = () async {
        if (n++ > 0) return null;
        await gate.future;
        return first();
      };
    }

    Future<void> disconnectNow() async {
      final d = n().disconnect();
      emit({'type': 'state', 'value': 'disconnected'});
      await d;
      await _settle();
    }

    test('an earlier connect finishing after a newer one changes nothing', () async {
      await boot(configs: [_cfg('a'), _cfg('b')], activeId: 'a');
      final gate = Completer<void>();
      holdFirstConnect(gate, () => null);
      final first = n().connect();
      await _settle();
      expect(native.named('connect'), hasLength(1));

      await disconnectNow();
      await c.read(configProvider.notifier).setActiveConfig('b');
      await n().connect();
      emit({'type': 'state', 'value': 'connected', 'socksPort': 2080, 'socksUser': 'su', 'socksPassword': 'sp'});
      await _settle();
      expect(n().runsConfig(_cfg('b')), isTrue);

      gate.complete();
      await first;
      await _settle();
      expect(n().runsConfig(_cfg('b')), isTrue);
      expect(n().runsConfig(_cfg('a')), isFalse);
      expect(st().isConnected, isTrue);
    });

    test("a superseded attempt's failure doesn't set an error", () async {
      await boot(configs: [_cfg('a')], activeId: 'a');
      final gate = Completer<void>();
      holdFirstConnect(gate, () => throw PlatformException(code: 'X', message: 'late failure'));
      final first = n().connect();
      await _settle();

      await disconnectNow();
      await n().connect();
      emit({'type': 'state', 'value': 'connected', 'socksPort': 2080, 'socksUser': 'su', 'socksPassword': 'sp'});
      await _settle();

      gate.complete();
      await first;
      await _settle();
      expect(st().connectionState, VpnState.connected);
      expect(st().error, isNull);
      expect(logs().where((l) => l.message.contains('late failure')), isEmpty);
    });

    test('disconnect while a connect waits before native: the connect is never dispatched', () async {
      await boot(configs: [_cfg('a')], activeId: 'a');
      final permission = Completer<Map<int, int>>();
      messenger.setMockMethodCallHandler(_permissions, (call) => permission.future);
      final first = n().connect();
      await _settle();
      expect(st().connectionState, VpnState.connecting);

      await disconnectNow();
      permission.complete({17: 1});
      await first;
      await _settle();
      expect(native.named('connect'), isEmpty);
      expect(st().connectionState, VpnState.disconnected);
    });

    test('disconnect after native reported disconnected still drops the waiting connect', () async {
      await boot(configs: [_cfg('a')], activeId: 'a');
      final permission = Completer<Map<int, int>>();
      messenger.setMockMethodCallHandler(_permissions, (call) => permission.future);
      final first = n().connect();
      await _settle();
      emit({'type': 'state', 'value': 'disconnected'});
      await _settle();
      expect(st().connectionState, VpnState.disconnected);

      await n().disconnect(); // idle: no native call, but the waiting connect is dropped
      permission.complete({17: 1});
      await first;
      await _settle();
      expect(native.named('connect'), isEmpty);
      expect(native.named('disconnect'), isEmpty);
    });
  });

  group('disconnect', () {
    test('waits for native and resets state', () async {
      await connected();
      await n().disconnect();
      expect(st().connectionState, VpnState.disconnecting);
      expect(native.named('disconnect'), hasLength(1));
      emit({'type': 'state', 'value': 'disconnected'});
      await _settle();
      expect(st().connectionState, VpnState.disconnected);
      expect(st().activeSocksPort, 0);
      expect(st().stats.uploadBytes, 0);
    });

    test('native error forces disconnected', () async {
      native.onDisconnect = () => throw PlatformException(code: 'X', message: 'gone');
      await connected();
      await n().disconnect();
      expect(st().connectionState, VpnState.disconnected);
      expect(logs().last.message, 'Disconnect error: gone');
    });

    test('toggle connects and disconnects; disconnect when idle is a no-op', () async {
      await boot(configs: [_cfg('a')], activeId: 'a');
      await n().disconnect();
      expect(native.named('disconnect'), isEmpty);
      await n().toggle();
      expect(native.named('connect'), hasLength(1));
      emit({'type': 'state', 'value': 'connected', 'socksPort': 1});
      await _settle();
      await n().toggle();
      expect(native.named('disconnect'), hasLength(1));
    });
  });

  group('native events', () {
    test('error, blocked and reconnecting states', () async {
      await connected();
      emit({'type': 'state', 'value': 'reconnecting'});
      await _settle();
      expect(st().connectionState, VpnState.connecting);
      emit({'type': 'state', 'value': 'blocked'});
      await _settle();
      expect(st().isBlocked, isTrue);
      expect(st().error, isNull);
      emit({'type': 'state', 'value': 'error'});
      await _settle();
      expect(st().connectionState, VpnState.error);
      expect(st().error, 'Connection error');
    });

    test('native failure reason reaches error and blocked states', () async {
      await connected();
      emit({'type': 'state', 'value': 'blocked', 'error': 'port busy'});
      await _settle();
      expect((st().isBlocked, st().error), (true, 'port busy'));
      emit({'type': 'state', 'value': 'error', 'error': 'bad config'});
      await _settle();
      expect((st().isError, st().error), (true, 'bad config'));
    });

    test('late history after a failure keeps the reason; tunnel config is tracked', () async {
      final a = _cfg('a');
      await connected(configs: [a]);
      expect(n().runsConfig(a), isTrue);
      expect(n().runsConfig(a.copyWith(rawUri: 'trojan://edited')), isFalse);
      emit({'type': 'state', 'value': 'error', 'error': 'bad config'});
      emit({
        'type': 'statsHistory',
        'full': true,
        'epoch': 1,
        'seq': 1,
        'history': [
          {'uploadSpeed': 1, 'downloadSpeed': 1},
        ],
      });
      await _settle();
      expect(st().error, 'bad config');
      expect(st().stats.speedHistory, isEmpty);
      expect(n().runsConfig(a), isFalse);
    });

    test('repeated error state updates the reason', () async {
      await connected();
      emit({'type': 'state', 'value': 'error'});
      emit({'type': 'state', 'value': 'error', 'error': 'port busy'});
      await _settle();
      expect(st().error, 'port busy');
    });

    test('log events go to the log with level', () async {
      await boot();
      emit({'type': 'log', 'level': 'warning', 'message': 'w'});
      emit({'type': 'log', 'level': 'nonsense', 'message': 'i'});
      emit({'type': 'stats', 'upload': 1});
      native.sink!.success('not a map');
      await _settle();
      final tail = logs().reversed.take(2).toList().reversed.toList();
      expect(tail.map((e) => (e.level, e.message, e.source)), [
        (LogLevel.warning, 'w', 'xray'),
        (LogLevel.info, 'i', 'xray'),
      ]);
    });

    test('speed history: full replaces, delta appends only when it continues', () async {
      await connected();
      Map<String, Object?> pts(int n) => {'uploadSpeed': n, 'downloadSpeed': n};
      emit({
        'type': 'statsHistory',
        'full': true,
        'epoch': 1,
        'seq': 3,
        'history': [pts(1), pts(2), pts(3)],
      });
      await _settle();
      expect(st().stats.speedHistory.map((p) => p.uploadSpeed), [1, 2, 3]);

      emit({
        'type': 'statsHistory',
        'epoch': 1,
        'from': 3,
        'seq': 4,
        'history': [pts(4)],
      });
      await _settle();
      expect(st().stats.speedHistory.map((p) => p.uploadSpeed), [1, 2, 3, 4]);

      // A late response doesn't duplicate points and resets the epoch.
      emit({
        'type': 'statsHistory',
        'epoch': 1,
        'from': 3,
        'seq': 4,
        'history': [pts(4)],
      });
      emit({
        'type': 'statsHistory',
        'epoch': 1,
        'from': 4,
        'seq': 5,
        'history': [pts(5)],
      });
      await _settle();
      expect(st().stats.speedHistory, hasLength(4));

      emit({
        'type': 'statsHistory',
        'full': true,
        'epoch': 2,
        'seq': 400,
        'history': [for (var i = 0; i < 400; i++) pts(i)],
      });
      await _settle();
      expect(st().stats.speedHistory, hasLength(300));
      expect(st().stats.speedHistory.last.uploadSpeed, 399);
    });
  });

  group('tunnel_dead', () {
    const switchOn = AppSettings(
      randomPort: false,
      randomCredentials: false,
      socksUser: 'su',
      socksPassword: 'sp',
      heartbeat: HeartbeatSettings(failAction: HeartbeatFailAction.switchConfig),
    );
    final subConfigs = [_cfg('a', subId: 's'), _cfg('b', subId: 's'), _cfg('c', subId: 's'), _cfg('d', subId: 'other')];

    test('switches to the fastest live config of the same subscription', () async {
      native.outboundMs = {'hb.example': 200, 'hc.example': 80, 'hd.example': 1};
      await connected(configs: subConfigs, settings: switchOn);
      emit({'type': 'tunnel_dead', 'failures': 3});
      await _settle();
      final probed = native.named('measureOutbound').map((m) => (m.arguments as Map)['config'] as String);
      expect(probed.where((cfg) => cfg.contains('ha.example') || cfg.contains('hd.example')), isEmpty);
      expect(probed, hasLength(2));
      expect(native.named('measureOutbound').first.arguments, containsPair('url', HeartbeatTarget.cloudflare.url));
      expect(c.read(configProvider).value!.activeConfigId, 'c');
      expect(native.named('connect'), hasLength(2));
      expect(native.lastConnect()['xrayConfig'], contains('hc.example'));
    });

    test('pinned source probes only pinned configs', () async {
      native.outboundMs = {'hd.example': 10};
      await boot(
        configs: subConfigs,
        activeId: 'a',
        pins: [PinnedRef.of(subConfigs[3])],
        settings: switchOn.copyWith(
          heartbeat: const HeartbeatSettings(
            failAction: HeartbeatFailAction.switchConfig,
            switchSource: SwitchSource.pinned,
          ),
        ),
      );
      await n().connect();
      emit({'type': 'state', 'value': 'connected', 'socksPort': 1});
      emit({'type': 'tunnel_dead', 'failures': 3});
      await _settle();
      expect(native.named('measureOutbound'), hasLength(1));
      expect(c.read(configProvider).value!.activeConfigId, 'd');
    });

    test('no live candidates keeps the current config', () async {
      await connected(configs: subConfigs, settings: switchOn);
      emit({'type': 'tunnel_dead', 'failures': 3});
      await _settle();
      expect(native.named('measureOutbound'), hasLength(2));
      expect(c.read(configProvider).value!.activeConfigId, 'a');
      expect(native.named('connect'), hasLength(1));
      expect(logs().last.message, contains('no live configs found'));
    });

    test('reconnect action ignores the event', () async {
      await connected(configs: subConfigs);
      emit({'type': 'tunnel_dead', 'failures': 3});
      await _settle();
      expect(native.named('measureOutbound'), isEmpty);
    });
  });

  group('ping', () {
    test('pings each endpoint once and stores the result', () async {
      native.pingMs = {'ha.example': 30, 'shared.example': 40};
      await boot(
        configs: [
          _cfg('a'),
          _cfg('b'),
          _cfg('raw', host: 'shared.example', rawXray: _visionRaw),
          _cfg('plain', host: 'shared.example'),
        ],
      );
      await n().pingAllConfigs();
      final pinged = native.named('ping').map((m) => (m.arguments as Map)['address']).toList();
      expect(pinged, unorderedEquals(['ha.example', 'hb.example', 'shared.example']));
      final byId = {for (final c in c.read(configProvider).value!.configs) c.id: c};
      expect(byId['a']!.latencyMs, 30);
      expect(byId['b']!.latencyMs, isNull);
      expect(byId['b']!.lastPingedAt, isNotNull);
      expect(byId['raw']!.latencyMs, 40);
      expect(byId['plain']!.latencyMs, 40);
    });

    test('stale ping skips recently pinged configs', () async {
      await boot(
        configs: [
          _cfg('fresh', pingedAt: DateTime.now()),
          _cfg('old'),
        ],
      );
      await n().pingStaleConfigs();
      expect(native.named('ping').map((m) => (m.arguments as Map)['address']), ['hold.example']);
      native.calls.clear();
      await boot(configs: [_cfg('fresh', pingedAt: DateTime.now())]);
      await n().pingStaleConfigs();
      expect(native.named('ping'), isEmpty);
    });
  });

  group('core switch', () {
    test('connected session on an unsupported config is disconnected', () async {
      await connected(configs: [_cfg('r', rawXray: _visionRaw)]);
      await c
          .read(settingsProvider.notifier)
          .save(_settings.copyWith(disabledCores: {CoreKind.xrayGo, CoreKind.singBox}));
      await _settle();
      expect(native.named('disconnect'), hasLength(1));
      expect(st().error, isNotNull);
    });

    test('idle switch saves or clears the quick-connect config', () async {
      await boot(configs: [_cfg('a')], activeId: 'a');
      await c
          .read(settingsProvider.notifier)
          .save(_settings.copyWith(coreOrder: [CoreKind.xrayRust, CoreKind.xrayGo, CoreKind.singBox]));
      await _settle();
      expect((native.named('saveQuickConnect').single.arguments as Map)['engine'], 'rust');

      // Rust doesn't take a raw config — the active profile's core doesn't change.
      native.calls.clear();
      await boot(
        configs: [_cfg('r', rawXray: _visionRaw)],
        activeId: 'r',
      );
      await c
          .read(settingsProvider.notifier)
          .save(_settings.copyWith(coreOrder: [CoreKind.xrayRust, CoreKind.xrayGo, CoreKind.singBox]));
      await _settle();
      expect(native.named('saveQuickConnect'), isEmpty);
      expect(native.named('clearQuickConnect'), isEmpty);
      await c
          .read(settingsProvider.notifier)
          .save(_settings.copyWith(disabledCores: {CoreKind.xrayGo, CoreKind.singBox}));
      await _settle();
      expect(native.named('clearQuickConnect'), hasLength(1));
    });

    test('idle switch to sing-box saves a sing-box config or clears an unsupported one', () async {
      await boot(configs: [_cfg('a')], activeId: 'a');
      await c
          .read(settingsProvider.notifier)
          .save(_settings.copyWith(coreOrder: [CoreKind.singBox, CoreKind.xrayGo, CoreKind.xrayRust]));
      await _settle();
      final args = native.named('saveQuickConnect').single.arguments as Map;
      expect(args['engine'], 'box');
      final json = jsonDecode(args['xrayConfig'] as String) as Map<String, dynamic>;
      expect(((json['inbounds'] as List).first as Map)['type'], 'mixed');

      await boot(
        configs: [_cfg('r', rawXray: _visionRaw)],
        activeId: 'r',
      );
      await c
          .read(settingsProvider.notifier)
          .save(_settings.copyWith(disabledCores: {CoreKind.xrayGo, CoreKind.xrayRust}));
      await _settle();
      expect(native.named('clearQuickConnect'), hasLength(1));
    });
  });

  group('misc', () {
    test('tunnel SOCKS follows the connection and a subscription fetch can read it', () async {
      await connected();
      final socks = c.read(tunnelSocksProvider);
      expect((socks?.port, socks?.user, socks?.password), (2080, 'su', 'sp'));
      // configProvider reads tunnelSocksProvider while vpnProvider depends on configProvider (through
      // activeCoreProvider): in debug Riverpod refuses the read if tunnelSocksProvider depends on vpnProvider.
      await expectLater(
        c.read(configProvider.notifier).addSubscriptionFromUrl('http://127.0.0.1:1/sub'),
        throwsA(predicate((Object e) => !e.toString().contains('CircularDependencyError'))),
      );
      emit({'type': 'state', 'value': 'disconnected'});
      await _settle();
      expect(c.read(tunnelSocksProvider), isNull);
    });

    test('syncNativeState adopts native credentials', () async {
      await boot();
      native.state = {'state': 'connected', 'socksPort': 7000, 'socksUser': 'x', 'socksPassword': 'y'};
      await n().syncNativeState();
      expect(st().isConnected, isTrue);
      expect(st().activeSocksPort, 7000);
    });

    test('stats poller updates traffic while connected', () async {
      await connected();
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await _settle();
      expect(st().stats.uploadBytes, 10);
      expect(st().stats.downloadSpeedBps, 2);
      n().pauseStatsPolling();
    });

    test('tunnel diag and log helpers', () async {
      await boot();
      await n().dumpTunnelDiag();
      expect(logs().last.message, 'tunnel diag: not running');
      await n().setLogsEnabled(false);
      await n().clearNativeLogs();
      expect(await n().getLogFilePath(), isNull);
      expect(native.named('clearLogs'), hasLength(1));
      expect(n().connectionState, VpnState.disconnected);
    });
  });

  // In fakeAsync EventChannel events aren't delivered (root zone), MethodChannel works.
  group('timeouts', () {
    test('connect without native confirmation times out after 45 s', () {
      fakeAsync((async) {
        boot(configs: [_cfg('a')], activeId: 'a');
        async.flushMicrotasks();
        n().connect();
        async.flushMicrotasks();
        expect(st().connectionState, VpnState.connecting);
        async.elapse(const Duration(seconds: 44));
        expect(st().connectionState, VpnState.connecting);
        async.elapse(const Duration(seconds: 2));
        expect(st().connectionState, VpnState.error);
        expect(st().error, 'Connection timeout');
        expect(native.named('disconnect'), hasLength(1));
        c.dispose();
      });
    });

    test('native reconnect cycle cancels the connect timeout', () {
      fakeAsync((async) {
        boot(configs: [_cfg('a')], activeId: 'a');
        async.flushMicrotasks();
        n().connect();
        async.flushMicrotasks();
        // syncNativeState doesn't know whose connecting this is, and clears the timeout.
        native.state = {'state': 'connecting'};
        n().syncNativeState();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 60));
        expect(st().connectionState, VpnState.connecting);
        c.dispose();
      });
    });

    test('disconnect without native confirmation completes after 10 s', () {
      fakeAsync((async) {
        boot(configs: [_cfg('a')], activeId: 'a');
        async.flushMicrotasks();
        n().connect();
        async.flushMicrotasks();
        n().disconnect();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 9));
        expect(st().connectionState, VpnState.disconnecting);
        async.elapse(const Duration(seconds: 2));
        expect(st().connectionState, VpnState.disconnected);
        c.dispose();
      });
    });
  });
}

class _FailingSelection extends ConfigNotifier {
  static var fail = false;

  @override
  Future<void> applySelection(ConfigSelection selection) =>
      fail ? Future.error(StateError('storage write failed')) : super.applySelection(selection);
}

/// Real storage writes take event-loop turns: providers recompute in between.
class _SlowSelection extends ConfigNotifier {
  @override
  Future<void> applySelection(ConfigSelection selection) async {
    await super.applySelection(selection);
    await Future<void>.delayed(Duration.zero);
  }
}
