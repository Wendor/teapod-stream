import 'dart:math';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/models/app_settings.dart';
import 'package:teapodstream/core/models/subscription.dart';
import 'package:teapodstream/ui/screens/add_config_screen.dart';
import 'package:teapodstream/ui/screens/configs/configs_screen.dart';
import 'package:teapodstream/ui/screens/dns_settings_screen.dart';
import 'package:teapodstream/ui/screens/home/home_screen.dart';
import 'package:teapodstream/ui/screens/logs_screen.dart';
import 'package:teapodstream/ui/screens/network_settings_screen.dart';
import 'package:teapodstream/ui/screens/profiles_screen.dart';
import 'package:teapodstream/ui/screens/routing/routing_screen.dart';
import 'package:teapodstream/ui/screens/settings/settings_screen.dart';
import 'package:teapodstream/ui/screens/split_tunnel_screen.dart';
import 'package:teapodstream/ui/screens/subscription_settings_screen.dart';
import 'package:teapodstream/ui/theme/app_colors.dart';
import 'package:teapodstream/ui/theme/app_theme.dart';
import 'package:teapodstream/ui/widgets/breadcrumb_bar.dart';
import 'package:teapodstream/ui/widgets/pressable.dart';
import 'package:teapodstream/ui/widgets/settings_shared.dart';

import '../helpers/ui_harness.dart';

/// The guideline skips nodes touching the screen's edge: full-width rows and the breadcrumb are measured directly.
void expectFullWidthRows() {
  for (final row in find.byWidgetPredicate((w) => w is Pressable || w is BreadcrumbBar).evaluate()) {
    expect(row.size!.height, greaterThanOrEqualTo(kMinInteractiveDimension), reason: '${row.widget}');
  }
}

void main() {
  final screens = <String, Widget Function()>{
    'home': () => const HomeScreen(),
    'configs': () => const ConfigsScreen(),
    'routing': () => const RoutingScreen(),
    'settings': () => const SettingsScreen(),
    'add config': () => const AddConfigScreen(),
    'dns': () => const DnsSettingsScreen(),
    'network': () => const NetworkSettingsScreen(),
    'subscriptions': () => const SubscriptionSettingsScreen(breadcrumbParent: 'settings'),
    'profiles': () => const ProfilesScreen(),
    'logs': () => const LogsScreen(),
    'split tunnel': () => const SplitTunnelScreen(),
  };

  for (final e in screens.entries) {
    testWidgets('${e.key}: tap targets are at least 48 dp and labeled', (tester) async {
      final handle = tester.ensureSemantics();
      await setUpScreenTest(
        settings: const AppSettings(splitTunnelingEnabled: true, includedPackages: {'b.app'}),
        configs: [
          testConfig('1', latency: 40),
          testConfig('2', subId: 's'),
        ],
      );
      final c = await pumpScreen(tester, e.value());
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expectFullWidthRows();
      await unmount(tester, c);
      handle.dispose();
    });
  }

  for (final brightness in Brightness.values) {
    for (final e in screens.entries) {
      testWidgets('${e.key}: text meets the AA contrast in the ${brightness.name} theme', (tester) async {
        final handle = tester.ensureSemantics();
        await setUpScreenTest(
          settings: const AppSettings(splitTunnelingEnabled: true, includedPackages: {'b.app'}),
          configs: [
            testConfig('1', latency: 40),
            testConfig('2', subId: 's'),
          ],
          activeId: '1',
        );
        final c = await pumpScreen(tester, e.value(), brightness: brightness);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await unmount(tester, c);
        handle.dispose();
      });
    }
  }

  test('text tokens reach 4.5:1 on each background of their theme, on the selection highlight and on tints', () {
    double contrast(Color a, Color b) {
      final (la, lb) = (a.computeLuminance(), b.computeLuminance());
      return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
    }

    for (final accent in AppColors.accentPresets) {
      for (final t in [TeapodTokens.dark(accent), TeapodTokens.light(accent)]) {
        for (final bg in [t.bg, t.bgElev, t.bgSunken]) {
          for (final fg in [t.textMuted, t.accent, t.danger, t.warning]) {
            expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: 'fg $fg on bg $bg');
          }
          // The logs level filter tints a selected tab in its own colour.
          for (final fg in [t.text, t.textDim, t.accent, t.danger, t.warning]) {
            final tint = Color.alphaBlend(fg.withAlpha(TeapodTokens.tintAlpha), bg);
            expect(contrast(fg, tint), greaterThanOrEqualTo(4.5), reason: 'fg $fg on its tint over $bg');
          }
          // An error or warning banner: danger text on a danger tint.
          final banner = Color.alphaBlend(t.danger.withAlpha(TeapodTokens.dangerSoftAlpha), bg);
          expect(contrast(t.danger, banner), greaterThanOrEqualTo(4.5), reason: 'danger on its banner over $bg');
          // A selected item: accentSoft over the background. textMuted isn't used there (textDim instead).
          final highlight = Color.alphaBlend(t.accentSoft, bg);
          for (final fg in [t.text, t.textDim, t.accent]) {
            expect(contrast(fg, highlight), greaterThanOrEqualTo(4.5), reason: 'fg $fg on highlight $highlight');
          }
        }
      }
    }
  });

  testWidgets('a row with onTap is announced as a button', (tester) async {
    final handle = tester.ensureSemantics();
    await setUpScreenTest();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.dark, AppColors.accentCyan),
        home: Column(
          children: [
            Pressable(onTap: () {}, child: const Text('tappable')),
            const Pressable(child: Text('static')),
            SetToggleRow(value: true, onTap: () {}, child: const Text('switch')),
            SetToggleRow(value: false, checkbox: true, onTap: () {}, child: const Text('box')),
          ],
        ),
      ),
    );
    expect(
      tester.getSemantics(find.text('tappable')),
      matchesSemantics(label: 'tappable', isButton: true, hasTapAction: true),
    );
    expect(tester.getSemantics(find.text('static')), matchesSemantics(label: 'static'));
    // A row with another role keeps it alone: not also a button.
    expect(
      tester.getSemantics(find.text('switch')),
      matchesSemantics(label: 'switch', hasToggledState: true, isToggled: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.text('box')),
      matchesSemantics(label: 'box', hasCheckedState: true, hasTapAction: true),
    );
    handle.dispose();
  });

  Future<void> expectGuidelines(WidgetTester tester) async {
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    expectFullWidthRows();
  }

  testWidgets('configs: a subscription group meets the guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await setUpScreenTest(
      configs: [
        testConfig('1'),
        testConfig('2', subId: 's'),
      ],
      subscriptions: [
        Subscription(
          id: 's',
          name: 'S',
          url: 'https://subs.example/x',
          createdAt: DateTime(2026),
          announce: 'News',
          announceUrl: 'https://subs.example/news',
        ),
      ],
    );
    final c = await pumpScreen(tester, const ConfigsScreen());
    await expectGuidelines(tester);
    await unmount(tester, c);
    handle.dispose();
  });

  testWidgets('profiles: the create dialog meets the guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await setUpScreenTest();
    final c = await pumpScreen(tester, const ProfilesScreen());
    await tester.tap(find.byIcon(Icons.add_rounded));
    await settle(tester);
    expect(find.byType(Dialog), findsOneWidget);
    await expectGuidelines(tester);
    await unmount(tester, c);
    handle.dispose();
  });

  testWidgets('home: the server picker sheet meets the guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await setUpScreenTest(configs: [testConfig('1'), testConfig('2')], activeId: '1');
    final c = await pumpScreen(tester, const HomeScreen());
    await tester.tap(find.bySemanticsLabel(RegExp('change server')));
    await settle(tester);
    await expectGuidelines(tester);
    await unmount(tester, c);
    handle.dispose();
  });
}
