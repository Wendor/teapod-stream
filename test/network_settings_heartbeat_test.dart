import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/constants/core_features.dart';
import 'package:teapodstream/core/models/heartbeat_settings.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/providers/profile_provider.dart';
import 'package:teapodstream/providers/settings_provider.dart';
import 'package:teapodstream/providers/vpn_provider.dart';
import 'package:teapodstream/ui/screens/network_settings_screen.dart';
import 'package:teapodstream/ui/theme/app_theme.dart';

class _Settings extends SettingsNotifier {
  final AppSettings initial;
  _Settings(this.initial);

  @override
  Future<AppSettings> build() async => initial;

  @override
  Future<void> save(AppSettings settings) async => state = AsyncData(settings);
}

class _Profile extends ProfileNotifier {
  @override
  Future<ProfileState> build() async =>
      const ProfileState(profiles: [], activeProfileId: 'default');
}

void main() {
  const reset = 'Сбросить неподдерживаемое значение';

  Future<ProviderContainer> pumpScreen(
    WidgetTester tester,
    HeartbeatProbe probe,
  ) async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          () => _Settings(
            AppSettings(heartbeat: HeartbeatSettings(probe: probe)),
          ),
        ),
        profileProvider.overrideWith(_Profile.new),
        pendingReconnectProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const NetworkSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Тип проверки'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    return container;
  }

  AppSettings settingsOf(ProviderContainer container) =>
      container.read(settingsProvider).requireValue;

  testWidgets('a stored XRAYDELAY probe is kept in both cores', (
    tester,
  ) async {
    final container = await pumpScreen(tester, HeartbeatProbe.xrayDelay);
    expect(find.text('XRAYDELAY'), findsOneWidget);
    // Both cores measure the URL in the core through the proxy.
    expect(find.text('Адрес проверки'), findsOneWidget);
    expect(find.text(reset), findsNothing);
    expect(settingsOf(container).heartbeat.probe, HeartbeatProbe.xrayDelay);
    expect(
      find.textContaining('XRAYDELAY — '),
      findsOneWidget,
    );
  });

  testWidgets('PASSIVE is supported by both cores and needs no target URL', (
    tester,
  ) async {
    final container = await pumpScreen(tester, HeartbeatProbe.passive);
    expect(find.text('PASSIVE'), findsOneWidget);
    expect(find.text(reset), findsNothing);
    expect(find.text('Адрес проверки'), findsNothing);
    expect(settingsOf(container).heartbeat.probe, HeartbeatProbe.passive);
    expect(
      find.textContaining('PASSIVE — без активных проб'),
      findsOneWidget,
    );
  });

  testWidgets('the probe picker offers only probes of the selected core', (
    tester,
  ) async {
    await pumpScreen(tester, HeartbeatProbe.socks);
    await tester.tap(find.text('SOCKS'));
    await tester.pumpAndSettle();
    expect(find.text('heartbeat // probe'), findsOneWidget);
    expect(find.text('XRAYDELAY'), findsOneWidget);
    expect(find.text('PASSIVE'), findsOneWidget);
  });

  testWidgets('switchConfig explains how the selected core checks candidates', (
    tester,
  ) async {
    final container = await pumpScreen(tester, HeartbeatProbe.socks);
    await container
        .read(settingsProvider.notifier)
        .save(
          settingsOf(container).copyWith(
            heartbeat: const HeartbeatSettings(
              failAction: HeartbeatFailAction.switchConfig,
            ),
          ),
        );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Откуда брать конфиг'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining('полноценным замером через сам протокол, не TCP-пингом'),
      findsOneWidget,
    );
    // Rust takes only the profiles its builder can run.
    expect(
      find.textContaining('поддерживает Rust-сборка'),
      CoreFeatures.current.isRust ? findsOneWidget : findsNothing,
    );
  });
}
