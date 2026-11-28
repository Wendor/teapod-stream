// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/models/subscription.dart';
import 'package:teapodstream/core/services/log_service.dart';
import 'package:teapodstream/providers/config_provider.dart';
import 'package:teapodstream/core/models/app_settings.dart';
import 'package:teapodstream/providers/settings_provider.dart';
import 'package:teapodstream/ui/screens/add_config_screen.dart';
import 'package:teapodstream/ui/screens/configs/configs_screen.dart';
import 'package:teapodstream/ui/screens/dns_settings_screen.dart';
import 'package:teapodstream/ui/screens/home/home_screen.dart';
import 'package:teapodstream/ui/screens/logs_screen.dart';
import 'package:teapodstream/ui/screens/profiles_screen.dart';
import 'package:teapodstream/ui/screens/split_tunnel_screen.dart';

import '../helpers/ui_harness.dart';

/// Opens [screen] on top of an empty route so Navigator.pop has somewhere to return.
class _Launcher extends StatelessWidget {
  final Widget screen;
  const _Launcher(this.screen);

  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextButton(
      onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen)),
      child: const Text('open'),
    ),
  );
}

Future<ProviderContainer> _open(WidgetTester tester, Widget screen) async {
  final c = await pumpScreen(tester, _Launcher(screen));
  // As in the app: the config list is already loaded by the screen it was opened from.
  c.listen(configProvider, (_, _) {});
  await settle(tester);
  await tester.tap(find.text('open'));
  await settle(tester);
  return c;
}

void main() {
  final sub = Subscription(id: 's', name: 'My Sub', url: 'https://sub.example/x', createdAt: DateTime(2026));

  testWidgets('home shows the active server and connect calls native', (tester) async {
    final native = await setUpScreenTest(configs: [testConfig('1')], activeId: '1');
    final c = await pumpScreen(tester, const HomeScreen());
    expect(find.textContaining('Server 1'), findsWidgets);
    final semantics = tester.ensureSemantics();
    await tester.tap(find.bySemanticsLabel(RegExp('^connect')));
    semantics.dispose();
    await settle(tester);
    expect(native.named('connect'), hasLength(1));
    await unmount(tester, c);
  });

  group('home says the session state in words', () {
    final cases = <String, (Map<String, Object?>, List<Pattern>)>{
      'connected': ({'value': 'connected'}, ['Connected', RegExp(r'^\d\d:\d\d:\d\d · ')]),
      'connecting': ({'value': 'connecting'}, ['Connecting', 'establishing connection…']),
      'disconnecting': ({'value': 'disconnecting'}, ['Disconnecting', 'closing session…']),
      'disconnected': ({'value': 'disconnected'}, ['Not connected', 'tap to connect']),
      'error': (
        {'value': 'error', 'error': 'handshake timed out'},
        ['Connection failed', 'handshake timed out', 'tap to retry'],
      ),
      // A long reason is bounded on its own: the retry prompt stays a line of its own.
      'error with a long reason': (
        {'value': 'error', 'error': 'one\ntwo\nthree\nfour'},
        ['Connection failed', 'one\ntwo\nthree\nfour', 'tap to retry'],
      ),
      'error without a reason': ({'value': 'error'}, ['Connection failed', 'tap to retry']),
      'blocked': (
        {'value': 'blocked', 'error': 'tunnel lost'},
        [
          'Traffic blocked',
          'The kill switch holds traffic until the VPN connects. Disconnect to go online without the VPN.',
          'tunnel lost',
        ],
      ),
    };
    for (final MapEntry(key: name, value: (state, texts)) in cases.entries) {
      testWidgets(name, (tester) async {
        final native = await setUpScreenTest(configs: [testConfig('1')], activeId: '1');
        native.state = state;
        final c = await pumpScreen(tester, const HomeScreen());
        for (final text in texts) {
          expect(
            text is RegExp ? find.textContaining(text) : find.text(text as String),
            findsOneWidget,
            reason: '$text',
          );
        }
        // No status codes on Home.
        expect(find.textContaining('sys.state'), findsNothing);
        expect(find.textContaining(RegExp('ONLINE|OFFLINE|HANDSHAKE|SHUTDOWN|BLOCKED')), findsNothing);
        if (name == 'blocked') expect(find.text('DISCONNECT'), findsOneWidget);
        await unmount(tester, c);
      });
    }

    testWidgets('ping and traffic say what they measure', (tester) async {
      await setUpScreenTest(configs: [testConfig('1', latency: 42)], activeId: '1');
      final c = await pumpScreen(tester, const HomeScreen());
      expect(find.text('PING TO SERVER'), findsOneWidget);
      expect(find.text('TRAFFIC — THIS SESSION'), findsOneWidget);
      expect(find.text('peak ↓ 0.0 Mbit/s'), findsOneWidget);
      await unmount(tester, c);
    });
  });

  testWidgets('configs screen lists standalone configs and subscriptions', (tester) async {
    await setUpScreenTest(
      configs: [
        testConfig('1'),
        testConfig('2', subId: 's'),
      ],
      subscriptions: [sub],
      activeId: '1',
    );
    final c = await pumpScreen(tester, const ConfigsScreen());
    expect(find.text('total [03]'), findsOneWidget);
    expect(find.text('My Sub'), findsOneWidget);
    // [local] is expanded by default, subscriptions are collapsed; a tap collapses.
    expect(find.text('Server 1'), findsOneWidget);
    expect(find.text('Server 2'), findsNothing);
    await tester.tap(find.text('[local]'));
    await settle(tester);
    expect(find.text('Server 1'), findsNothing);
    await unmount(tester, c);
  });

  group('add config', () {
    testWidgets('a valid URI is added, selected and the screen closes', (tester) async {
      await setUpScreenTest();
      final c = await _open(tester, const AddConfigScreen());
      await tester.enterText(find.byType(TextField), 'trojan://pw@new.example:443?security=tls#Fresh');
      await tester.tap(find.text('ADD'));
      await settle(tester);
      await settle(tester);
      final state = c.read(configProvider).value!;
      expect(state.configs.single.name, 'Fresh');
      expect(state.activeConfigId, state.configs.single.id);
      expect(find.byType(AddConfigScreen), findsNothing);
      await unmount(tester, c);
    });

    testWidgets('empty and unknown input show errors', (tester) async {
      await setUpScreenTest();
      final c = await _open(tester, const AddConfigScreen());
      await tester.tap(find.text('ADD'));
      await settle(tester);
      expect(find.text('Enter a URL'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'wireguard://nope');
      await tester.tap(find.text('ADD'));
      await settle(tester);
      expect(find.textContaining("Couldn't recognize"), findsOneWidget);
      expect(c.read(configProvider).value!.configs, isEmpty);
      await unmount(tester, c);
    });

    testWidgets('compact connections deeplink imports its configs', (tester) async {
      await setUpScreenTest();
      final c = await _open(tester, const AddConfigScreen());
      await tester.enterText(
        find.byType(TextField),
        'teapod://import/connections?data='
        'eyJ2ZXJzaW9uIjoxLCJleHBvcnRlZEF0IjoiMjAyNi0wMS0wMVQwMDowMDowMC4wMDAiLCJjb25maWdzIjpbInRyb2phbjovL3B3QGEuZXhhbXBsZTo0NDMjQSJdLCJzdWJzY3JpcHRpb25zIjpbXX0',
      );
      await tester.tap(find.text('ADD'));
      await settle(tester);
      expect(c.read(configProvider).value!.configs.single.address, 'a.example');
      await unmount(tester, c);
    });
  });

  testWidgets('dns screen saves the chosen preset', (tester) async {
    await setUpScreenTest();
    final c = await _open(tester, const DnsSettingsScreen());
    await tester.tap(find.text('Google (DoH)'));
    await tester.pump();
    await tester.tap(find.text('SAVE'));
    await settle(tester);
    expect(c.read(settingsProvider).value!.dnsPreset, 'google_doh');
    await unmount(tester, c);
  });

  testWidgets('logs screen shows entries and the empty state', (tester) async {
    await setUpScreenTest();
    final c = await pumpScreen(tester, const LogsScreen());
    expect(find.text('[ stream empty ]'), findsOneWidget);
    c.read(logServiceProvider.notifier)
      ..addError('boom happened')
      ..addInfo('all good');
    await settle(tester);
    expect(find.textContaining('boom happened'), findsOneWidget);
    expect(find.textContaining('all good'), findsOneWidget);
    await unmount(tester, c);
  });

  testWidgets('split tunnel lists installed apps ignoring case', (tester) async {
    final native = await setUpScreenTest();
    native.apps = [
      {'packageName': 'z.app', 'appName': 'Zoom'},
      {'packageName': 'e.app', 'appName': 'eBay'},
      {'packageName': 'a.app', 'appName': 'Alpha'},
    ];
    final c = await pumpScreen(tester, const SplitTunnelScreen());
    final ys = [
      for (final n in ['Alpha', 'eBay', 'Zoom']) tester.getTopLeft(find.text(n)).dy,
    ];
    expect(ys, orderedEquals([...ys]..sort()), reason: 'sorted ignoring case');
    await unmount(tester, c);
  });

  testWidgets('an app tapped right after a mode switch goes to that mode\'s list', (tester) async {
    final native = await setUpScreenTest(settings: const AppSettings(splitTunnelingEnabled: true));
    native.apps = [
      {'packageName': 'a.app', 'appName': 'Alpha'},
    ];
    final c = await pumpScreen(tester, const SplitTunnelScreen());
    // No pump between the taps: the app row still renders the default "only selected" mode.
    await tester.tap(find.text('EXCEPT').last);
    await tester.tap(find.text('Alpha'));
    await settle(tester);
    final s = c.read(settingsProvider).value!;
    expect(s.vpnMode, VpnMode.allExcept);
    expect(s.excludedPackages, {'a.app'});
    expect(s.includedPackages, isEmpty);
    await unmount(tester, c);
  });

  testWidgets('profiles screen shows the default profile', (tester) async {
    await setUpScreenTest();
    final c = await pumpScreen(tester, const ProfilesScreen());
    expect(find.textContaining('Default'), findsWidgets);
    expect(find.text('ACTIVE'), findsOneWidget);
    await unmount(tester, c);
  });
}
