import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teapodstream/core/models/connections_bundle.dart';
import 'package:teapodstream/core/models/profile.dart';
import 'package:teapodstream/core/models/profile_bundle.dart';
import 'package:teapodstream/core/services/deeplink_handler.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/providers/config_provider.dart';
import 'package:teapodstream/providers/profile_provider.dart';
import 'package:teapodstream/providers/settings_provider.dart';
import 'package:teapodstream/providers/vpn_provider.dart';
import 'package:teapodstream/ui/screens/home_screen.dart';
import 'package:teapodstream/ui/screens/profiles_screen.dart';

import '../helpers/ui_harness.dart';

/// Кнопка `go` вызывает DeeplinkHandler.handleUri с [uri].
class _DeeplinkHost extends ConsumerWidget {
  final String uri;
  const _DeeplinkHost(this.uri);

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: TextButton(
          onPressed: () => DeeplinkHandler(context, ref).handleUri(uri),
          child: const Text('go'),
        ),
      );
}

final _profileBundle = ProfileBundle(
  exportedAt: DateTime(2026, 3, 4, 5, 6),
  profile: Profile(id: 'r', name: 'Shared', settings: const AppSettings(mtu: 1300), createdAt: DateTime(2026)),
  configs: [testConfig('p1')],
);

void main() {
  group('deeplink handler', () {
    Future<ProviderContainer> go(WidgetTester tester, String uri) async {
      await setUpScreenTest();
      final c = await pumpScreen(tester, _DeeplinkHost(uri));
      c.listen(profileProvider, (_, _) {});
      c.listen(configProvider, (_, _) {});
      await settle(tester);
      await tester.tap(find.text('go'));
      await settle(tester);
      return c;
    }

    testWidgets('inline profile is imported after confirmation', (tester) async {
      final c = await go(tester, _profileBundle.toDeeplink());
      expect(find.text('Импорт профиля'), findsOneWidget);
      expect(find.text('Профиль: «Shared»'), findsOneWidget);
      expect(find.text('Экспорт: 2026-03-04 05:06'), findsOneWidget);
      expect(find.text('+ 1 конфигов, 0 подписок'), findsOneWidget);
      await tester.tap(find.text('Импортировать'));
      await settle(tester);
      expect(c.read(profileProvider).value!.profiles.map((p) => p.name), contains('Shared'));
      expect(c.read(configProvider).value!.configs.single.address, 'hp1.example');
      expect(find.textContaining('импортирован'), findsOneWidget);
      await unmount(tester, c);
    });

    testWidgets('cancel leaves everything as is', (tester) async {
      final c = await go(tester, _profileBundle.toDeeplink());
      await tester.tap(find.text('Отмена'));
      await settle(tester);
      expect(c.read(profileProvider).value!.profiles, hasLength(1));
      await unmount(tester, c);
    });

    testWidgets('inline connections are imported', (tester) async {
      final bundle = ConnectionsBundle(exportedAt: DateTime(2026), label: 'Pack', configs: [testConfig('x')]);
      final c = await go(tester, bundle.toDeeplink());
      expect(find.text('Набор: «Pack»'), findsOneWidget);
      expect(find.text('1 конфигов, 0 подписок'), findsOneWidget);
      await tester.tap(find.text('Импортировать'));
      await settle(tester);
      expect(c.read(configProvider).value!.configs.single.address, 'hx.example');
      expect(find.text('Добавлено: 1 новых конфигов'), findsOneWidget);
      await unmount(tester, c);
    });

    testWidgets('non-https url is refused without a request', (tester) async {
      var requests = 0;
      await http.runWithClient(() async {
        final c = await go(tester, 'teapod://import/profile?url=http://plain.example/p.json');
        expect(find.text('Импорт по ссылке поддерживает только https'), findsOneWidget);
        await unmount(tester, c);
      }, () => MockClient((_) async {
            requests++;
            return http.Response('', 200);
          }));
      expect(requests, 0);
    });

    testWidgets('https url asks first; declining makes no request', (tester) async {
      var requests = 0;
      await http.runWithClient(() async {
        final c = await go(tester, 'teapod://import/profile?url=https://cfg.example/p.json');
        expect(find.text('Загрузить по ссылке?'), findsOneWidget);
        expect(find.textContaining('cfg.example'), findsOneWidget);
        await tester.tap(find.text('Отмена'));
        await settle(tester);
        await unmount(tester, c);
      }, () => MockClient((_) async {
            requests++;
            return http.Response('', 200);
          }));
      expect(requests, 0);
    });

    testWidgets('https url fetches after consent and shows the import dialog', (tester) async {
      await http.runWithClient(() async {
        final c = await go(tester, 'teapod://import/profile?url=https://cfg.example/p.json');
        await tester.tap(find.text('Загрузить'));
        await settle(tester);
        expect(find.text('Импорт профиля'), findsOneWidget);
        expect(find.text('Источник: https://cfg.example/p.json'), findsOneWidget);
        await tester.tap(find.text('Отмена'));
        await settle(tester);
        await unmount(tester, c);
      }, () => MockClient((_) async => http.Response(jsonEncode(_profileBundle.toJson()), 200)));
    });

    testWidgets('failed fetch shows an error', (tester) async {
      await http.runWithClient(() async {
        final c = await go(tester, 'teapod://import/connections?url=https://cfg.example/c.json');
        await tester.tap(find.text('Загрузить'));
        await settle(tester);
        expect(find.text('Не удалось загрузить данные по ссылке'), findsOneWidget);
        await unmount(tester, c);
      }, () => MockClient((_) async => http.Response('', 404)));
    });

    testWidgets('foreign links are ignored', (tester) async {
      final c = await go(tester, 'https://example.com');
      expect(find.byType(AlertDialog), findsNothing);
      await unmount(tester, c);
    });
  });

  testWidgets('server picker switches the active config', (tester) async {
    await setUpScreenTest(configs: [testConfig('1'), testConfig('2')], activeId: '1');
    final c = await pumpScreen(tester, const HomeScreen());
    await tester.tap(find.text('Server 1').first);
    await settle(tester);
    expect(find.text('select // server'), findsOneWidget);
    await tester.tap(find.text('Server 2').last);
    await settle(tester);
    expect(c.read(configProvider).value!.activeConfigId, '2');
    await unmount(tester, c);
  });

  testWidgets('reconnect banner appears after a setting change and reconnects', (tester) async {
    final native = await setUpScreenTest(configs: [testConfig('1')], activeId: '1');
    native.state = {'state': 'connected', 'socksPort': 2000, 'socksUser': 'u', 'socksPassword': 'p'};
    final c = await pumpScreen(tester, const HomeScreen());
    expect(c.read(vpnProvider).isConnected, isTrue);
    expect(find.text('ПЕРЕПОДКЛЮЧИТЬ'), findsNothing);

    final s = c.read(settingsProvider).value!;
    c.read(settingsProvider.notifier).save(s.copyWith(mtu: 1400));
    await settle(tester);
    expect(find.text('ПЕРЕПОДКЛЮЧИТЬ'), findsOneWidget);

    await tester.tap(find.text('ПЕРЕПОДКЛЮЧИТЬ'));
    await settle(tester);
    expect(native.named('connect'), hasLength(1));
    expect(find.text('ПЕРЕПОДКЛЮЧИТЬ'), findsNothing);
    await unmount(tester, c);
  });

  testWidgets('profiles screen creates a profile', (tester) async {
    await setUpScreenTest();
    final c = await pumpScreen(tester, const ProfilesScreen());
    await tester.tap(find.byIcon(Icons.add_rounded));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Travel');
    await tester.tap(find.text('Создать'));
    await settle(tester);
    expect(c.read(profileProvider).value!.profiles.map((p) => p.name), contains('Travel'));
    expect(find.textContaining('Travel'), findsWidgets);
    await unmount(tester, c);
  });
}
