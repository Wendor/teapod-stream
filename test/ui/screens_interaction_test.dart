import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/services/config_storage_service.dart';
import 'package:teapodstream/core/services/log_service.dart';
import 'package:teapodstream/providers/config_provider.dart';
import 'package:teapodstream/providers/settings_provider.dart';
import 'package:teapodstream/ui/screens/add_config_screen.dart';
import 'package:teapodstream/ui/screens/configs_screen.dart';
import 'package:teapodstream/ui/screens/dns_settings_screen.dart';
import 'package:teapodstream/ui/screens/home_screen.dart';
import 'package:teapodstream/ui/screens/logs_screen.dart';
import 'package:teapodstream/ui/screens/profiles_screen.dart';
import 'package:teapodstream/ui/screens/split_tunnel_screen.dart';

import '../helpers/ui_harness.dart';

/// Открывает [screen] поверх пустого маршрута, чтобы Navigator.pop было куда возвращаться.
class _Launcher extends StatelessWidget {
  final Widget screen;
  const _Launcher(this.screen);

  @override
  Widget build(BuildContext context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
          child: const Text('open'),
        ),
      );
}

Future<ProviderContainer> _open(WidgetTester tester, Widget screen) async {
  final c = await pumpScreen(tester, _Launcher(screen));
  // Как в приложении: список конфигов уже загружен экраном, с которого открыли.
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
    await tester.tap(find.bySemanticsLabel(RegExp('^подключить')));
    semantics.dispose();
    await settle(tester);
    expect(native.named('connect'), hasLength(1));
    await unmount(tester, c);
  });

  testWidgets('configs screen lists standalone configs and subscriptions', (tester) async {
    await setUpScreenTest(
      configs: [testConfig('1'), testConfig('2', subId: 's')],
      subscriptions: [sub],
      activeId: '1',
    );
    final c = await pumpScreen(tester, const ConfigsScreen());
    expect(find.text('total [03]'), findsOneWidget);
    expect(find.text('My Sub'), findsOneWidget);
    // Группы свёрнуты; раскрытие показывает конфиги.
    expect(find.text('Server 1'), findsNothing);
    await tester.tap(find.text('[local]'));
    await settle(tester);
    expect(find.text('Server 1'), findsOneWidget);
    await unmount(tester, c);
  });

  group('add config', () {
    testWidgets('a valid URI is added, selected and the screen closes', (tester) async {
      await setUpScreenTest();
      final c = await _open(tester, const AddConfigScreen());
      await tester.enterText(find.byType(TextField), 'trojan://pw@new.example:443?security=tls#Fresh');
      await tester.tap(find.text('ДОБАВИТЬ'));
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
      await tester.tap(find.text('ДОБАВИТЬ'));
      await settle(tester);
      expect(find.text('Введите URL'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'wireguard://nope');
      await tester.tap(find.text('ДОБАВИТЬ'));
      await settle(tester);
      expect(find.textContaining('Не удалось распознать'), findsOneWidget);
      expect(c.read(configProvider).value!.configs, isEmpty);
      await unmount(tester, c);
    });

    testWidgets('compact connections deeplink imports its configs', (tester) async {
      await setUpScreenTest();
      final c = await _open(tester, const AddConfigScreen());
      await tester.enterText(
          find.byType(TextField),
          'teapod://import/connections?data='
          'eyJ2ZXJzaW9uIjoxLCJleHBvcnRlZEF0IjoiMjAyNi0wMS0wMVQwMDowMDowMC4wMDAiLCJjb25maWdzIjpbInRyb2phbjovL3B3QGEuZXhhbXBsZTo0NDMjQSJdLCJzdWJzY3JpcHRpb25zIjpbXX0');
      await tester.tap(find.text('ДОБАВИТЬ'));
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
    await tester.tap(find.text('СОХРАНИТЬ'));
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
    final ys = [for (final n in ['Alpha', 'eBay', 'Zoom']) tester.getTopLeft(find.text(n)).dy];
    expect(ys, orderedEquals([...ys]..sort()), reason: 'sorted ignoring case');
    await unmount(tester, c);
  });

  testWidgets('profiles screen shows the default profile', (tester) async {
    await setUpScreenTest();
    final c = await pumpScreen(tester, const ProfilesScreen());
    expect(find.textContaining('По умолчанию'), findsWidgets);
    expect(find.text('ACTIVE'), findsOneWidget);
    await unmount(tester, c);
  });
}
