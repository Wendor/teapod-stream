import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/models/core_kind.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/providers/config_provider.dart';
import 'package:teapodstream/ui/screens/home_screen.dart';

import '../helpers/ui_harness.dart';

void main() {
  testWidgets('home shows the core; the sheet explains it and pins another core', (tester) async {
    await setUpScreenTest(
      configs: [testConfig('1')],
      activeId: '1',
      settings: const AppSettings(disabledCores: {CoreKind.xrayRust}),
    );
    final c = await pumpScreen(tester, const HomeScreen());
    final line = find.textContaining('Xray (Go) ›', findRichText: true);
    expect(line, findsOneWidget);

    await tester.tap(line);
    await settle(tester);
    expect(find.text('используется'), findsOneWidget);
    expect(find.text('совместимо'), findsOneWidget); // sing-box
    expect(find.text('Выключено в настройках.'), findsOneWidget); // Rust
    // Выключенное ядро закрепить нельзя.
    expect(find.text('RUST'), findsNothing);

    await tester.tap(find.text('SING-BOX'));
    await settle(tester);
    expect(c.read(configProvider).value!.configs.single.core, CoreKind.singBox);
    expect(find.text('★'), findsOneWidget);
    expect(find.textContaining('sing-box · закреплено ›', findRichText: true), findsOneWidget);

    await tester.tap(find.text('АВТО'));
    await settle(tester);
    expect(c.read(configProvider).value!.configs.single.core, isNull);
    await unmount(tester, c);
  });
}
