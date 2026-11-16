import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'deeplink_router.dart';
import '../models/profile_bundle.dart';
import '../models/connections_bundle.dart';
import '../../providers/profile_provider.dart';
import '../../providers/config_provider.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/theme/app_colors.dart';
import '../../l10n/l10n.dart';

class DeeplinkHandler {
  final WidgetRef ref;
  final BuildContext context;

  DeeplinkHandler(this.context, this.ref);

  Future<void> handleUri(String uri) async {
    final parsed = DeeplinkRouter.parse(uri);
    if (parsed == null) return;

    Object? bundle;
    final sourceUrl = parsed.effectiveSourceUrl;

    if (parsed.source == DeeplinkSource.data) {
      bundle = parsed.type == DeeplinkType.profile
          ? parsed.profileBundle
          : parsed.connectionsBundle;
    } else {
      // Any site or app can open the link, and the request bypasses the VPN
      // from the real IP — https only and only after the user agrees.
      final url = Uri.tryParse(parsed.urlValue ?? '');
      if (url == null || url.scheme != 'https' || url.host.isEmpty) {
        return _showError(context.l10n.deeplinkHttpsOnly);
      }
      if (!await _confirmFetch(url.host)) return;
      bundle = await DeeplinkRouter.fetchFromUrl(parsed);
    }

    if (!context.mounted) return;
    if (bundle == null) return _showError(context.l10n.deeplinkFetchFailed);

    switch (parsed.type) {
      case DeeplinkType.profile:
        _showProfileImportDialog(bundle as ProfileBundle, sourceUrl: sourceUrl);
      case DeeplinkType.connections:
        _showConnectionsImportDialog(bundle as ConnectionsBundle);
    }
  }

  void _showProfileImportDialog(ProfileBundle bundle, {String? sourceUrl}) {
    final t = Theme.of(context).extension<TeapodTokens>()!;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.bg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(context.l10n.profileImportTitle,
            style: AppTheme.sans(size: 16, color: t.text, weight: FontWeight.w500)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.deeplinkProfile(bundle.profile.name),
                style: AppTheme.mono(size: 12, color: t.text)),
            const SizedBox(height: 6),
            Text(context.l10n.deeplinkExported(_formatDate(bundle.exportedAt)),
                style: AppTheme.mono(size: 10, color: t.textMuted)),
            if (sourceUrl != null) ...[
              const SizedBox(height: 4),
              Text(context.l10n.deeplinkSource(sourceUrl),
                  style: AppTheme.mono(size: 9, color: t.accent)),
            ],
            if (bundle.hasConnections)
              Text('+ ${context.l10n.configsCount(bundle.configs?.length ?? 0)}, ${context.l10n.subscriptionsCount(bundle.subscriptions?.length ?? 0)}',
                  style: AppTheme.mono(size: 10, color: t.accent)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.commonCancel, style: AppTheme.mono(size: 11, color: t.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(profileProvider.notifier).importBundle(
                  bundle, sourceUrl: sourceUrl);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(context.l10n.deeplinkProfileImported(bundle.profile.name),
                      style: AppTheme.mono(size: 12, color: t.bg)),
                  backgroundColor: t.accent,
                  duration: const Duration(seconds: 2),
                ));
              }
            },
            child: Text(context.l10n.commonImport, style: AppTheme.mono(size: 11, color: t.accent)),
          ),
        ],
      ),
    );
  }

  void _showConnectionsImportDialog(ConnectionsBundle bundle) {
    final t = Theme.of(context).extension<TeapodTokens>()!;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.bg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(context.l10n.deeplinkConnectionsTitle,
            style: AppTheme.sans(size: 16, color: t.text, weight: FontWeight.w500)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (bundle.label != null)
              Text(context.l10n.deeplinkBundle(bundle.label!),
                  style: AppTheme.mono(size: 12, color: t.text)),
            const SizedBox(height: 6),
            Text('${context.l10n.configsCount(bundle.configs.length)}, ${context.l10n.subscriptionsCount(bundle.subscriptions.length)}',
                style: AppTheme.mono(size: 12, color: t.text)),
            const SizedBox(height: 4),
            Text(context.l10n.deeplinkExported(_formatDate(bundle.exportedAt)),
                style: AppTheme.mono(size: 10, color: t.textMuted)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.commonCancel, style: AppTheme.mono(size: 11, color: t.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final result = await ref.read(configProvider.notifier).importBundle(bundle);
              if (context.mounted) {
                final msg = result.addedSubscriptions > 0
                    ? context.l10n.deeplinkAdded('${context.l10n.configsCount(result.addedConfigs)}, ${context.l10n.subscriptionsCount(result.addedSubscriptions)}')
                    : context.l10n.deeplinkAddedNew(result.addedConfigs);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(msg, style: AppTheme.mono(size: 12, color: t.bg)),
                  backgroundColor: t.accent,
                  duration: const Duration(seconds: 2),
                ));
              }
            },
            child: Text(context.l10n.commonImport, style: AppTheme.mono(size: 11, color: t.accent)),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!context.mounted) return;
    final t = Theme.of(context).extension<TeapodTokens>()!;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: AppTheme.mono(size: 12, color: t.bg)),
      backgroundColor: t.danger,
      duration: const Duration(seconds: 3),
    ));
  }

  Future<bool> _confirmFetch(String host) async {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.bg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(context.l10n.deeplinkFetchTitle,
            style: AppTheme.sans(size: 16, color: t.text, weight: FontWeight.w500)),
        content: Text(
            context.l10n.deeplinkFetchMessage(host),
            style: AppTheme.mono(size: 12, color: t.text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.commonCancel, style: AppTheme.mono(size: 11, color: t.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.deeplinkFetchButton, style: AppTheme.mono(size: 11, color: t.accent)),
          ),
        ],
      ),
    );
    return ok == true && context.mounted;
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
