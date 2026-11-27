// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/models/app_settings.dart';
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

import '../helpers/ui_harness.dart';

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
        configs: [testConfig('1', latency: 40), testConfig('2', subId: 's')],
      );
      final c = await pumpScreen(tester, e.value());
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await unmount(tester, c);
      handle.dispose();
    });
  }
}
