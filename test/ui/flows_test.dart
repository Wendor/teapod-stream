import 'dart:convert';
import 'dart:io';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/models/connections_bundle.dart';
import 'package:teapodstream/core/models/profile.dart';
import 'package:teapodstream/core/models/profile_bundle.dart';
import 'package:teapodstream/core/models/dns_config.dart';
import 'package:teapodstream/core/models/subscription.dart';
import 'package:teapodstream/ui/deeplink_handler.dart';
import 'package:teapodstream/core/models/app_settings.dart';
import 'package:teapodstream/providers/config_provider.dart';
import 'package:teapodstream/providers/ip_info_provider.dart';
import 'package:teapodstream/providers/profile_provider.dart';
import 'package:teapodstream/providers/settings_provider.dart';
import 'package:teapodstream/providers/vpn_provider.dart';
import 'package:teapodstream/ui/screens/home_screen.dart';
import 'package:teapodstream/ui/screens/profiles_screen.dart';

import '../helpers/local_server.dart';
import '../helpers/ui_harness.dart';

/// The `go` button calls DeeplinkHandler.handleUri with [uri].
class _DeeplinkHost extends ConsumerWidget {
  final String uri;
  const _DeeplinkHost(this.uri);

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: TextButton(onPressed: () => DeeplinkHandler(context, ref).handleUri(uri), child: const Text('go')),
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
      expect(find.text('Import profile'), findsOneWidget);
      expect(find.text('Profile: "Shared"'), findsOneWidget);
      expect(find.text('Exported: 2026-03-04 05:06'), findsOneWidget);
      expect(find.text('+ 1 config, 0 subscriptions'), findsOneWidget);
      await tester.tap(find.text('Import'));
      await settle(tester);
      expect(c.read(profileProvider).value!.profiles.map((p) => p.name), contains('Shared'));
      expect(c.read(configProvider).value!.configs.single.address, 'hp1.example');
      expect(find.textContaining('imported'), findsOneWidget);
      await unmount(tester, c);
    });

    testWidgets('cancel leaves everything as is', (tester) async {
      final c = await go(tester, _profileBundle.toDeeplink());
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(c.read(profileProvider).value!.profiles, hasLength(1));
      await unmount(tester, c);
    });

    testWidgets('inline connections are imported', (tester) async {
      final bundle = ConnectionsBundle(exportedAt: DateTime(2026), label: 'Pack', configs: [testConfig('x')]);
      final c = await go(tester, bundle.toDeeplink());
      expect(find.text('Bundle: "Pack"'), findsOneWidget);
      expect(find.text('1 config, 0 subscriptions'), findsOneWidget);
      await tester.tap(find.text('Import'));
      await settle(tester);
      expect(c.read(configProvider).value!.configs.single.address, 'hx.example');
      expect(find.text('Added: 1 new config'), findsOneWidget);
      await unmount(tester, c);
    });

    testWidgets('the import dialogs list traffic changes and subscription hosts', (tester) async {
      final profile = ProfileBundle(
        exportedAt: DateTime(2026),
        profile: Profile(
          id: 'r',
          name: 'Leaky',
          settings: const AppSettings(dnsMode: DnsMode.direct, geoipUrl: 'https://geo.example/ip.dat'),
          createdAt: DateTime(2026),
        ),
      );
      var c = await go(tester, profile.toDeeplink());
      expect(find.text('Changes how traffic goes:'), findsOneWidget);
      expect(find.text('· DNS'), findsOneWidget);
      expect(find.textContaining('subscriptions, the app'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      await unmount(tester, c);

      final connections = ConnectionsBundle(
        exportedAt: DateTime(2026),
        subscriptions: [Subscription(id: 's', name: 'S', url: 'https://subs.example/x', createdAt: DateTime(2026))],
      );
      c = await go(tester, connections.toDeeplink());
      expect(find.text('Adds subscriptions, the app will load them from:'), findsOneWidget);
      expect(find.text('· subs.example'), findsOneWidget);
      expect(find.text('Changes how traffic goes:'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      await unmount(tester, c);
    });

    /// A local server behind every request (RedirectHttpOverrides); its IO runs in [tester.runAsync].
    Future<LocalServer> serve(WidgetTester tester, Object body, {int status = 200}) async {
      final server = (await tester.runAsync(LocalServer.start))!..serve(body, status: status);
      final previous = HttpOverrides.current;
      HttpOverrides.global = RedirectHttpOverrides(server.port);
      addTearDown(() async {
        HttpOverrides.global = previous;
        await tester.runAsync(server.close);
      });
      return server;
    }

    /// Taps `Load` and lets the fetch finish: its IO is real, its continuations run in the fake zone.
    Future<void> load(WidgetTester tester) async {
      await tester.tap(find.text('Load'));
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      await settle(tester);
    }

    testWidgets('non-https url is refused without a request', (tester) async {
      final server = await serve(tester, '');
      final c = await go(tester, 'teapod://import/profile?url=http://plain.example/p.json');
      expect(find.text('Import by link supports https only'), findsOneWidget);
      await unmount(tester, c);
      expect(server.paths, isEmpty);
    });

    testWidgets('https url asks first; declining makes no request', (tester) async {
      final server = await serve(tester, '');
      final c = await go(tester, 'teapod://import/profile?url=https://cfg.example/p.json');
      expect(find.text('Load from link?'), findsOneWidget);
      expect(find.textContaining('cfg.example'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      await unmount(tester, c);
      expect(server.paths, isEmpty);
    });

    testWidgets('https url fetches after consent and shows the import dialog', (tester) async {
      final server = await serve(tester, jsonEncode(_profileBundle.toJson()));
      final c = await go(tester, 'teapod://import/profile?url=https://cfg.example/p.json');
      await load(tester);
      expect(server.paths.single, '/p.json');
      expect(find.text('Import profile'), findsOneWidget);
      expect(find.text('Source: https://cfg.example/p.json'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      await unmount(tester, c);
    });

    testWidgets('failed fetch shows an error', (tester) async {
      await serve(tester, '', status: 404);
      final c = await go(tester, 'teapod://import/connections?url=https://cfg.example/c.json');
      await load(tester);
      expect(find.text("Couldn't load data from the link"), findsOneWidget);
      await unmount(tester, c);
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

  testWidgets('home says the IP is unknown when no lookup service answers', (tester) async {
    final native = await setUpScreenTest(configs: [testConfig('1')], activeId: '1');
    native.state = {'state': 'connected', 'socksPort': 2000, 'socksUser': 'u', 'socksPassword': 'p'};
    // The test binding's HttpClient answers 400 to everything: every service in the chain fails.
    final c = await pumpScreen(tester, const HomeScreen());
    expect(find.textContaining('IP not detected'), findsOneWidget);
    expect(find.textContaining('— · —'), findsNothing);
    await unmount(tester, c);
  });

  testWidgets('home shows the IP alone when the service gave no country', (tester) async {
    final native = await setUpScreenTest(configs: [testConfig('1')], activeId: '1');
    native.state = {'state': 'connected', 'socksPort': 2000, 'socksUser': 'u', 'socksPassword': 'p'};
    final c = await pumpScreen(
      tester,
      const HomeScreen(),
      overrides: [ipInfoProvider.overrideWith(() => _FixedIp(const IpInfo(ip: '203.0.113.9')))],
    );
    expect(find.text('203.0.113.9'), findsOneWidget);
    await unmount(tester, c);
  });

  testWidgets('reconnect banner appears after a setting change and reconnects', (tester) async {
    final native = await setUpScreenTest(configs: [testConfig('1')], activeId: '1');
    native.state = {'state': 'connected', 'socksPort': 2000, 'socksUser': 'u', 'socksPassword': 'p'};
    final c = await pumpScreen(tester, const HomeScreen());
    expect(c.read(vpnProvider).isConnected, isTrue);
    expect(find.text('RECONNECT'), findsNothing);

    final s = c.read(settingsProvider).value!;
    c.read(settingsProvider.notifier).save(s.copyWith(mtu: 1400));
    await settle(tester);
    expect(find.text('RECONNECT'), findsOneWidget);

    await tester.tap(find.text('RECONNECT'));
    await settle(tester);
    expect(native.named('connect'), hasLength(1));
    expect(find.text('RECONNECT'), findsNothing);
    await unmount(tester, c);
  });

  testWidgets('profiles screen creates a profile', (tester) async {
    await setUpScreenTest();
    final c = await pumpScreen(tester, const ProfilesScreen());
    await tester.tap(find.byIcon(Icons.add_rounded));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Travel');
    await tester.tap(find.text('Create'));
    await settle(tester);
    expect(c.read(profileProvider).value!.profiles.map((p) => p.name), contains('Travel'));
    expect(find.textContaining('Travel'), findsWidgets);
    await unmount(tester, c);
  });
}

class _FixedIp extends IpInfoNotifier {
  _FixedIp(this.info);
  final IpInfo info;

  @override
  Future<IpInfo?> build() async => info;
}
