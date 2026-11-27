// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../core/models/import_review.dart';
import '../../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'dialog_parts.dart';

/// The traffic settings an import changes and the subscription hosts it adds; nothing when [review] is empty.
class ImportReviewDetails extends StatelessWidget {
  final ImportReview review;

  const ImportReviewDetails(this.review, {super.key});

  static String label(AppLocalizations l, TrafficSetting s) => switch (s) {
    TrafficSetting.killSwitch => l.importChangeKillSwitch,
    TrafficSetting.dns => l.importChangeDns,
    TrafficSetting.splitTunneling => l.routingSplitTunnel,
    TrafficSetting.routing => l.importChangeRouting,
    TrafficSetting.tethering => l.splitTethering,
    TrafficSetting.ipv6 => l.networkIpv6,
    TrafficSetting.logLevel => l.importChangeLogLevel,
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    final l = context.l10n;
    final head = AppTheme.sans(size: 12, color: t.danger);
    final item = AppTheme.mono(size: 11, color: t.text);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (review.changes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(l.importReviewTraffic, style: head),
          for (final c in review.changes) Text('· ${label(l, c)}', style: item),
        ],
        if (review.subscriptionHosts.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(l.importReviewSubscriptions, style: head),
          for (final h in review.subscriptionHosts) Text('· $h', style: item),
        ],
      ],
    );
  }
}

/// Asks before an import that changes traffic settings or adds subscriptions; true at once when [review] is empty.
Future<bool> confirmImportReview(BuildContext context, ImportReview review) async {
  if (review.isEmpty) return true;
  final l = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.importReviewTitle),
      content: SingleChildScrollView(child: ImportReviewDetails(review)),
      actions: [
        const DialogCancel(result: false),
        DialogAction(l.commonContinue, onPressed: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  return ok ?? false;
}
