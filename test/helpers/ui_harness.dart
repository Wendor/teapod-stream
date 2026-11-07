import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teapodstream/core/constants/app_constants.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/services/config_storage_service.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/ui/theme/app_colors.dart';
import 'package:teapodstream/ui/theme/app_theme.dart';

/// Нативная сторона для widget-тестов: журнал вызовов и простые ответы.
class FakeNative {
  final calls = <MethodCall>[];
  Map<String, Object?> state = {'state': 'disconnected'};
  List<Map<String, Object?>> apps = [];
  List<String> logs = [];

  List<MethodCall> named(String m) => calls.where((c) => c.method == m).toList();

  Object? handle(MethodCall call) {
    calls.add(call);
    return switch (call.method) {
      'getState' => state,
      'getLogs' => logs,
      'getInstalledApps' => apps,
      'getAvailableEngines' => ['go', 'rust', 'box'],
      'getBinaryVersions' => {'xray': '26.1.1', 'xray-go': '26.1.1', 'xray-rust': '0.9.0', 'sing-box': '1.14.4', 'tun2socks': '1.7.3'},
      'getFilesDir' => '',
      'getAbi' => 'arm64-v8a',
      _ => null,
    };
  }
}

VpnConfig testConfig(String id, {String? subId, int? latency}) => VpnConfig(
      id: id,
      name: 'Server $id',
      protocol: VpnProtocol.trojan,
      address: 'h$id.example',
      port: 443,
      uuid: '',
      password: 'p',
      security: VpnSecurity.tls,
      transport: VpnTransport.tcp,
      createdAt: DateTime(2026),
      subscriptionId: subId,
      latencyMs: latency,
      rawUri: 'trojan://p@h$id.example:443#Server%20$id',
    );

/// Мокает каналы, хранилища и данные; возвращает нативную заглушку.
Future<FakeNative> setUpScreenTest({
  AppSettings settings = const AppSettings(),
  List<VpnConfig> configs = const [],
  List<Subscription> subscriptions = const [],
  String? activeId,
}) async {
  final native = FakeNative();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
      const MethodChannel(AppConstants.methodChannel), (call) async => native.handle(call));
  messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'), (call) async => <int, int>{17: 1});
  messenger.setMockStreamHandler(const EventChannel('${AppConstants.methodChannel}/events'),
      MockStreamHandler.inline(onListen: (_, _) {}));
  PackageInfo.setMockInitialValues(
      appName: 'TeapodStream', packageName: 'p', version: '1.7.3', buildNumber: '1', buildSignature: '');
  SharedPreferences.setMockInitialValues({'storage_migrated_v2': true});
  FlutterSecureStorage.setMockInitialValues({});
  await SettingsService().save(settings);
  final storage = ConfigStorageService();
  await storage.saveConfigs(configs);
  await storage.saveSubscriptions(subscriptions);
  await storage.saveActiveConfigId(activeId);
  return native;
}

/// Рендерит [screen] в теме приложения. Возвращает контейнер для проверок состояния.
Future<ProviderContainer> pumpScreen(WidgetTester tester, Widget screen) async {
  // Тестовый шрифт шире реального: на узком экране переполнения были бы ложными.
  tester.view.physicalSize = const Size(1500, 3000);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  final container = ProviderContainer();
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.build(Brightness.dark, AppColors.accentCyan),
      home: screen,
    ),
  ));
  await settle(tester);
  return container;
}

/// Несколько кадров: моки хранилищ и каналов завершаются в fake-async.
/// Без runAsync — иначе google_fonts реально пошёл бы в сеть за шрифтами.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Размонтирует дерево (dispose контейнера снимает таймеры провайдеров).
Future<void> unmount(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
  await tester.pump(const Duration(seconds: 1));
}
