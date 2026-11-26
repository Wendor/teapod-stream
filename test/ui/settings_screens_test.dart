// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/models/core_kind.dart';
import 'package:teapodstream/core/models/profile.dart';
import 'package:teapodstream/core/models/routing_settings.dart';
import 'package:teapodstream/core/services/profile_storage_service.dart';
import 'package:teapodstream/core/models/app_settings.dart';
import 'package:teapodstream/core/services/update_service.dart';
import 'package:teapodstream/providers/profile_provider.dart';
import 'package:teapodstream/providers/settings_provider.dart';
import 'package:teapodstream/providers/update_provider.dart';
import 'package:teapodstream/ui/screens/network_settings_screen.dart';
import 'package:teapodstream/ui/screens/routing/routing_screen.dart';
import 'package:teapodstream/ui/screens/settings/settings_screen.dart';
import 'package:teapodstream/ui/screens/whats_new_screen.dart';
import 'package:teapodstream/ui/widgets/settings_shared.dart';

import '../helpers/stored_settings.dart';
import '../helpers/ui_harness.dart';

Future<void> _tapRow(WidgetTester tester, String title) async {
  final row = find.text(title);
  await tester.scrollUntilVisible(row, 200, scrollable: find.byType(Scrollable).first);
  await tester.tap(row);
  await settle(tester);
}

AppSettings _settings(ProviderContainer c) => c.read(settingsProvider).value!;

class _FixedUpdate extends UpdateNotifier {
  final UpdateState fixed;
  _FixedUpdate(this.fixed);

  @override
  UpdateState build() => fixed;
}

void main() {
  group('core picker', () {
    testWidgets('lists cores by priority with versions; ↑ and switches are saved', (tester) async {
      await setUpScreenTest();
      final c = await pumpScreen(tester, const SettingsScreen());
      for (final kind in CoreKind.values) {
        expect(find.text(kind.displayName), findsOneWidget, reason: kind.name);
      }
      expect(find.text('1.14.4'), findsOneWidget);

      // The language row pushes the core list below the fold.
      await tester.ensureVisible(find.bySemanticsLabel('move sing-box up'));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('move sing-box up'));
      await settle(tester);
      expect(_settings(c).coreOrder, [CoreKind.singBox, CoreKind.xrayGo, CoreKind.xrayRust]);

      Finder switchOf(CoreKind k) =>
          find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(SetSquareSwitch));
      await tester.ensureVisible(switchOf(CoreKind.xrayRust));
      await tester.tap(switchOf(CoreKind.singBox));
      await settle(tester);
      expect(_settings(c).disabledCores, {CoreKind.singBox});
      await tester.tap(switchOf(CoreKind.xrayGo));
      await settle(tester);
      await tester.tap(switchOf(CoreKind.xrayRust));
      await settle(tester);
      // The last enabled core can't be turned off.
      expect(_settings(c).disabledCores, {CoreKind.singBox, CoreKind.xrayGo});
      expect(find.text('At least one core must stay enabled'), findsOneWidget);
      await unmount(tester, c);
    });

    testWidgets('licenses row opens the license page', (tester) async {
      await setUpScreenTest();
      final c = await pumpScreen(tester, const SettingsScreen());
      final row = find.text('LICENSES');
      await tester.scrollUntilVisible(row, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(row);
      await settle(tester);
      expect(find.byType(LicensePage), findsOneWidget);
      await unmount(tester, c);
    });

    testWidgets('battery row opens the system battery optimization settings', (tester) async {
      final native = await setUpScreenTest();
      final c = await pumpScreen(tester, const SettingsScreen());
      final row = find.text('Battery optimization');
      await tester.scrollUntilVisible(row, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(row);
      await settle(tester);
      expect(native.named('openBatteryOptimizationSettings'), hasLength(1));
      await unmount(tester, c);
    });

    testWidgets('changelog row opens the release history in the app language', (tester) async {
      await setUpScreenTest();
      final c = await pumpScreen(tester, const SettingsScreen());
      final row = find.text('CHANGELOG');
      await tester.scrollUntilVisible(row, 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(row);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await settle(tester);
      expect(find.byType(WhatsNewScreen), findsOneWidget);
      expect(find.text('v1.8.0'), findsOneWidget);
      expect(find.text('v1.7.0'), findsNothing); // below the fold of the lazy list
      expect(find.textContaining('Fixed rare AmneziaWG'), findsOneWidget);
      await unmount(tester, c);
    });

    testWidgets('update tile lists the notes of every new version in the app language', (tester) async {
      await setUpScreenTest();
      const body = '### English\n\n- {v} en\n\n### Русский\n\n- {v} ru\n';
      final c = await pumpScreen(
        tester,
        ProviderScope(
          overrides: [
            updateProvider.overrideWith(
              () => _FixedUpdate(
                UpdateAvailable(
                  UpdateInfo(
                    version: '1.8.1',
                    downloadUrl: 'https://dl/a.apk',
                    notes: [
                      ReleaseNotes('1.8.1', body.replaceAll('{v}', '1.8.1')),
                      const ReleaseNotes('1.8.0', '- old style body'),
                    ],
                  ),
                ),
              ),
            ),
          ],
          child: const SettingsScreen(),
        ),
      );
      expect(find.text('- 1.8.1 en'), findsOneWidget);
      expect(find.textContaining('1.8.1 ru'), findsNothing);
      expect(find.text('- old style body'), findsOneWidget);
      expect(find.text('v1.8.0'), findsOneWidget);
      await unmount(tester, c);
    });
  });

  group('network settings', () {
    testWidgets('toggles are saved', (tester) async {
      await setUpScreenTest();
      final c = await pumpScreen(tester, const NetworkSettingsScreen());
      expect(_settings(c).enableUdp, isTrue);
      await _tapRow(tester, 'UDP');
      expect(_settings(c).enableUdp, isFalse);
      await _tapRow(tester, 'Block QUIC');
      expect(_settings(c).blockQuic, isTrue);
      await _tapRow(tester, 'Fragmentation');
      expect(_settings(c).fragment.enabled, isTrue);
      expect((await storedSettings()).fragment.enabled, isTrue);
      await unmount(tester, c);
    });

    testWidgets('fixed port reveals the port field', (tester) async {
      await setUpScreenTest();
      final c = await pumpScreen(tester, const NetworkSettingsScreen());
      expect(find.text('SOCKS5 port'), findsNothing);
      await _tapRow(tester, 'Random port');
      expect(_settings(c).randomPort, isFalse);
      expect(find.text('SOCKS5 port'), findsOneWidget);
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
      await _tapRow(tester, 'Russian services');
      expect(_settings(c).routing.ruServicesEnabled, isTrue);
      await _tapRow(tester, 'Ad blocking');
      expect(_settings(c).routing.adBlockEnabled, isFalse);
      await unmount(tester, c);
    });

    testWidgets('rule sections appear only in bypass/only modes', (tester) async {
      await setUpScreenTest();
      var c = await pumpScreen(tester, const RoutingScreen());
      expect(find.text('Local networks'), findsNothing);
      await unmount(tester, c);

      await setUpScreenTest(
        settings: const AppSettings(routing: RoutingSettings(direction: RoutingDirection.bypass)),
      );
      c = await pumpScreen(tester, const RoutingScreen());
      await _tapRow(tester, 'Local networks');
      expect(_settings(c).routing.bypassLocal, isTrue);
      await unmount(tester, c);
    });

    testWidgets('a custom geodata source is labelled from ARB', (tester) async {
      await setUpScreenTest(
        settings: const AppSettings(geoipUrl: 'https://geo.test/geoip.dat', geositeUrl: 'https://geo.test/geosite.dat'),
      );
      final c = await pumpScreen(tester, const RoutingScreen());
      await tester.scrollUntilVisible(find.text('Custom'), 200);
      expect(find.text('custom'), findsNothing);
      await unmount(tester, c);
    });
  });

  group('settings', () {
    testWidgets('connection toggles are saved', (tester) async {
      await setUpScreenTest();
      final c = await pumpScreen(tester, const SettingsScreen());
      await _tapRow(tester, 'Auto-connect');
      expect(_settings(c).autoConnect, isTrue);
      await _tapRow(tester, 'Automation');
      expect(_settings(c).automationEnabled, isTrue);
      await _tapRow(tester, 'Notification');
      expect(_settings(c).showNotification, isFalse);
      await unmount(tester, c);
    });

    testWidgets('navigates to sub-screens', (tester) async {
      await setUpScreenTest();
      final c = await pumpScreen(tester, const SettingsScreen());
      await _tapRow(tester, 'Network');
      expect(find.byType(NetworkSettingsScreen), findsOneWidget);
      await unmount(tester, c);
    });
  });
}
