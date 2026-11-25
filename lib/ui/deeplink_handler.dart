// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/deeplink_router.dart';
import '../core/models/profile_bundle.dart';
import '../core/models/connections_bundle.dart';
import '../providers/profile_provider.dart';
import '../providers/config_provider.dart';
import '../providers/vpn_provider.dart';
import 'theme/app_theme.dart';
import 'theme/app_colors.dart';
import 'widgets/import_review.dart';
import '../l10n/l10n.dart';

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
      bundle = parsed.type == DeeplinkType.profile ? parsed.profileBundle : parsed.connectionsBundle;
    } else {
      // Any site or app can open the link: https only and only after the user agrees.
      final url = Uri.tryParse(parsed.urlValue ?? '');
      if (url == null || url.scheme != 'https' || url.host.isEmpty) {
        return _showError(context.l10n.deeplinkHttpsOnly);
      }
      if (!await _confirmFetch(url.host)) return;
      bundle = await DeeplinkRouter.fetchFromUrl(parsed, socks: ref.read(tunnelSocksProvider));
    }

    if (!context.mounted) return;
    if (bundle == null) return _showError(context.l10n.deeplinkFetchFailed);

    switch (parsed.type) {
      case DeeplinkType.profile:
        await _showProfileImportDialog(bundle as ProfileBundle, sourceUrl: sourceUrl);
      case DeeplinkType.connections:
        _showConnectionsImportDialog(bundle as ConnectionsBundle);
    }
  }

  Future<void> _showProfileImportDialog(ProfileBundle bundle, {String? sourceUrl}) async {
    final review = await ref.read(profileProvider.notifier).reviewImport(bundle);
    if (!context.mounted) return;
    final t = Theme.of(context).extension<TeapodTokens>()!;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.bg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(
          context.l10n.profileImportTitle,
          style: AppTheme.sans(size: 16, color: t.text, weight: FontWeight.w500),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.deeplinkProfile(bundle.profile.name), style: AppTheme.mono(size: 12, color: t.text)),
              const SizedBox(height: 6),
              Text(
                context.l10n.deeplinkExported(_formatDate(bundle.exportedAt)),
                style: AppTheme.mono(size: 10, color: t.textMuted),
              ),
              if (sourceUrl != null) ...[
                const SizedBox(height: 4),
                Text(context.l10n.deeplinkSource(sourceUrl), style: AppTheme.mono(size: 9, color: t.accent)),
              ],
              if (bundle.hasConnections)
                Text(
                  '+ ${context.l10n.configsCount(bundle.configs?.length ?? 0)}, ${context.l10n.subscriptionsCount(bundle.subscriptions?.length ?? 0)}',
                  style: AppTheme.mono(size: 10, color: t.accent),
                ),
              ImportReviewDetails(review),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.commonCancel, style: AppTheme.mono(size: 11, color: t.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final id = await ref.read(profileProvider.notifier).importBundle(bundle, sourceUrl: sourceUrl);
              if (id != null) await ref.read(vpnProvider.notifier).switchProfile(id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      context.l10n.deeplinkProfileImported(bundle.profile.name),
                      style: AppTheme.mono(size: 12, color: t.bg),
                    ),
                    backgroundColor: t.accent,
                    duration: const Duration(seconds: 2),
                  ),
                );
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
    final review = ref.read(configProvider.notifier).reviewBundle(bundle);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.bg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(
          context.l10n.deeplinkConnectionsTitle,
          style: AppTheme.sans(size: 16, color: t.text, weight: FontWeight.w500),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (bundle.label != null)
                Text(context.l10n.deeplinkBundle(bundle.label!), style: AppTheme.mono(size: 12, color: t.text)),
              const SizedBox(height: 6),
              Text(
                '${context.l10n.configsCount(bundle.configs.length)}, ${context.l10n.subscriptionsCount(bundle.subscriptions.length)}',
                style: AppTheme.mono(size: 12, color: t.text),
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.deeplinkExported(_formatDate(bundle.exportedAt)),
                style: AppTheme.mono(size: 10, color: t.textMuted),
              ),
              ImportReviewDetails(review),
            ],
          ),
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
                    ? context.l10n.deeplinkAdded(
                        '${context.l10n.configsCount(result.addedConfigs)}, ${context.l10n.subscriptionsCount(result.addedSubscriptions)}',
                      )
                    : context.l10n.deeplinkAddedNew(result.addedConfigs);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(msg, style: AppTheme.mono(size: 12, color: t.bg)),
                    backgroundColor: t.accent,
                    duration: const Duration(seconds: 2),
                  ),
                );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: AppTheme.mono(size: 12, color: t.bg)),
        backgroundColor: t.danger,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<bool> _confirmFetch(String host) async {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.bg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(
          context.l10n.deeplinkFetchTitle,
          style: AppTheme.sans(size: 16, color: t.text, weight: FontWeight.w500),
        ),
        content: Text(context.l10n.deeplinkFetchMessage(host), style: AppTheme.mono(size: 12, color: t.text)),
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
