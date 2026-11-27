// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../core/services/subscription_service.dart';
import '../../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'dialog_parts.dart';

/// Asks whether to trust the certificate in [e]. True means: retry with `pinnedCertDer: e.der`, so exactly the
/// certificate shown here (its SHA-256 included) is pinned.
Future<bool> confirmUntrustedCertificate(BuildContext context, UntrustedCertificateException e) async {
  final t = Theme.of(context).extension<TeapodTokens>()!;
  final l10n = context.l10n;
  final detail = AppTheme.mono(size: 11, color: t.textDim);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.certUntrustedTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.certUntrustedMessage),
            const SizedBox(height: 12),
            Text(l10n.certServer(e.host), style: detail),
            Text(l10n.certSubject(e.subject), style: detail),
            Text(l10n.certIssuer(e.issuer), style: detail),
            const SizedBox(height: 8),
            SelectableText(l10n.certFingerprint(e.sha256Fingerprint), style: detail),
            const SizedBox(height: 12),
            Text(l10n.certContinueAnyway, style: AppTheme.mono(size: 12, color: t.text)),
          ],
        ),
      ),
      actions: [
        const DialogCancel(result: false),
        DialogAction(l10n.commonContinue, danger: true, onPressed: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  return confirmed ?? false;
}
