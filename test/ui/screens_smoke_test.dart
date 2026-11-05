import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/services/config_storage_service.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/ui/screens/add_config_screen.dart';
import 'package:teapodstream/ui/screens/configs_screen.dart';
import 'package:teapodstream/ui/screens/dns_settings_screen.dart';
import 'package:teapodstream/ui/screens/home_screen.dart';
import 'package:teapodstream/ui/screens/logs_screen.dart';
import 'package:teapodstream/ui/screens/network_settings_screen.dart';
import 'package:teapodstream/ui/screens/profiles_screen.dart';
import 'package:teapodstream/ui/screens/routing_screen.dart';
import 'package:teapodstream/ui/screens/settings_screen.dart';
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
    testWidgets('${e.key} renders with empty data', (tester) async {
      await setUpScreenTest();
      final c = await pumpScreen(tester, e.value());
      expect(tester.takeException(), isNull);
      await unmount(tester, c);
    });

    testWidgets('${e.key} renders with configs and subscriptions', (tester) async {
      final native = await setUpScreenTest(
        settings: const AppSettings(splitTunnelingEnabled: true, includedPackages: {'b.app'}),
        configs: [testConfig('1', latency: 40), testConfig('2', subId: 's'), testConfig('3', subId: 's')],
        subscriptions: [
          Subscription(
            id: 's',
            name: 'My Sub',
            url: 'https://sub.example/x',
            createdAt: DateTime(2026),
            lastFetchedAt: DateTime(2026, 2),
            expireAt: DateTime(2027),
            uploadBytes: 1024,
            downloadBytes: 2048,
            totalBytes: 1 << 30,
            announce: 'Hello',
          ),
        ],
        activeId: '1',
      );
      native.logs = ['1700000000000|error|boom', '1700000000001|info|ok'];
      native.apps = [
        {'packageName': 'a.app', 'appName': 'Alpha'},
        {'packageName': 'b.app', 'appName': 'Beta', 'isSystem': true},
      ];
      final c = await pumpScreen(tester, e.value());
      expect(tester.takeException(), isNull);
      await unmount(tester, c);
    });
  }
}
