import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/models/core_kind.dart';
import 'package:teapodstream/core/models/app_settings.dart';
import 'package:teapodstream/providers/config_provider.dart';
import 'package:teapodstream/ui/screens/home/home_screen.dart';

import '../helpers/ui_harness.dart';

void main() {
  testWidgets('home shows the core; the sheet explains it and pins another core', (tester) async {
    await setUpScreenTest(
      configs: [testConfig('1')],
      activeId: '1',
      settings: const AppSettings(disabledCores: {CoreKind.xrayRust}),
    );
    final c = await pumpScreen(tester, const HomeScreen());
    final line = find.textContaining('xray-core ›', findRichText: true);
    expect(line, findsOneWidget);

    await tester.tap(line);
    await settle(tester);
    expect(find.text('in use'), findsOneWidget);
    expect(find.text('compatible'), findsOneWidget); // sing-box
    expect(find.text('Disabled in settings.'), findsOneWidget); // Rust
    // A disabled core can't be pinned.
    expect(find.text('XRAY-RUST'), findsNothing);

    await tester.tap(find.text('SING-BOX'));
    await settle(tester);
    expect(c.read(configProvider).value!.configs.single.core, CoreKind.singBox);
    expect(find.text('★'), findsOneWidget);
    expect(find.textContaining('sing-box · pinned ›', findRichText: true), findsOneWidget);

    await tester.tap(find.text('AUTO'));
    await settle(tester);
    expect(c.read(configProvider).value!.configs.single.core, isNull);
    await unmount(tester, c);
  });
}
