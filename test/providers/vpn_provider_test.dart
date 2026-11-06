import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teapodstream/core/constants/app_constants.dart';
import 'package:teapodstream/core/cores/core_backend.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/connection_fingerprint.dart';
import 'package:teapodstream/core/models/core_kind.dart';
import 'package:teapodstream/core/models/heartbeat_settings.dart';
import 'package:teapodstream/core/models/pinned_ref.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/models/vpn_log_entry.dart';
import 'package:teapodstream/core/services/config_storage_service.dart';
import 'package:teapodstream/core/services/log_service.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/protocols/xray/xray_rust_backend.dart';
import 'package:teapodstream/providers/config_provider.dart';
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

const _visionRaw = '{"outbounds":[{"tag":"proxy","protocol":"vless","settings":{"vnext":[{"address":'
    '"r.example","port":443,"users":[{"id":"11111111-2222-4333-8444-555555555555",'
    '"encryption":"none","flow":"xtls-rprx-vision"}]}]}}]}';

VpnConfig _cfg(String id,
        {String? subId, String password = 'p', DateTime? pingedAt, String? rawXray, String? host}) =>
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

/// Состояние нативной стороны и журнал вызовов.
class _Native {
  final calls = <MethodCall>[];
  Map<String, Object?> state = {'state': 'disconnected'};
  List<String> logs = [];

  /// host → задержка через `measureOutbound`; null — сервер мёртв.
  Map<String, int?> outboundMs = {};

  /// host → задержка TCP-пинга.
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
    messenger.setMockStreamHandler(
        _events, MockStreamHandler.inline(onListen: (_, sink) => native.sink = sink));
  });

  /// Без await: внутри fakeAsync завершается через flushMicrotasks.
  Future<void> boot({
    List<VpnConfig> configs = const [],
    String? activeId,
    List<PinnedRef> pins = const [],
    AppSettings settings = _settings,
  }) async {
    SharedPreferences.setMockInitialValues({'storage_migrated_v2': true});
    FlutterSecureStorage.setMockInitialValues({});
    await SettingsService().save(settings);
    final storage = ConfigStorageService();
    await storage.saveConfigs(configs);
    await storage.saveActiveConfigId(activeId);
    await storage.savePins(pins);
    final container = c = ProviderContainer();
    // Незавершённые fire-and-forget операции (syncActiveSettings) не должны
    // пережить контейнер.
    addTearDown(() async {
      await _settle();
      container.dispose();
    });
    await c.read(configProvider.future);
    await c.read(settingsProvider.future);
    c.listen(vpnProvider, (_, _) {});
    await _settle();
  }

  Future<void> connected({List<VpnConfig>? configs, AppSettings settings = _settings}) async {
    await boot(configs: configs ?? [_cfg('a')], activeId: (configs ?? [_cfg('a')]).first.id,
        settings: settings);
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
      await boot(configs: [_cfg('a', password: '')], activeId: 'a');
      await n().connect();
      expect(st().error, 'Пустой пароль');
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
          includedPackages: {'in'});
      await boot(configs: [_cfg('a')], activeId: 'a', settings: split);
      await n().connect();
      List<Object?> split3(Map<Object?, Object?> a) =>
          [a['vpnMode'], a['excludedPackages'], a['includedPackages']];
      expect(split3(native.lastConnect()), ['allExcept', ['ex'], []]);

      await boot(configs: [_cfg('a')], activeId: 'a', settings: split.copyWith(vpnMode: VpnMode.onlySelected));
      await n().connect();
      expect(split3(native.lastConnect()), ['onlySelected', [], ['in']]);

      await boot(configs: [_cfg('a')], activeId: 'a', settings: split.copyWith(splitTunnelingEnabled: false));
      await n().connect();
      expect(split3(native.lastConnect()), ['allExcept', [], []]);
    });

    test('vision flow forces QUIC blocking, also inside raw configs', () async {
      await boot(configs: [_vision('v')], activeId: 'v');
      await n().connect();
      expect(native.lastConnect()['blockQuic'], isTrue);

      await boot(configs: [_cfg('r', rawXray: _visionRaw)], activeId: 'r');
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
      await boot(configs: [_cfg('a')], activeId: 'a',
          settings: _settings.copyWith(coreOrder: [CoreKind.xrayRust, CoreKind.xrayGo, CoreKind.singBox]));
      await n().connect();
      expect(native.lastConnect()['engine'], 'rust');

      // proxy-only Rust не умеет — профиль уходит на следующее ядро.
      await boot(configs: [_cfg('a')], activeId: 'a',
          settings: _settings.copyWith(coreOrder: [CoreKind.xrayRust, CoreKind.xrayGo, CoreKind.singBox], proxyOnly: true));
      await n().connect();
      expect(native.lastConnect()['engine'], 'go');

      await boot(configs: [_cfg('r', rawXray: _visionRaw)], activeId: 'r',
          settings: _settings.copyWith(coreOrder: [CoreKind.xrayRust, CoreKind.xrayGo, CoreKind.singBox]));
      await n().connect();
      expect(native.lastConnect()['engine'], 'go');
    });

    test('a profile pinned to a core runs on it', () async {
      await boot(configs: [_cfg('a').copyWith(core: CoreKind.singBox)], activeId: 'a');
      await n().connect();
      expect(native.lastConnect()['engine'], 'box');
    });

    test('no enabled core can run the profile — refused before native', () async {
      await boot(configs: [_cfg('a')], activeId: 'a',
          settings: _settings.copyWith(
              proxyOnly: true, disabledCores: {CoreKind.xrayGo, CoreKind.singBox}));
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
      await connected(configs: [_cfg('a'), _cfg('bad', password: '')]);
      await c.read(configProvider.notifier).setActiveConfig('bad');
      await n().reconnectWithNewConfig();
      expect(st().isConnected, isTrue);
      expect(st().error, 'Пустой пароль');
      expect(native.named('connect'), hasLength(1));
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

    test('log events go to the log with level', () async {
      await boot();
      emit({'type': 'log', 'level': 'warning', 'message': 'w'});
      emit({'type': 'log', 'level': 'nonsense', 'message': 'i'});
      emit({'type': 'stats', 'upload': 1});
      native.sink!.success('not a map');
      await _settle();
      final tail = logs().reversed.take(2).toList().reversed.toList();
      expect(tail.map((e) => (e.level, e.message, e.source)),
          [(LogLevel.warning, 'w', 'xray'), (LogLevel.info, 'i', 'xray')]);
    });

    test('speed history: full replaces, delta appends only when it continues', () async {
      await connected();
      Map<String, Object?> pts(int n) => {'uploadSpeed': n, 'downloadSpeed': n};
      emit({'type': 'statsHistory', 'full': true, 'epoch': 1, 'seq': 3, 'history': [pts(1), pts(2), pts(3)]});
      await _settle();
      expect(st().stats.speedHistory.map((p) => p.uploadSpeed), [1, 2, 3]);

      emit({'type': 'statsHistory', 'epoch': 1, 'from': 3, 'seq': 4, 'history': [pts(4)]});
      await _settle();
      expect(st().stats.speedHistory.map((p) => p.uploadSpeed), [1, 2, 3, 4]);

      // Опоздавший ответ не задваивает точки и сбрасывает эпоху.
      emit({'type': 'statsHistory', 'epoch': 1, 'from': 3, 'seq': 4, 'history': [pts(4)]});
      emit({'type': 'statsHistory', 'epoch': 1, 'from': 4, 'seq': 5, 'history': [pts(5)]});
      await _settle();
      expect(st().stats.speedHistory, hasLength(4));

      emit({
        'type': 'statsHistory', 'full': true, 'epoch': 2, 'seq': 400,
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
    final subConfigs = [
      _cfg('a', subId: 's'),
      _cfg('b', subId: 's'),
      _cfg('c', subId: 's'),
      _cfg('d', subId: 'other'),
    ];

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
                failAction: HeartbeatFailAction.switchConfig, switchSource: SwitchSource.pinned)),
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
      expect(logs().last.message, contains('живых конфигов не найдено'));
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
      await boot(configs: [
        _cfg('a'),
        _cfg('b'),
        _cfg('raw', host: 'shared.example', rawXray: _visionRaw),
        _cfg('plain', host: 'shared.example'),
      ]);
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
      await boot(configs: [_cfg('fresh', pingedAt: DateTime.now()), _cfg('old')]);
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
      await c.read(settingsProvider.notifier)
          .save(_settings.copyWith(disabledCores: {CoreKind.xrayGo, CoreKind.singBox}));
      await _settle();
      expect(native.named('disconnect'), hasLength(1));
      expect(st().error, isNotNull);
    });

    test('idle switch saves or clears the quick-connect config', () async {
      await boot(configs: [_cfg('a')], activeId: 'a');
      await c.read(settingsProvider.notifier).save(_settings.copyWith(coreOrder: [CoreKind.xrayRust, CoreKind.xrayGo, CoreKind.singBox]));
      await _settle();
      expect((native.named('saveQuickConnect').single.arguments as Map)['engine'], 'rust');

      // Сырой конфиг Rust не берёт — ядро активного профиля не меняется.
      native.calls.clear();
      await boot(configs: [_cfg('r', rawXray: _visionRaw)], activeId: 'r');
      await c.read(settingsProvider.notifier).save(_settings.copyWith(coreOrder: [CoreKind.xrayRust, CoreKind.xrayGo, CoreKind.singBox]));
      await _settle();
      expect(native.named('saveQuickConnect'), isEmpty);
      expect(native.named('clearQuickConnect'), isEmpty);
      await c.read(settingsProvider.notifier)
          .save(_settings.copyWith(disabledCores: {CoreKind.xrayGo, CoreKind.singBox}));
      await _settle();
      expect(native.named('clearQuickConnect'), hasLength(1));
    });

    test('idle switch to sing-box saves a sing-box config or clears an unsupported one', () async {
      await boot(configs: [_cfg('a')], activeId: 'a');
      await c.read(settingsProvider.notifier)
          .save(_settings.copyWith(coreOrder: [CoreKind.singBox, CoreKind.xrayGo, CoreKind.xrayRust]));
      await _settle();
      final args = native.named('saveQuickConnect').single.arguments as Map;
      expect(args['engine'], 'box');
      final json = jsonDecode(args['xrayConfig'] as String) as Map<String, dynamic>;
      expect(((json['inbounds'] as List).first as Map)['type'], 'mixed');

      await boot(configs: [_cfg('r', rawXray: _visionRaw)], activeId: 'r');
      await c.read(settingsProvider.notifier)
          .save(_settings.copyWith(disabledCores: {CoreKind.xrayGo, CoreKind.xrayRust}));
      await _settle();
      expect(native.named('clearQuickConnect'), hasLength(1));
    });
  });

  group('misc', () {
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

  // В fakeAsync события EventChannel не доставляются (root-зона), MethodChannel — работает.
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
        // syncNativeState не знает, чей это connecting, и снимает таймаут.
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
