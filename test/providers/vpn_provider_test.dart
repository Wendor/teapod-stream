import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
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
import 'package:teapodstream/core/services/geosite_index.dart';
import 'package:teapodstream/core/models/routing_settings.dart';
import 'package:teapodstream/providers/geo_provider.dart';
import 'package:teapodstream/core/models/pinned_ref.dart';
import 'package:teapodstream/core/services/profile_storage_service.dart';
import 'package:teapodstream/core/models/profile.dart';
import 'package:teapodstream/core/models/profile_bundle.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/l10n/l10n.dart';
import 'package:teapodstream/core/models/vpn_log_entry.dart';
import 'package:teapodstream/core/services/config_storage_service.dart';
import 'package:teapodstream/core/services/log_service.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/core/services/subscription_service.dart';
import 'package:teapodstream/core/services/tunnel_socks.dart';
import 'package:teapodstream/core/models/subscription.dart';
import 'package:teapodstream/core/models/app_message.dart';
import 'package:teapodstream/core/models/app_settings.dart';
import 'package:teapodstream/protocols/xray/xray_engine.dart';
import 'package:teapodstream/protocols/xray/xray_rust_backend.dart';
import 'package:teapodstream/providers/config_provider.dart';
import 'package:teapodstream/providers/profile_provider.dart';
import 'package:teapodstream/providers/settings_provider.dart';
import 'package:teapodstream/providers/quick_connect_reconciler.dart';
import 'package:teapodstream/providers/vpn_provider.dart';
import 'package:teapodstream/providers/vpn_switcher.dart';
import 'package:teapodstream/providers/vpn_stats_provider.dart';
import 'package:teapodstream/core/models/vpn_stats.dart';
import 'package:teapodstream/providers/ping_provider.dart';
import 'package:teapodstream/providers/native_logs_provider.dart';
import 'package:teapodstream/providers/auto_switch_provider.dart';

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

VpnConfig _cfg(
  String id, {
  String? subId,
  String password = 'p',
  DateTime? pingedAt,
  String? rawXray,
  String? host,
  int port = 443,
}) => VpnConfig(
  id: id,
  name: 'n$id',
  protocol: VpnProtocol.trojan,
  address: host ?? 'h$id.example',
  port: port,
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
  Map<String, Object?> state = {'value': 'disconnected'};
  List<String> logs = [];

  /// host → latency via `measureOutbound`; null — the server is dead.
  Map<String, int?> outboundMs = {};

  /// Holds `measureOutbound` answers until it completes; null — they come at once.
  Future<void>? outboundGate;

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
        final ms = outboundMs.entries.where((e) => cfg.contains(e.key)).firstOrNull?.value;
        return outboundGate == null ? ms : outboundGate!.then((_) => ms);
      case 'getStats':
        final args = call.arguments as Map?;
        return {
          'upload': 10,
          'download': 20,
          'uploadSpeed': 1,
          'downloadSpeed': 2,
          if (args != null)
            'history': {
              'epoch': 1,
              'seq': 1,
              'from': args['since'],
              'full': args['epoch'] != 1,
              'history': [
                {'timestamp': 0, 'uploadSpeed': 5, 'downloadSpeed': 6},
              ],
            },
        };
    }
    return null;
  }
}

/// Records the core each call was given, without touching the method channel.
class _RecordingEngine extends XrayEngine {
  final connects = <CoreKind>[];
  final quickSaves = <CoreKind>[];

  @override
  Future<void> connect(VpnConfig config, CoreBackend backend, VpnEngineOptions options, {int attempt = 0}) async =>
      connects.add(backend.kind);

  @override
  Future<void> saveQuickConnect(VpnConfig config, CoreBackend backend, VpnEngineOptions options) async =>
      quickSaves.add(backend.kind);
}

class _FakeSubscriptions extends SubscriptionService {
  final List<VpnConfig> configs;
  _FakeSubscriptions(this.configs);

  @override
  Future<SubscriptionFetchResult> fetchSubscription(
    String url, {
    String? pinnedCertDer,
    HwidDeviceInfo? hwid,
    String? userAgent,
    TunnelSocks? socks,
  }) async => SubscriptionFetchResult(configs: configs);
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
  VpnSwitcher sw() => c.read(vpnSwitcherProvider.notifier);
  VpnStats stats() => c.read(vpnStatsProvider);
  VpnStatus st() => c.read(vpnProvider);
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
    List<Subscription> subs = const [],
    String? activeSubId,
    AppSettings settings = _settings,
    List<Override> overrides = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SettingsService().save(settings);
    final storage = ConfigStorageService();
    await storage.saveConfigs(configs);
    await storage.saveActiveConfigId(activeId);
    await storage.saveSubscriptions(subs);
    await storage.saveActiveSubscriptionId(activeSubId);
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
    // What the app shell keeps alive.
    c.listen(vpnStatsProvider, (_, _) {});
    c.read(autoSwitchProvider);
    c.listen(quickConnectReconcilerProvider, (_, _) {});
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
        'value': 'connected',
        'socksPort': 5555,
        'socksUser': 'nu',
        'socksPassword': 'np',
        'connectedAtMs': DateTime.now().millisecondsSinceEpoch - 60000,
      };
      native.logs = ['1700000000000|warning|from last session'];
      await boot();
      await c.read(nativeLogsProvider).restore();
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
      expect(st().error, const AppMessage(MessageCode.vpnNoConfigSelected));
      expect(logs().last.level, LogLevel.error);
      expect(native.named('connect'), isEmpty);
    });

    test('invalid config fails validation', () async {
      await boot(
        configs: [_cfg('a', password: '')],
        activeId: 'a',
      );
      await n().connect();
      // The stored reason is the app string, localized where it is shown.
      final ru = lookupAppLocalizations(const Locale('ru'));
      expect(st().error!.localize(lookupAppLocalizations(const Locale('en'))), 'Empty password');
      expect(st().error!.localize(ru), ru.validateEmptyPassword);
      expect(native.named('connect'), isEmpty);
    });

    test('sends settings and follows native events', () async {
      await boot(configs: [_cfg('a')], activeId: 'a');
      await n().connect();
      expect(st().connectionState, VpnState.connecting);
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
      expect((st().activeSocksPort, st().activeSocksUser, st().activeSocksPassword), (2080, 'su', 'sp'));
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
      expect(st().error, const AppMessage.text('denied'));
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

    test('selectConfig switches a live tunnel to another config and leaves the running one alone', () async {
      await connected(configs: [_cfg('a'), _cfg('b')]);
      expect(await sw().selectConfig(c.read(configProvider).value!.configs.first), isNull);
      await _settle();
      expect(native.named('connect'), hasLength(1), reason: 'the running config: no rebuild');
      expect(await sw().selectConfig(c.read(configProvider).value!.configs.last), isNull);
      await _settle();
      expect(c.read(configProvider).value!.activeConfigId, 'b');
      expect(native.named('connect'), hasLength(2));
      expect(native.lastConnect()['xrayConfig'], contains('hb.example'));
    });

    test('overlapping selections end with the tunnel on the last one', () async {
      await connected(configs: [_cfg('a'), _cfg('b')]);
      final configs = c.read(configProvider).value!.configs;
      // b, then back to a before b's save and reconnect are done.
      final toB = sw().selectConfig(configs.last);
      final toA = sw().selectConfig(configs.first);
      expect(await toB, isNull);
      expect(await toA, isNull);
      // The native side answers: each connect ends connected, each disconnect disconnected.
      for (var i = 0; i < 20; i++) {
        await _settle();
        if (!st().isBusy) break;
        final value = st().isDisconnecting ? 'disconnected' : 'connected';
        emit({'type': 'state', 'value': value, 'socksPort': 2080, 'socksUser': 'su', 'socksPassword': 'sp'});
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      expect(c.read(configProvider).value!.activeConfigId, 'a');
      expect(st().isConnected, isTrue);
      expect(n().runsConfig(configs.first), isTrue, reason: 'the tunnel must not stay on b');
    });

    test('selectConfig refuses a config no enabled core runs and changes nothing', () async {
      await boot(
        configs: [_cfg('a'), _cfg('b')],
        activeId: 'a',
        settings: _settings.copyWith(proxyOnly: true, disabledCores: {CoreKind.xrayGo, CoreKind.singBox}),
      );
      final reason = await sw().selectConfig(c.read(configProvider).value!.configs.last);
      expect(reason, const XrayRustBackend().unavailableReason(CoreFeature.proxyOnly));
      expect(c.read(configProvider).value!.activeConfigId, 'a');
    });

    test('selectConfig while disconnected only selects', () async {
      await boot(configs: [_cfg('a'), _cfg('b')], activeId: 'a');
      expect(await sw().selectConfig(c.read(configProvider).value!.configs.last), isNull);
      await _settle();
      expect(c.read(configProvider).value!.activeConfigId, 'b');
      expect(native.named('connect'), isEmpty);
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
      final en = lookupAppLocalizations(const Locale('en'));
      final ru = lookupAppLocalizations(const Locale('ru'));
      void expectReason() {
        expect(st().error!.localize(en), en.validateEmptyPassword);
        expect(st().error!.localize(ru), ru.validateEmptyPassword);
      }

      expect(st().isConnected, isTrue);
      expectReason();
      expect(native.named('connect'), hasLength(1));
      // A stats tick keeps the reason, still localizable.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await _settle();
      expect(stats().uploadBytes, 10);
      expectReason();
      c.read(vpnStatsProvider.notifier).pause();
    });

    test('importProfile adds the profile and switches to it unless asked not to', () async {
      await connected();
      await c.read(profileProvider.future);
      final bundle = ProfileBundle(
        exportedAt: DateTime(2026),
        profile: Profile(id: 'x', name: 'Imported', settings: _settings, createdAt: DateTime(2026)),
      );
      final kept = c.read(profileProvider).value!.activeProfileId;
      final quiet = await sw().importProfile(bundle, switchTo: false, sourceUrl: 'https://s');
      expect(c.read(profileProvider).value!.activeProfileId, kept);
      final p = c.read(profileProvider).value!.profiles.singleWhere((p) => p.id == quiet);
      expect((p.name, p.sourceUrl, p.readonly), ('Imported', 'https://s', false));

      final id = await sw().importProfile(bundle, makeReadonly: true);
      expect(c.read(profileProvider).value!.activeProfileId, id);
      expect(c.read(profileProvider).value!.activeProfile!.readonly, isTrue);
    });

    test('profile switch reconnects only when the server or settings change', () async {
      await connected(configs: [_cfg('a'), _cfg('b')]);
      final profiles = c.read(profileProvider.notifier);
      await c.read(profileProvider.future);
      await profiles.createProfile('B');
      final defaultId = c.read(profileProvider).value!.activeProfileId;
      final bId = c.read(profileProvider).value!.profiles.last.id;

      // same server, same settings — the tunnel stays
      await sw().switchProfile(bId);
      await c.read(configProvider.notifier).setActiveConfig('b');
      await sw().switchProfile(defaultId);
      await _settle();
      expect(native.named('connect'), hasLength(1));

      // B remembered server b
      await sw().switchProfile(bId);
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
      await sw().switchProfile(bId); // B remembers the current server
      await c.read(settingsProvider.notifier).save(_settings.copyWith(mtu: 1400));
      await sw().switchProfile(defaultId);
      await _settle();
      final before = native.named('connect').length;

      _FailingSelection.fail = true;
      addTearDown(() => _FailingSelection.fail = false);
      await expectLater(sw().switchProfile(bId), throwsA(isA<StateError>()));
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
      await sw().switchProfile(bId);
      await c.read(settingsProvider.notifier).save(_settings);
      await c.read(configProvider.notifier).setActiveConfig('r');
      await _settle();

      // in between, sing-box settings with the raw config (or the reverse) can't run
      await sw().switchProfile(boxId);
      await _settle();
      expect(native.lastConnect()['engine'], 'box');
      await sw().switchProfile(bId);
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
      c.invalidate(profileProvider);
      await c.read(profileProvider.future);
      confirmConnects();

      await Future.wait([sw().switchProfile('W'), sw().switchProfile('Y')]);
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
      c.invalidate(profileProvider);
      await c.read(profileProvider.future);

      await sw().switchProfile('B');
      await _settle();
      expect(native.named('disconnect'), hasLength(1));
      expect(st().error, isNotNull);
      // The reason outlives the stop it caused; native tags the stop with its last Flutter connect, not the session's.
      emit({'type': 'state', 'value': 'disconnected', 'attempt': 4242});
      await _settle();
      expect(st().connectionState, VpnState.error);
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
      c.invalidate(profileProvider);
      await c.read(profileProvider.future);
      final before = native.named('connect').length;
      final gate = Completer<void>();
      confirmConnects(gate.future);

      final switches = Future.wait([sw().switchProfile('W'), sw().switchProfile('Y')]);
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
      await sw().duringProfileSwitch(() async {
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

    test("a late event of a replaced session doesn't override a newer connect", () async {
      await boot(configs: [_cfg('a')], activeId: 'a');
      await n().connect();
      final first = native.lastConnect()['attempt'] as int;
      expect(first, greaterThan(0));
      await disconnectNow();
      await n().connect();
      final second = native.lastConnect()['attempt'] as int;
      expect(second, isNot(first));
      expect(st().connectionState, VpnState.connecting);

      // The first session's start fails only now.
      emit({'type': 'state', 'value': 'error', 'error': 'old server failed', 'attempt': first});
      await _settle();
      expect(st().connectionState, VpnState.connecting);
      expect(st().error, isNull);

      emit({
        'type': 'state',
        'value': 'connected',
        'socksPort': 2080,
        'socksUser': 'su',
        'socksPassword': 'sp',
        'attempt': second,
      });
      await _settle();
      expect(st().isConnected, isTrue);
    });

    test('a recreated notifier never reuses an attempt number an older session reports', () async {
      await boot(configs: [_cfg('a')], activeId: 'a');
      await n().connect();
      final before = native.lastConnect()['attempt'] as int;
      // The UI is recreated while the native session lives on.
      c.dispose();
      await boot(configs: [_cfg('a')], activeId: 'a');
      await n().connect();
      expect(native.lastConnect()['attempt'] as int, isNot(before));
    });

    test('after a UI restart a native reconnect of the surviving session and its disconnect still apply', () async {
      native.state = {'value': 'connected', 'socksPort': 2080, 'socksUser': 'su', 'socksPassword': 'sp', 'attempt': 5};
      await boot(configs: [_cfg('a')], activeId: 'a');
      expect(st().isConnected, isTrue);
      emit({'type': 'state', 'value': 'reconnecting', 'attempt': 5});
      await _settle();
      expect(st().connectionState, VpnState.connecting);
      emit({'type': 'state', 'value': 'disconnected', 'attempt': 5});
      await _settle();
      expect(st().connectionState, VpnState.disconnected);
    });

    test("a resume sync during a pending connect ignores another session's snapshot", () async {
      await boot(configs: [_cfg('a')], activeId: 'a');
      await n().connect();
      final attempt = native.lastConnect()['attempt'] as int;
      native.state = {'value': 'error', 'attempt': attempt - 1}; // an older session failed meanwhile
      await n().syncNativeState();
      await _settle();
      expect(st().connectionState, VpnState.connecting);
      expect(st().error, isNull);
      // The older session's later events are still dropped; the pending connect's own outcome applies.
      emit({'type': 'state', 'value': 'error', 'error': 'old', 'attempt': attempt - 1});
      await _settle();
      expect(st().connectionState, VpnState.connecting);
      emit({
        'type': 'state',
        'value': 'connected',
        'socksPort': 2080,
        'socksUser': 'su',
        'socksPassword': 'sp',
        'attempt': attempt,
      });
      await _settle();
      expect(st().isConnected, isTrue);
    });

    test('a resume before the connect reaches the service keeps the pending connect', () async {
      await boot(configs: [_cfg('a')], activeId: 'a');
      final permission = Completer<Map<int, int>>();
      messenger.setMockMethodCallHandler(_permissions, (call) => permission.future);
      final pending = n().connect();
      await _settle();
      // The notification-permission dialog closes: the app resumes, native still reports the idle service.
      native.state = {'value': 'disconnected', 'attempt': 0};
      await n().syncNativeState();
      await _settle();
      expect(st().connectionState, VpnState.connecting);
      permission.complete({17: 1});
      await pending;
      expect(native.named('connect'), hasLength(1));
    });

    test("a resume before the connect reaches the service ignores a natively started session's error", () async {
      await boot(configs: [_cfg('a')], activeId: 'a');
      final permission = Completer<Map<int, int>>();
      messenger.setMockMethodCallHandler(_permissions, (call) => permission.future);
      final pending = n().connect();
      await _settle();
      // A session started from the tile failed before the connect; its untagged state is still there.
      native.state = {'value': 'error', 'attempt': 0};
      await n().syncNativeState();
      await _settle();
      expect(st().connectionState, VpnState.connecting);
      permission.complete({17: 1});
      await pending;
      expect(native.named('connect'), hasLength(1));
    });

    test('a connect settled by the startup sync follows a later idle snapshot', () async {
      final syncGate = Completer<void>();
      var first = true;
      messenger.setMockMethodCallHandler(_method, (call) async {
        if (call.method == 'getState' && first) {
          first = false;
          await syncGate.future;
        }
        return native.handle(call);
      });
      await boot(configs: [_cfg('a')], activeId: 'a');
      // The startup sync's answer is slow; a connect starts meanwhile and native brings it up.
      await n().connect();
      final attempt = native.lastConnect()['attempt'] as int;
      native.state = {'value': 'connected', 'socksPort': 2080, 'attempt': attempt};
      syncGate.complete();
      await _settle();
      expect(st().isConnected, isTrue);
      // The service died: the idle snapshot of a resume applies.
      native.state = {'value': 'disconnected', 'attempt': 0};
      await n().syncNativeState();
      await _settle();
      expect(st().connectionState, VpnState.disconnected);
    });

    test('tagged events outside a newer connect and untagged events apply as before', () async {
      await boot(configs: [_cfg('a')], activeId: 'a');
      await n().connect();
      final first = native.lastConnect()['attempt'] as int;
      final d = n().disconnect(); // bumps the attempt; not a connect
      emit({'type': 'state', 'value': 'disconnected', 'attempt': first});
      await d;
      await _settle();
      expect(st().connectionState, VpnState.disconnected);

      await n().connect();
      // A session started natively (tile, boot) has no tag.
      emit({'type': 'state', 'value': 'error', 'error': 'native failure'});
      await _settle();
      expect(st().connectionState, VpnState.error);
      expect(st().error, const AppMessage.text('native failure'));
    });

    test('a new config while connecting replaces the starting session without a disconnect', () async {
      await boot(configs: [_cfg('a'), _cfg('b')], activeId: 'a');
      await n().connect();
      final first = native.lastConnect()['attempt'] as int;
      await c.read(configProvider.notifier).setActiveConfig('b');
      await n().reconnectWithNewConfig();
      expect(native.named('disconnect'), isEmpty);
      expect(native.named('connect'), hasLength(2));
      final second = native.lastConnect()['attempt'] as int;
      expect(native.lastConnect()['xrayConfig'], contains('hb.example'));
      // The replaced start's failure is not this connect's outcome.
      emit({'type': 'state', 'value': 'error', 'error': 'replaced', 'attempt': first});
      await _settle();
      expect(st().connectionState, VpnState.connecting);
      emit({'type': 'state', 'value': 'connected', 'socksPort': 2080, 'attempt': second});
      await _settle();
      expect(n().runsConfig(_cfg('b')), isTrue);
    });

    test("a refused switch shows the old session's latest state", () async {
      await connected(
        configs: [
          _cfg('a'),
          _cfg('bad', password: ''),
        ],
      );
      final permission = Completer<Map<int, int>>();
      messenger.setMockMethodCallHandler(_permissions, (call) => permission.future);
      await c.read(configProvider.notifier).setActiveConfig('bad');
      final switching = n().reconnectWithNewConfig();
      await _settle();
      // The old session drops while the switch waits; its report isn't the switch's outcome.
      emit({'type': 'state', 'value': 'error', 'error': 'old dropped', 'attempt': 4242});
      await _settle();
      expect(st().connectionState, VpnState.connecting);
      permission.complete({17: 1});
      await switching;
      await _settle();
      expect((st().connectionState, st().error), (VpnState.error, const AppMessage.text('old dropped')));
      expect(c.read(tunnelSocksProvider), isNull);
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
      expect(stats().uploadBytes, 0);
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
      expect(st().error, const AppMessage(MessageCode.vpnConnectError));
    });

    test('native failure reason reaches error and blocked states', () async {
      await connected();
      emit({'type': 'state', 'value': 'blocked', 'error': 'port busy'});
      await _settle();
      expect((st().isBlocked, st().error), (true, const AppMessage.text('port busy')));
      emit({'type': 'state', 'value': 'error', 'error': 'bad config'});
      await _settle();
      expect((st().isError, st().error), (true, const AppMessage.text('bad config')));
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
      expect(st().error, const AppMessage.text('bad config'));
      expect(stats().speedHistory, isEmpty);
      expect(n().runsConfig(a), isFalse);
    });

    test('repeated error state updates the reason', () async {
      await connected();
      emit({'type': 'state', 'value': 'error'});
      emit({'type': 'state', 'value': 'error', 'error': 'port busy'});
      await _settle();
      expect(st().error, const AppMessage.text('port busy'));
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
      expect(stats().speedHistory.map((p) => p.uploadSpeed), [1, 2, 3]);

      emit({
        'type': 'statsHistory',
        'epoch': 1,
        'from': 3,
        'seq': 4,
        'history': [pts(4)],
      });
      await _settle();
      expect(stats().speedHistory.map((p) => p.uploadSpeed), [1, 2, 3, 4]);

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
      expect(stats().speedHistory, hasLength(4));

      emit({
        'type': 'statsHistory',
        'full': true,
        'epoch': 2,
        'seq': 400,
        'history': [for (var i = 0; i < 400; i++) pts(i)],
      });
      await _settle();
      expect(stats().speedHistory, hasLength(300));
      expect(stats().speedHistory.last.uploadSpeed, 399);
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

    test('auto mode stays on: the measured results make the live config its best', () async {
      native.outboundMs = {'hb.example': 200, 'hc.example': 80};
      await boot(
        configs: subConfigs,
        subs: [Subscription(id: 's', name: 'S', url: 'https://sub.example/s', createdAt: DateTime(2026))],
        activeSubId: 's',
        settings: switchOn,
      );
      await n().connect();
      emit({'type': 'state', 'value': 'connected', 'socksPort': 1});
      await _settle();
      expect(native.lastConnect()['xrayConfig'], contains('ha.example'));
      emit({'type': 'tunnel_dead', 'failures': 3});
      await _settle();
      final cs = c.read(configProvider).value!;
      expect(cs.activeSubscriptionId, 's');
      expect(c.read(effectiveConfigProvider)?.id, 'c');
      expect(cs.configs.firstWhere((x) => x.id == 'a').latencyMs, isNull);
      expect(native.lastConnect()['xrayConfig'], contains('hc.example'));
    });

    test('auto mode stays on when the failed config shares the endpoint of the live one', () async {
      final shared = [
        _cfg('a', subId: 's', host: 'same.example'),
        _cfg('b', subId: 's', host: 'same.example', password: 'q'),
      ];
      native.outboundMs = {'same.example': 60};
      await boot(
        configs: shared,
        subs: [Subscription(id: 's', name: 'S', url: 'https://sub.example/s', createdAt: DateTime(2026))],
        activeSubId: 's',
        settings: switchOn,
      );
      await n().connect();
      emit({'type': 'state', 'value': 'connected', 'socksPort': 1});
      await _settle();
      emit({'type': 'tunnel_dead', 'failures': 3});
      await _settle();
      final byId = {for (final x in c.read(configProvider).value!.configs) x.id: x};
      expect(c.read(configProvider).value!.activeSubscriptionId, 's');
      expect(byId['a']!.latencyMs, isNull);
      expect(byId['b']!.latencyMs, 60);
      expect(c.read(effectiveConfigProvider)?.id, 'b');
    });

    test('auto mode stays on when configs of the subscription were not probed (pinned source)', () async {
      native.outboundMs = {'hc.example': 50};
      await boot(
        configs: subConfigs,
        pins: [PinnedRef.of(subConfigs[2])],
        subs: [Subscription(id: 's', name: 'S', url: 'https://sub.example/s', createdAt: DateTime(2026))],
        activeSubId: 's',
        settings: switchOn.copyWith(
          heartbeat: const HeartbeatSettings(
            failAction: HeartbeatFailAction.switchConfig,
            switchSource: SwitchSource.pinned,
          ),
        ),
      );
      await n().connect();
      emit({'type': 'state', 'value': 'connected', 'socksPort': 1});
      await _settle();
      // b's TCP ping is better than c's urltest, but b wasn't probed.
      await c.read(configProvider.notifier).batchUpdatePingResults({
        'ha.example:443': 5,
        'hb.example:443': 1,
      }, DateTime(2026));
      await _settle();
      emit({'type': 'tunnel_dead', 'failures': 3});
      await _settle();
      expect(c.read(configProvider).value!.activeSubscriptionId, 's');
      expect(c.read(effectiveConfigProvider)?.id, 'c');
      expect(native.lastConnect()['xrayConfig'], contains('hc.example'));
    });

    test('a switch found during a profile switch runs after it', () async {
      native.outboundMs = {'hc.example': 80};
      await connected(configs: subConfigs, settings: switchOn);
      await sw().duringProfileSwitch(() async {
        emit({'type': 'tunnel_dead', 'failures': 3});
        await _settle();
        expect(native.named('measureOutbound'), isNotEmpty);
        expect(c.read(configProvider).value!.activeConfigId, 'a');
        return false;
      });
      await _settle();
      expect(c.read(configProvider).value!.activeConfigId, 'c');
      expect(native.lastConnect()['xrayConfig'], contains('hc.example'));
    });

    test('a switch is dropped when a profile switch changed the server meanwhile', () async {
      native.outboundMs = {'hc.example': 80};
      final probe = Completer<void>();
      native.outboundGate = probe.future;
      await connected(configs: subConfigs, settings: switchOn);
      await sw().duringProfileSwitch(() async {
        emit({'type': 'tunnel_dead', 'failures': 3});
        await _settle();
        expect(native.named('measureOutbound'), isNotEmpty); // the failed config is taken: the probes wait
        await c.read(configProvider.notifier).setActiveConfig('d');
        return true;
      });
      await _settle();
      expect(native.lastConnect()['xrayConfig'], contains('hd.example'));
      probe.complete();
      await _settle();
      expect(logs().map((l) => l.message), contains('urltest: the server changed meanwhile, no switch'));
      expect(c.read(configProvider).value!.activeConfigId, 'd');
      expect(native.lastConnect()['xrayConfig'], contains('hd.example'));
    });

    test('the config the session runs is the failed one, also when a ping moved the auto best', () async {
      native.outboundMs = {'hb.example': 50};
      await boot(
        configs: subConfigs,
        subs: [Subscription(id: 's', name: 'S', url: 'https://sub.example/s', createdAt: DateTime(2026))],
        activeSubId: 's',
        settings: switchOn,
      );
      await n().connect();
      emit({'type': 'state', 'value': 'connected', 'socksPort': 1});
      await _settle();
      // A ping makes b the auto best; the tunnel keeps running a.
      await c.read(configProvider.notifier).batchUpdatePingResults({
        'ha.example:443': 90,
        'hb.example:443': 10,
      }, DateTime(2026));
      await _settle();
      expect(native.named('connect'), hasLength(1));
      emit({'type': 'tunnel_dead', 'failures': 3});
      await _settle();
      final probed = native.named('measureOutbound').map((m) => (m.arguments as Map)['config'] as String);
      expect(probed.where((cfg) => cfg.contains('ha.example')), isEmpty);
      expect(native.named('connect'), hasLength(2));
      expect(native.lastConnect()['xrayConfig'], contains('hb.example'));
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
      await c.read(pingProvider.notifier).pingAll();
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
      await c.read(pingProvider.notifier).pingStale();
      expect(native.named('ping').map((m) => (m.arguments as Map)['address']), ['hold.example']);
      native.calls.clear();
      await boot(configs: [_cfg('fresh', pingedAt: DateTime.now())]);
      await c.read(pingProvider.notifier).pingStale();
      expect(native.named('ping'), isEmpty);
    });
  });

  group('core switch', () {
    test('the engine gets the resolved core on connect and on a quick-connect save', () async {
      final engine = _RecordingEngine();
      await boot(
        configs: [_cfg('a')],
        activeId: 'a',
        settings: _settings.copyWith(coreOrder: [CoreKind.singBox, CoreKind.xrayGo, CoreKind.xrayRust]),
        overrides: [xrayEngineProvider.overrideWithValue(engine)],
      );
      await n().connect();
      expect(engine.connects, [CoreKind.singBox]);

      await n().disconnect();
      emit({'type': 'state', 'value': 'disconnected'});
      await _settle();
      await c
          .read(settingsProvider.notifier)
          .save(_settings.copyWith(coreOrder: [CoreKind.xrayRust, CoreKind.xrayGo, CoreKind.singBox]));
      await _settle();
      // The ended session re-saves what would run now (sing-box), then the core change saves rust.
      expect(engine.quickSaves, [CoreKind.singBox, CoreKind.xrayRust]);
      expect(native.named('connect'), isEmpty);
    });

    test('quick connect follows connection settings changed while off', () async {
      await boot(configs: [_cfg('a')], activeId: 'a');
      await c.read(settingsProvider.notifier).save(_settings.copyWith(killSwitchEnabled: true));
      await _settle();
      expect((native.named('saveQuickConnect').single.arguments as Map)['killSwitch'], isTrue);

      // A change outside the connection (auto-connect) saves nothing.
      native.calls.clear();
      await c.read(settingsProvider.notifier).save(_settings.copyWith(killSwitchEnabled: true, autoConnect: true));
      await _settle();
      expect(native.named('saveQuickConnect'), isEmpty);
    });

    test('an idle profile switch with the same core reaches quick connect', () async {
      await boot(configs: [_cfg('a')], activeId: 'a');
      await c.read(profileProvider.future);
      final profiles = c.read(profileProvider.notifier);
      final defaultId = c.read(profileProvider).value!.activeProfileId;
      await profiles.createProfile('B');
      final bId = c.read(profileProvider).value!.profiles.last.id;
      await sw().switchProfile(bId);
      await c.read(settingsProvider.notifier).save(_settings.copyWith(killSwitchEnabled: true));
      await _settle();
      expect((native.named('saveQuickConnect').last.arguments as Map)['killSwitch'], isTrue);

      native.calls.clear();
      await sw().switchProfile(defaultId);
      await _settle();
      expect(native.named("saveQuickConnect").map((c) => (c.arguments as Map)["killSwitch"]), [false]);
    });

    test('a server selected while off reaches quick connect', () async {
      await boot(configs: [_cfg('a'), _cfg('b')], activeId: 'a');
      await _settle();
      native.calls.clear();
      await sw().selectConfig(c.read(configProvider).value!.configs.last);
      await _settle();
      expect(native.named('saveQuickConnect').map((c) => (c.arguments as Map)['xrayConfig'] as String), [
        contains('hb.example'),
      ]);
    });

    group('the effective config changed while off reaches quick connect', () {
      final sub = Subscription(id: 's', name: 'S', url: 'https://sub.example/s', createdAt: DateTime(2026));
      List<String> saved() => [
        for (final call in native.named('saveQuickConnect')) (call.arguments as Map)['xrayConfig'] as String,
      ];

      test('a link edit', () async {
        await boot(configs: [_cfg('a')], activeId: 'a');
        native.calls.clear();
        await c.read(configProvider.notifier).updateConfig(_cfg('a', host: 'edited.example'));
        await _settle();
        expect(saved(), [contains('edited.example')]);
      });

      test('a subscription refresh', () async {
        await boot(
          configs: [_cfg('a', subId: 's')],
          subs: [sub],
          activeSubId: 's',
          overrides: [
            subscriptionServiceProvider.overrideWithValue(_FakeSubscriptions([_cfg('fresh', subId: 's')])),
          ],
        );
        native.calls.clear();
        await c.read(configProvider.notifier).addSubscriptionFromUrl(sub.url);
        await _settle();
        expect(saved(), [contains('hfresh.example')]);
      });

      test('auto mode turned on', () async {
        await boot(
          configs: [
            _cfg('a'),
            _cfg('b', subId: 's'),
          ],
          subs: [sub],
          activeId: 'a',
        );
        native.calls.clear();
        await c.read(configProvider.notifier).setActiveSubscription('s');
        await _settle();
        expect(saved(), [contains('hb.example')]);
      });

      test('a config connect refuses clears the saved parameters', () async {
        await boot(configs: [_cfg('a')], activeId: 'a');
        native.calls.clear();
        await c.read(configProvider.notifier).updateConfig(_cfg('a', port: 0));
        await _settle();
        expect(saved(), isEmpty);
        expect(native.named('clearQuickConnect'), hasLength(1));
      });

      test('a ping that changes the best config in auto mode', () async {
        await boot(
          configs: [
            _cfg('a', subId: 's'),
            _cfg('b', subId: 's'),
          ],
          subs: [sub],
          activeSubId: 's',
        );
        native.calls.clear();
        await c.read(configProvider.notifier).batchUpdatePingResults({
          'ha.example:443': 300,
          'hb.example:443': 40,
        }, DateTime(2026));
        await _settle();
        expect(saved(), [contains('hb.example')]);

        // A ping that keeps the best config saves nothing.
        native.calls.clear();
        await c.read(configProvider.notifier).batchUpdatePingResults({
          'ha.example:443': 200,
          'hb.example:443': 50,
        }, DateTime(2026, 2));
        await _settle();
        expect(saved(), isEmpty);
      });
    });

    test('a server selected while the geosite index loads is saved without missing codes', () async {
      final index = Completer<GeositeIndex?>();
      await boot(
        configs: [_cfg('a'), _cfg('b')],
        activeId: 'a',
        settings: _settings.copyWith(routing: const RoutingSettings(adBlockEnabled: true)),
        overrides: [geositeIndexProvider.overrideWith((ref) => index.future)],
      );
      native.calls.clear();
      await sw().selectConfig(c.read(configProvider).value!.configs.last);
      await _settle();
      expect(native.named('saveQuickConnect'), isEmpty);
      index.complete(const GeositeIndex({}));
      await _settle();
      final saved = native.named('saveQuickConnect').single.arguments as Map;
      expect(saved['xrayConfig'], allOf(contains('hb.example'), isNot(contains('category-ads-all'))));
    });

    test('a save waiting for the geosite index skips a profile switch begun meanwhile', () async {
      final index = Completer<GeositeIndex?>();
      await boot(
        configs: [_cfg('a')],
        activeId: 'a',
        overrides: [geositeIndexProvider.overrideWith((ref) => index.future)],
      );
      await c.read(settingsProvider.notifier).save(_settings.copyWith(killSwitchEnabled: true));
      await _settle();
      native.calls.clear();
      var savedDuringSwitch = -1;
      await sw().duringProfileSwitch(() async {
        index.complete(const GeositeIndex({}));
        await _settle();
        savedDuringSwitch = native.named('saveQuickConnect').length;
        return true;
      });
      await _settle();
      expect(savedDuringSwitch, 0);
      expect(native.named('saveQuickConnect'), isNotEmpty); // the switch's end saves
    });

    test("native's off report saves quick connect again", () async {
      // A timed-out connect shows `error` before native stops, and the save asked for then is refused: native's
      // later off report (no state change here) must save again.
      await boot(configs: [_cfg('a')], activeId: 'a');
      await _settle();
      native.calls.clear();
      emit({'type': 'state', 'value': 'disconnected', 'attempt': 0});
      emit({'type': 'state', 'value': 'disconnected', 'attempt': 0});
      await _settle();
      expect(native.named('saveQuickConnect'), hasLength(1));
    });

    test('settings changed during a session reach quick connect when it ends', () async {
      await connected();
      await c.read(settingsProvider.notifier).save(_settings.copyWith(killSwitchEnabled: true));
      await _settle();
      await n().disconnect();
      emit({'type': 'state', 'value': 'disconnected'});
      await _settle();
      expect((native.named('saveQuickConnect').last.arguments as Map)['killSwitch'], isTrue);
    });

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
      native.state = {'value': 'connected', 'socksPort': 7000, 'socksUser': 'x', 'socksPassword': 'y'};
      await n().syncNativeState();
      expect(st().isConnected, isTrue);
      expect(st().activeSocksPort, 7000);
    });

    test('syncNativeState shows the native failure reason', () async {
      await boot();
      native.state = {'value': 'error', 'error': 'core failed'};
      await n().syncNativeState();
      expect(st().connectionState, VpnState.error);
      expect(st().error, const AppMessage.text('core failed'));
    });

    test('stats poller updates traffic while connected', () async {
      await connected();
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await _settle();
      expect(stats().uploadBytes, 10);
      expect(stats().downloadSpeedBps, 2);
      c.read(vpnStatsProvider.notifier).pause();
    });

    test('with the chart on screen a tick is one call that also carries the history', () async {
      await connected();
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await _settle();
      c.read(vpnStatsProvider.notifier).pause();
      final polls = native.named('getStats');
      expect(polls, isNotEmpty);
      expect(polls.first.arguments, {'epoch': -1, 'since': 0});
      expect(stats().speedHistory.map((p) => p.uploadSpeed), [5]);
      // Only the catch-up when the polling started asks for the history on its own.
      expect(native.named('getStatsHistory'), hasLength(1));
    });

    test("a session connecting in the background doesn't start the stats polling", () async {
      await boot(configs: [_cfg('a')], activeId: 'a');
      c.read(vpnStatsProvider.notifier).pause();
      await n().connect();
      emit({'type': 'state', 'value': 'connected', 'socksPort': 2080, 'socksUser': 'su', 'socksPassword': 'sp'});
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await _settle();
      expect(native.named('getStats'), isEmpty);
      c.read(vpnStatsProvider.notifier).resume();
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await _settle();
      expect(stats().uploadBytes, 10);
      c.read(vpnStatsProvider.notifier).pause();
    });

    test('tunnel diag and log helpers', () async {
      await boot();
      await c.read(nativeLogsProvider).dumpTunnelDiag();
      expect(logs().last.message, 'tunnel diag: not running');
      await c.read(nativeLogsProvider).setLogsEnabled(false);
      await c.read(nativeLogsProvider).clear();
      expect(await c.read(nativeLogsProvider).getLogFilePath(), isNull);
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
        expect(st().error, const AppMessage(MessageCode.vpnConnectTimeout));
        expect(native.named('disconnect'), hasLength(1));
        c.dispose();
      });
    });

    test("a timed-out connect's late answer doesn't replace the timeout error", () {
      fakeAsync((async) {
        boot(configs: [_cfg('a')], activeId: 'a');
        async.flushMicrotasks();
        final gate = Completer<void>();
        // The VPN-permission dialog is still open; the timeout's disconnect makes native answer CANCELLED.
        native.onConnect = () async {
          await gate.future;
          throw PlatformException(code: 'CANCELLED', message: 'VPN start CANCELLED');
        };
        n().connect();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 46));
        expect(st().error, const AppMessage(MessageCode.vpnConnectTimeout));
        gate.complete();
        async.flushMicrotasks();
        expect(st().connectionState, VpnState.error);
        expect(st().error, const AppMessage(MessageCode.vpnConnectTimeout));
        c.dispose();
      });
    });

    test('an idle snapshot after a reconnect report keeps the pending connect bounded', () {
      fakeAsync((async) {
        boot(configs: [_cfg('a')], activeId: 'a');
        async.flushMicrotasks();
        n().connect();
        async.flushMicrotasks();
        final attempt = native.lastConnect()['attempt'] as int;
        // A resume sync sees the pending session reconnecting: the timeout is cancelled.
        native.state = {'value': 'reconnecting', 'attempt': attempt};
        n().syncNativeState();
        async.flushMicrotasks();
        // The service died: an idle untagged snapshot is rejected, the connect still ends.
        native.state = {'value': 'disconnected', 'attempt': 0};
        n().syncNativeState();
        async.flushMicrotasks();
        expect(st().connectionState, VpnState.connecting);
        async.elapse(const Duration(seconds: 46));
        expect(st().connectionState, VpnState.error);
        expect(st().error, const AppMessage(MessageCode.vpnConnectTimeout));
        c.dispose();
      });
    });

    test('a resume seeing the pending session still starting keeps the timeout', () {
      fakeAsync((async) {
        boot(configs: [_cfg('a')], activeId: 'a');
        async.flushMicrotasks();
        n().connect();
        async.flushMicrotasks();
        native.state = {'value': 'connecting', 'attempt': native.lastConnect()['attempt']};
        n().syncNativeState();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 46));
        expect(st().error, const AppMessage(MessageCode.vpnConnectTimeout));
        c.dispose();
      });
    });

    test('a timed-out switch shows the timeout over the running session, also through its stop', () {
      fakeAsync((async) {
        native.state = {
          'value': 'connected',
          'socksPort': 2080,
          'socksUser': 'su',
          'socksPassword': 'sp',
          'attempt': 3,
        };
        boot(configs: [_cfg('a')], activeId: 'a');
        async.flushMicrotasks();
        expect(st().isConnected, isTrue);
        // The VPN-permission dialog never answers.
        native.onConnect = () => Completer<void>().future;
        n().reconnectWithNewConfig();
        async.flushMicrotasks();
        final attempt = native.lastConnect()['attempt'];
        async.elapse(const Duration(seconds: 46));
        expect((st().connectionState, st().error), (VpnState.error, const AppMessage(MessageCode.vpnConnectTimeout)));
        expect(st().activeSocksPort, 0);
        // A late connected of the timed-out attempt, then the stop tagged with it.
        for (final v in ['connected', 'disconnected']) {
          native.state = {'value': v, 'socksPort': 2080, 'attempt': attempt};
          n().syncNativeState();
          async.flushMicrotasks();
          expect(
            (st().connectionState, st().error),
            (VpnState.error, const AppMessage(MessageCode.vpnConnectTimeout)),
            reason: v,
          );
          expect(c.read(tunnelSocksProvider), isNull);
        }
        c.dispose();
      });
    });

    test('the deadline returns when the pending session starts after a restart report', () {
      fakeAsync((async) {
        boot(configs: [_cfg('a')], activeId: 'a');
        async.flushMicrotasks();
        n().connect();
        async.flushMicrotasks();
        final attempt = native.lastConnect()['attempt'];
        // A switch stops the old session under the new attempt, then starts the new one.
        for (final v in ['reconnecting', 'connecting']) {
          native.state = {'value': v, 'attempt': attempt};
          n().syncNativeState();
          async.flushMicrotasks();
        }
        async.elapse(const Duration(seconds: 46));
        expect(st().error, const AppMessage(MessageCode.vpnConnectTimeout));
        c.dispose();
      });
    });

    test("a late failure of an earlier disconnect doesn't cancel a newer connect's deadline", () {
      fakeAsync((async) {
        boot(configs: [_cfg('a')], activeId: 'a');
        async.flushMicrotasks();
        n().connect();
        async.flushMicrotasks();
        final reply = Completer<void>();
        native.onDisconnect = () => reply.future;
        n().disconnect();
        async.flushMicrotasks();
        native.state = {'value': 'disconnected'};
        n().syncNativeState();
        async.flushMicrotasks();
        expect(st().connectionState, VpnState.disconnected);
        n().connect();
        async.flushMicrotasks();
        reply.completeError(PlatformException(code: 'X', message: 'late'));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 46));
        expect(st().error, const AppMessage(MessageCode.vpnConnectTimeout));
        c.dispose();
      });
    });

    test('native reconnect cycle cancels the connect timeout', () {
      fakeAsync((async) {
        boot(configs: [_cfg('a')], activeId: 'a');
        async.flushMicrotasks();
        n().connect();
        async.flushMicrotasks();
        native.state = {'value': 'reconnecting', 'attempt': native.lastConnect()['attempt']};
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
