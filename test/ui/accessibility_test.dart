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
import 'package:teapodstream/ui/widgets/breadcrumb_bar.dart';
import 'package:teapodstream/ui/widgets/pressable.dart';

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
