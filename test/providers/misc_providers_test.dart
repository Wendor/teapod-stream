import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teapodstream/core/constants/app_constants.dart';
import 'package:teapodstream/core/models/core_kind.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/providers/app_icon_provider.dart';
import 'package:teapodstream/providers/app_info_provider.dart';
import 'package:teapodstream/providers/apps_provider.dart';
import 'package:teapodstream/providers/core_provider.dart';
import 'package:teapodstream/providers/settings_provider.dart';
import 'package:teapodstream/providers/theme_provider.dart';
import 'package:teapodstream/ui/theme/app_colors.dart';

const _channel = MethodChannel(AppConstants.methodChannel);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late Object? Function(MethodCall) reply;
  late ProviderContainer c;

  setUp(() async {
    calls.clear();
    reply = (_) => null;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return reply(call);
    });
    SharedPreferences.setMockInitialValues({'storage_migrated_v2': true});
    FlutterSecureStorage.setMockInitialValues({});
    c = ProviderContainer();
    addTearDown(c.dispose);
  });

  group('installedAppsProvider', () {
    test('sorts by name ignoring case and marks excluded packages', () async {
      await SettingsService().save(const AppSettings(excludedPackages: {'b.pkg'}));
      await c.read(settingsProvider.future);
      reply = (_) => [
            {'packageName': 'b.pkg', 'appName': 'Zeta', 'isSystem': true},
            {'packageName': 'e.pkg', 'appName': 'eBay'},
            {'packageName': 'a.pkg'},
          ];
      final apps = await c.read(installedAppsProvider.future);
      // Без учёта регистра: «eBay» не уезжает в конец за «Zeta».
      expect(apps.map((a) => a.appName), ['a.pkg', 'eBay', 'Zeta']);
      expect(apps.last.isExcluded, isTrue);
      expect(apps.last.isSystem, isTrue);
      expect(apps.first.isExcluded, isFalse);
    });

    test('native error or null gives an empty list', () async {
      expect(await c.read(installedAppsProvider.future), isEmpty);
      reply = (_) => throw PlatformException(code: 'X');
      c.invalidate(installedAppsProvider);
      expect(await c.read(installedAppsProvider.future), isEmpty);
    });
  });

  test('appIconProvider caches icons across containers', () async {
    reply = (_) => Uint8List.fromList([1, 2, 3]);
    expect(await c.read(appIconProvider('x.pkg').future), [1, 2, 3]);
    final other = ProviderContainer();
    addTearDown(other.dispose);
    expect(await other.read(appIconProvider('x.pkg').future), [1, 2, 3]);
    expect(calls.where((m) => m.method == 'getAppIcon'), hasLength(1));
    expect(calls.single.arguments, {'packageName': 'x.pkg'});

    reply = (_) => throw PlatformException(code: 'X');
    expect(await c.read(appIconProvider('y.pkg').future), isNull);
  });

  test('appVersionProvider prefixes v', () async {
    PackageInfo.setMockInitialValues(
        appName: 'a', packageName: 'p', version: '1.2.3', buildNumber: '1', buildSignature: '');
    expect(await c.read(appVersionProvider.future), 'v1.2.3');
  });

  group('theme', () {
    test('defaults to dark and cyan', () async {
      expect(c.read(themeModeProvider), ThemeMode.dark);
      expect(c.read(accentProvider), AppColors.accentCyan);
    });

    test('loads saved values', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'light', 'accent_color': 0xFF112233});
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      c2.listen(themeModeProvider, (_, _) {});
      c2.listen(accentProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(c2.read(themeModeProvider), ThemeMode.light);
      expect(c2.read(accentProvider), const Color(0xFF112233));
    });

    test('system mode and set persist', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'system'});
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      c2.listen(themeModeProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(c2.read(themeModeProvider), ThemeMode.system);

      await c2.read(themeModeProvider.notifier).set(ThemeMode.light);
      await c2.read(accentProvider.notifier).set(const Color(0xFF00FF00));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), 'light');
      expect(prefs.getInt('accent_color'), 0xFF00FF00);
      expect(c2.read(accentProvider), const Color(0xFF00FF00));
    });
  });

  group('core providers', () {
    test('coreBackendFor maps every kind', () {
      for (final k in CoreKind.values) {
        expect(coreBackendFor(k).kind, k);
      }
    });

    test('coreResolverProvider follows settings and device cores', () async {
      reply = (_) => ['rust', 'go', 'box'];
      await c.read(availableCoresProvider.future);
      await c.read(settingsProvider.future);
      expect(c.read(coreResolverProvider).primary, CoreKind.xrayGo);
      await c.read(settingsProvider.notifier).save(
          const AppSettings(coreOrder: [CoreKind.xrayRust, CoreKind.xrayGo, CoreKind.singBox]));
      expect(c.read(coreResolverProvider).primary, CoreKind.xrayRust);
      reply = (_) => ['go'];
      c.invalidate(availableCoresProvider);
      await c.read(availableCoresProvider.future);
      expect(c.read(coreResolverProvider).usable, [CoreKind.xrayGo]);
      await Future<void>.delayed(Duration.zero);
    });

    test('availableCoresProvider reads native engines', () async {
      reply = (_) => ['rust', 'go', 'unknown'];
      expect(await c.read(availableCoresProvider.future), {CoreKind.xrayGo, CoreKind.xrayRust});
      reply = (_) => throw PlatformException(code: 'X');
      c.invalidate(availableCoresProvider);
      expect(await c.read(availableCoresProvider.future), {CoreKind.xrayGo});
      reply = (_) => null;
      c.invalidate(availableCoresProvider);
      expect(await c.read(availableCoresProvider.future), isEmpty);
    });
  });
}
