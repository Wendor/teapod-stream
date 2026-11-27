// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/l10n/app_localizations.dart';
import 'package:teapodstream/ui/theme/app_colors.dart';
import 'package:teapodstream/ui/theme/app_theme.dart';
import 'package:teapodstream/ui/widgets/settings_shared.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The subscription interval: five segments in a label + selector row on a 280 dp screen at the largest text scale.
  Future<void> pump(WidgetTester tester, void Function(String) onChanged, {bool intrinsic = false}) async {
    tester.view.physicalSize = const Size(280, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final theme = AppTheme.build(Brightness.dark, AppColors.accentCyan);
    final t = theme.extension<TeapodTokens>()!;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(280, 600), textScaler: TextScaler.linear(2.0)),
          child: Scaffold(
            body: _maybeIntrinsic(
              intrinsic,
              SetInlineField(
                t: t,
                label: 'Interval',
                child: SetSegSquare(
                  t: t,
                  value: '1',
                  opts: const [('1', '1 h'), ('3', '3 h'), ('6', '6 h'), ('12', '12 h'), ('24', '24 h')],
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a selector wider than a narrow screen scrolls instead of overflowing; its targets stay 48 dp', (
    tester,
  ) async {
    String? picked;
    await pump(tester, (v) => picked = v);
    expect(tester.takeException(), isNull);
    for (final label in ['1 h', '24 h']) {
      final target = find.ancestor(of: find.text(label), matching: find.byType(Semantics)).first;
      final size = tester.getSize(target);
      expect(size.height, greaterThanOrEqualTo(kMinInteractiveDimension));
      expect(size.width, greaterThanOrEqualTo(kMinInteractiveDimension));
    }
    await tester.ensureVisible(find.text('24 h'));
    await tester.pump();
    await tester.tap(find.text('24 h'));
    expect(picked, '24');
  });

  testWidgets('it lays out under a parent that asks for intrinsic sizes', (tester) async {
    await pump(tester, (_) {}, intrinsic: true);
    expect(tester.takeException(), isNull);
    expect(find.text('24 h'), findsOneWidget);
  });
}

/// An `IntrinsicHeight` around [child] when [on]: a parent that queries the selector's intrinsic size.
Widget _maybeIntrinsic(bool on, Widget child) => on ? IntrinsicHeight(child: child) : child;
