import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/constants/core_features.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/providers/apps_provider.dart';
import 'package:teapodstream/providers/profile_provider.dart';
import 'package:teapodstream/providers/settings_provider.dart';
import 'package:teapodstream/ui/screens/split_tunnel_screen.dart';
import 'package:teapodstream/ui/theme/app_theme.dart';
import 'package:teapodstream/ui/widgets/settings_shared.dart';

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

Future<ProviderContainer> _pumpScreen(
  WidgetTester tester,
  AppSettings settings,
) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(() => _Settings(settings)),
      profileProvider.overrideWith(_Profile.new),
      installedAppsProvider.overrideWith((ref) async => []),
    ],
  );
  addTearDown(container.dispose);
  // The test font is wider than the app's fonts, so the fixed header above
  // the app list needs more room than on a phone.
  tester.view.physicalSize = const Size(800, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const SplitTunnelScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

AppSettings _allExcept({required bool allowTethering}) => AppSettings(
  splitTunnelingEnabled: true,
  vpnMode: VpnMode.allExcept,
  excludedPackages: const {'org.example.excluded'},
  allowTethering: allowTethering,
);

bool _switchValue(WidgetTester tester) => tester
    .widget<SetRowToggle>(
      find.ancestor(
        of: find.text('Раздача через VPN'),
        matching: find.byType(SetRowToggle),
      ),
    )
    .value;

void main() {
  // Both services check the owner of every new TUN flow (Go: tun2socks
  // validator, Rust: xray-rust TUN admission), so the screen is the upstream one.
  testWidgets('the tethering switch controls unowned flows in both cores', (
    tester,
  ) async {
    final container = await _pumpScreen(
      tester,
      _allExcept(allowTethering: true),
    );

    expect(find.text('Раздача через VPN'), findsOneWidget);
    expect(_switchValue(tester), isTrue);
    expect(find.textContaining('Защита ослаблена'), findsOneWidget);
    await tester.tap(find.text('Раздача через VPN'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).requireValue.allowTethering, isFalse);
    expect(_switchValue(tester), isFalse);
    expect(find.textContaining('Защита ослаблена'), findsNothing);
  });

  testWidgets('tethering stored as off shows the protected state', (
    tester,
  ) async {
    final container = await _pumpScreen(
      tester,
      _allExcept(allowTethering: false),
    );

    expect(_switchValue(tester), isFalse);
    expect(find.textContaining('Защита ослаблена'), findsNothing);
    expect(find.text('Сбросить неподдерживаемое значение'), findsNothing);
    expect(find.textContaining('не проверяет владельца'), findsNothing);

    // Turning it on still asks first, as upstream.
    await tester.tap(find.text('Раздача через VPN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Включить'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).requireValue.allowTethering, isTrue);
    expect(find.textContaining('Защита ослаблена'), findsOneWidget);
  });

  testWidgets('ТОЛЬКО mode needs no tethering switch or owner-check notice', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      const AppSettings(
        splitTunnelingEnabled: true,
        vpnMode: VpnMode.onlySelected,
        includedPackages: {'org.example.browser'},
      ),
    );

    expect(find.text('Раздача через VPN'), findsNothing);
    expect(find.textContaining('не проверяет владельца'), findsNothing);
  });

  // The owner check covers TUN only; Rust's loopback SOCKS takes no password.
  for (final (name, settings, shown) in [
    ('КРОМЕ', _allExcept(allowTethering: false), true),
    (
      'ТОЛЬКО',
      const AppSettings(
        splitTunnelingEnabled: true,
        vpnMode: VpnMode.onlySelected,
        includedPackages: {'org.example.browser'},
      ),
      true,
    ),
    ('split tunnelling off', const AppSettings(), false),
  ]) {
    testWidgets('Rust explains that its SOCKS is open to every app: $name', (
      tester,
    ) async {
      await _pumpScreen(tester, settings);
      expect(
        find.textContaining('локальный SOCKS работает без пароля'),
        shown && CoreFeatures.current.isRust ? findsOneWidget : findsNothing,
      );
    });
  }
}
