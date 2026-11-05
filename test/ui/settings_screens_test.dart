import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/models/profile.dart';
import 'package:teapodstream/core/models/routing_settings.dart';
import 'package:teapodstream/core/services/profile_storage_service.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/providers/profile_provider.dart';
import 'package:teapodstream/providers/settings_provider.dart';
import 'package:teapodstream/ui/screens/network_settings_screen.dart';
import 'package:teapodstream/ui/screens/routing_screen.dart';
import 'package:teapodstream/ui/screens/settings_screen.dart';

import '../helpers/ui_harness.dart';

Future<void> _tapRow(WidgetTester tester, String title) async {
  final row = find.text(title);
  await tester.scrollUntilVisible(row, 200, scrollable: find.byType(Scrollable).first);
  await tester.tap(row);
  await settle(tester);
}

AppSettings _settings(ProviderContainer c) => c.read(settingsProvider).value!;

void main() {
  group('network settings', () {
    testWidgets('toggles are saved', (tester) async {
      await setUpScreenTest();
      final c = await pumpScreen(tester, const NetworkSettingsScreen());
      expect(_settings(c).enableUdp, isTrue);
      await _tapRow(tester, 'UDP');
      expect(_settings(c).enableUdp, isFalse);
      await _tapRow(tester, 'Блокировать QUIC');
      expect(_settings(c).blockQuic, isTrue);
      await _tapRow(tester, 'Фрагментация');
      expect(_settings(c).fragment.enabled, isTrue);
      expect((await SettingsService().load()).fragment.enabled, isTrue);
      await unmount(tester, c);
    });

    testWidgets('fixed port reveals the port field', (tester) async {
      await setUpScreenTest();
      final c = await pumpScreen(tester, const NetworkSettingsScreen());
      expect(find.text('SOCKS5 порт'), findsNothing);
      await _tapRow(tester, 'Случайный порт');
      expect(_settings(c).randomPort, isFalse);
      expect(find.text('SOCKS5 порт'), findsOneWidget);
      await unmount(tester, c);
    });

    testWidgets('readonly profile locks the toggles', (tester) async {
      await setUpScreenTest();
      await ProfileStorageService().saveProfiles([
        Profile(id: 'ro', name: 'RO', readonly: true, settings: const AppSettings(), createdAt: DateTime(2026)),
      ]);
      await ProfileStorageService().saveActiveProfileId('ro');
      final c = await pumpScreen(tester, const NetworkSettingsScreen());
      c.listen(profileProvider, (_, _) {});
      await settle(tester);
      await _tapRow(tester, 'UDP');
      expect(_settings(c).enableUdp, isTrue);
      await unmount(tester, c);
    });
  });

  group('routing', () {
    testWidgets('toggles are saved; ad block is locked without geo data', (tester) async {
      await setUpScreenTest();
      final c = await pumpScreen(tester, const RoutingScreen());
      await _tapRow(tester, 'Kill Switch');
      expect(_settings(c).killSwitchEnabled, isTrue);
      await _tapRow(tester, 'Российские сервисы');
      expect(_settings(c).routing.ruServicesEnabled, isTrue);
      await _tapRow(tester, 'Блокировка рекламы');
      expect(_settings(c).routing.adBlockEnabled, isFalse);
      await unmount(tester, c);
    });

    testWidgets('rule sections appear only in bypass/only modes', (tester) async {
      await setUpScreenTest();
      var c = await pumpScreen(tester, const RoutingScreen());
      expect(find.text('Локальные сети'), findsNothing);
      await unmount(tester, c);

      await setUpScreenTest(
          settings: const AppSettings(routing: RoutingSettings(direction: RoutingDirection.bypass)));
      c = await pumpScreen(tester, const RoutingScreen());
      await _tapRow(tester, 'Локальные сети');
      expect(_settings(c).routing.bypassLocal, isTrue);
      await unmount(tester, c);
    });
  });

  group('settings', () {
    testWidgets('connection toggles are saved', (tester) async {
      await setUpScreenTest();
      final c = await pumpScreen(tester, const SettingsScreen());
      await _tapRow(tester, 'Автоподключение');
      expect(_settings(c).autoConnect, isTrue);
      await _tapRow(tester, 'Автоматизация');
      expect(_settings(c).automationEnabled, isTrue);
      await _tapRow(tester, 'Уведомление');
      expect(_settings(c).showNotification, isFalse);
      await unmount(tester, c);
    });

    testWidgets('navigates to sub-screens', (tester) async {
      await setUpScreenTest();
      final c = await pumpScreen(tester, const SettingsScreen());
      await _tapRow(tester, 'Сеть');
      expect(find.byType(NetworkSettingsScreen), findsOneWidget);
      await unmount(tester, c);
    });
  });
}
