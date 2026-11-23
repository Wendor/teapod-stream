import 'dart:convert';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/services/subscription_service.dart';
import 'package:teapodstream/l10n/app_localizations.dart';
import 'package:teapodstream/ui/theme/app_colors.dart';
import 'package:teapodstream/ui/theme/app_theme.dart';
import 'package:teapodstream/ui/widgets/untrusted_cert_dialog.dart';

void main() {
  final cert = UntrustedCertificateException(
    host: 'sub.example',
    subject: 'CN=sub.example',
    issuer: 'CN=sub.example',
    der: base64.encode(utf8.encode('abc')),
  );

  Future<Future<bool>> show(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.build(Brightness.dark, AppColors.accentCyan),
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final result = confirmUntrustedCertificate(ctx, cert);
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('shows the host, subject and SHA-256 fingerprint; Continue confirms', (tester) async {
    final result = await show(tester);
    expect(find.text('Server: sub.example'), findsOneWidget);
    expect(find.text('Certificate: CN=sub.example'), findsOneWidget);
    expect(
      find.text(
        'SHA-256: BA:78:16:BF:8F:01:CF:EA:41:41:40:DE:5D:AE:22:23:B0:03:61:A3:96:17:7A:9C:B4:10:FF:61:F2:00:15:AD',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('Cancel and a dismissed dialog decline', (tester) async {
    var result = await show(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);

    result = await show(tester);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });
}
