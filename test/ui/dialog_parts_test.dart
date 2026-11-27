import 'dart:convert';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/services/subscription_service.dart';
import 'package:teapodstream/l10n/app_localizations.dart';
import 'package:teapodstream/ui/theme/app_colors.dart';
import 'package:teapodstream/ui/theme/app_theme.dart';
import 'package:teapodstream/ui/widgets/dialog_parts.dart';
import 'package:teapodstream/ui/widgets/untrusted_cert_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final theme = AppTheme.build(Brightness.dark, AppColors.accentCyan);
  final t = theme.extension<TeapodTokens>()!;

  Future<BuildContext> pump(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme,
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    return ctx;
  }

  Color? textColor(WidgetTester tester, String text) =>
      DefaultTextStyle.of(tester.element(find.text(text))).style.color ??
      tester.widget<Text>(find.text(text)).style?.color;

  Material dialogMaterial(WidgetTester tester) =>
      tester.widget<Material>(find.descendant(of: find.byType(AlertDialog), matching: find.byType(Material)).first);

  testWidgets('a dialog takes its frame and text from the theme, its buttons the colour of their role', (tester) async {
    final ctx = await pump(tester);
    final result = showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Title'),
        content: const Text('Body'),
        actions: [
          const DialogCancel(result: false),
          DialogAction('Delete', danger: true, onPressed: () => Navigator.pop(c, true)),
          DialogAction('Save', onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final material = dialogMaterial(tester);
    expect(material.color, t.bg);
    expect((material.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.zero);
    expect(textColor(tester, 'Title'), t.text);
    expect(textColor(tester, 'Body'), t.textDim);
    expect(textColor(tester, 'Cancel'), t.textMuted);
    expect(textColor(tester, 'Delete'), t.danger);
    expect(textColor(tester, 'Save'), t.accent);
    for (final label in ['Cancel', 'Delete', 'Save']) {
      expect(tester.getSize(find.widgetWithText(TextButton, label)).height, greaterThanOrEqualTo(48));
    }

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('a dialog that set its own background now has the shared one', (tester) async {
    final ctx = await pump(tester);
    final cert = UntrustedCertificateException(
      host: 'sub.example',
      subject: 'CN=sub.example',
      issuer: 'CN=sub.example',
      der: base64.encode(utf8.encode('abc')),
    );
    final result = confirmUntrustedCertificate(ctx, cert);
    await tester.pumpAndSettle();
    expect(dialogMaterial(tester).color, t.bg);
    expect(textColor(tester, 'Continue'), t.danger);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('a dialog field is at least 48 dp high', (tester) async {
    final ctx = await pump(tester);
    showDialog<void>(
      context: ctx,
      builder: (c) => AlertDialog(
        content: TextField(
          style: dialogFieldStyle(c),
          decoration: dialogField(hint: 'name'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(TextField)).height, greaterThanOrEqualTo(48));
  });
}
