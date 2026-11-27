import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teapodstream/core/constants/app_constants.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/app_settings.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/models/vpn_stats.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/providers/app_lifecycle_provider.dart';
import 'package:teapodstream/providers/auto_switch_provider.dart';
import 'package:teapodstream/providers/config_provider.dart';
import 'package:teapodstream/providers/geo_provider.dart';
import 'package:teapodstream/providers/native_logs_provider.dart';
import 'package:teapodstream/providers/ping_provider.dart';
import 'package:teapodstream/providers/update_provider.dart';
import 'package:teapodstream/providers/vpn_provider.dart';
import 'package:teapodstream/providers/vpn_stats_provider.dart';

const _events = EventChannel('${AppConstants.methodChannel}/events');

/// Every step the lifecycle notifier takes, in order.
final _log = <String>[];

late Completer<void> _restored;
late Completer<void> _synced;
var _vpn = const VpnState2();
var _configs = <VpnConfig>[];

VpnConfig _cfg(String id) => VpnConfig(
  id: id,
  name: id,
  protocol: VpnProtocol.trojan,
  address: 'h$id',
  port: 443,
  uuid: '',
  password: 'p',
  security: VpnSecurity.tls,
  transport: VpnTransport.tcp,
  createdAt: DateTime(2026),
);

class _Logs extends NativeLogs {
  _Logs(super.ref);

  @override
  Future<void> restore() {
    _log.add('restore');
    return _restored.future;
  }
}

class _Vpn extends VpnNotifier {
  @override
  VpnState2 build() => _vpn;

  @override
  Future<void> get synced => _synced.future;

  @override
  Future<void> syncNativeState() async {
    _log.add('sync');
    await _synced.future;
  }

  @override
  Future<void> connect({bool switching = false}) async => _log.add('connect');
}

class _Configs extends ConfigNotifier {
  @override
  Future<ConfigState> build() async => ConfigState(configs: _configs);

  @override
  Future<void> refreshStaleIfDue() async => _log.add('refresh');

  void add(VpnConfig c) => state = AsyncData(ConfigState(configs: [...?state.value?.configs, c]));
}

class _Ping extends PingNotifier {
  @override
  Future<void> pingStale() async => _log.add('ping');
}

class _Geo extends GeoNotifier {
  @override
  GeoState build() => GeoMissing();

  @override
  Future<void> check() async => _log.add('geo');
}

class _Update extends UpdateNotifier {
  @override
  Future<void> checkForUpdate() async => _log.add('update');
}

class _Stats extends VpnStatsNotifier {
  @override
  VpnStats build() => const VpnStats();

  @override
  void resume() => _log.add('stats resume');

  @override
  void pause() => _log.add('stats pause');

  @override
  void setChartVisible(bool visible) => _log.add('chart $visible');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ProviderContainer c;
  VpnConfig? effective;

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    messenger.setMockStreamHandler(_events, MockStreamHandler.inline(onListen: (_, _) {}));
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    _log.clear();
    _restored = Completer();
    _synced = Completer();
    _vpn = const VpnState2();
    _configs = [_cfg('a')];
    effective = _configs.first;
    await SettingsService().save(const AppSettings(autoConnect: true));
    c = ProviderContainer(
      overrides: [
        nativeLogsProvider.overrideWith(_Logs.new),
        vpnProvider.overrideWith(_Vpn.new),
        configProvider.overrideWith(_Configs.new),
        effectiveConfigProvider.overrideWith((ref) => effective),
        pingProvider.overrideWith(_Ping.new),
        geoProvider.overrideWith(_Geo.new),
        updateProvider.overrideWith(_Update.new),
        vpnStatsProvider.overrideWith(_Stats.new),
        autoSwitchProvider.overrideWith((ref) {
          _log.add('autoSwitch');
          return AutoSwitch(ref);
        }),
      ],
    );
    addTearDown(c.dispose);
  });

  group('start', () {
    test('the subscription refresh waits for both the VPN sync and the log restore', () async {
      final started = c.read(appLifecycleProvider.notifier).start();
      await settle();
      expect(_log, ['restore', 'autoSwitch', 'ping', 'geo', 'connect']);

      _synced.complete();
      await settle();
      expect(_log, isNot(contains('refresh')), reason: 'the log restore is still running');

      _restored.complete();
      await started;
      expect(_log.last, 'refresh');
    });

    test('a failed log restore still lets the refresh run', () async {
      final started = c.read(appLifecycleProvider.notifier).start();
      _synced.complete();
      _restored.completeError(StateError('channel'));
      await started;
      expect(_log, contains('refresh'));
    });

    test('runs once', () async {
      _synced.complete();
      _restored.complete();
      final lifecycle = c.read(appLifecycleProvider.notifier);
      await lifecycle.start();
      final steps = [..._log];
      await lifecycle.start();
      expect(_log, steps);
    });

    test('auto-connect needs autoConnect on', () async {
      await SettingsService().save(const AppSettings());
      _synced.complete();
      _restored.complete();
      await c.read(appLifecycleProvider.notifier).start();
      expect(_log, isNot(contains('connect')));
    });

    test('auto-connect needs a config to run', () async {
      effective = null;
      _synced.complete();
      _restored.complete();
      await c.read(appLifecycleProvider.notifier).start();
      expect(_log, isNot(contains('connect')));
    });

    test('auto-connect leaves a VPN that is already up alone', () async {
      _vpn = const VpnState2(connectionState: VpnState.connected);
      _synced.complete();
      _restored.complete();
      await c.read(appLifecycleProvider.notifier).start();
      expect(_log, isNot(contains('connect')));
    });

    test('the update check comes after a delay, while no update is in progress', () {
      fakeAsync((async) {
        _synced.complete();
        _restored.complete();
        c.read(appLifecycleProvider.notifier).start();
        async.elapse(AppLifecycleNotifier.updateCheckDelay - const Duration(milliseconds: 1));
        expect(_log, isNot(contains('update')));
        async.elapse(const Duration(milliseconds: 1));
        expect(_log, contains('update'));
      });
    });
  });

  test('resumed: stats polling restarts, the refresh waits for the sync', () async {
    final resumed = c.read(appLifecycleProvider.notifier).resumed();
    await settle();
    expect(_log, ['stats resume', 'sync']);
    _synced.complete();
    await resumed;
    expect(_log, ['stats resume', 'sync', 'refresh']);
  });

  test('paused stops the stats polling', () {
    c.read(appLifecycleProvider.notifier).paused();
    expect(_log, ['stats pause']);
  });

  test('added configs are pinged; the chart follows the home tab', () async {
    c.listen(appLifecycleProvider, (_, _) {});
    await c.read(configProvider.future);
    await settle();
    _log.clear();

    (c.read(configProvider.notifier) as _Configs).add(_cfg('b'));
    await settle();
    expect(_log, ['ping']);

    c.read(tabIndexProvider.notifier).set(1);
    c.read(tabIndexProvider.notifier).set(0);
    expect(_log, ['ping', 'chart false', 'chart true']);
  });
}
