import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'deeplink_router.dart';
import '../models/profile_bundle.dart';
import '../models/connections_bundle.dart';
import '../../providers/profile_provider.dart';
import '../../providers/config_provider.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/theme/app_colors.dart';

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
      // Ссылку может открыть любой сайт или приложение, а запрос уходит мимо VPN
      // с реального IP — только https и только после согласия пользователя.
      final url = Uri.tryParse(parsed.urlValue ?? '');
      if (url == null || url.scheme != 'https' || url.host.isEmpty) {
        return _showError('Импорт по ссылке поддерживает только https');
      }
      if (!await _confirmFetch(url.host)) return;
      bundle = await DeeplinkRouter.fetchFromUrl(parsed);
    }

    if (!context.mounted) return;
    if (bundle == null) return _showError('Не удалось загрузить данные по ссылке');

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
        title: Text('Импорт профиля',
            style: AppTheme.sans(size: 16, color: t.text, weight: FontWeight.w500)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Профиль: «${bundle.profile.name}»',
                style: AppTheme.mono(size: 12, color: t.text)),
            const SizedBox(height: 6),
            Text('Экспорт: ${_formatDate(bundle.exportedAt)}',
                style: AppTheme.mono(size: 10, color: t.textMuted)),
            if (sourceUrl != null) ...[
              const SizedBox(height: 4),
              Text('Источник: $sourceUrl',
                  style: AppTheme.mono(size: 9, color: t.accent)),
            ],
            if (bundle.hasConnections)
              Text('+ ${bundle.configs?.length ?? 0} конфигов, ${bundle.subscriptions?.length ?? 0} подписок',
                  style: AppTheme.mono(size: 10, color: t.accent)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: AppTheme.mono(size: 11, color: t.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(profileProvider.notifier).importBundle(
                  bundle, sourceUrl: sourceUrl);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Профиль «${bundle.profile.name}» импортирован',
                      style: AppTheme.mono(size: 12, color: t.bg)),
                  backgroundColor: t.accent,
                  duration: const Duration(seconds: 2),
                ));
              }
            },
            child: Text('Импортировать', style: AppTheme.mono(size: 11, color: t.accent)),
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
        title: Text('Импорт подключений',
            style: AppTheme.sans(size: 16, color: t.text, weight: FontWeight.w500)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (bundle.label != null)
              Text('Набор: «${bundle.label}»',
                  style: AppTheme.mono(size: 12, color: t.text)),
            const SizedBox(height: 6),
            Text('${bundle.configs.length} конфигов, ${bundle.subscriptions.length} подписок',
                style: AppTheme.mono(size: 12, color: t.text)),
            const SizedBox(height: 4),
            Text('Экспорт: ${_formatDate(bundle.exportedAt)}',
                style: AppTheme.mono(size: 10, color: t.textMuted)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: AppTheme.mono(size: 11, color: t.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final result = await ref.read(configProvider.notifier).importBundle(bundle);
              if (context.mounted) {
                final msg = result.addedSubscriptions > 0
                    ? 'Добавлено: ${result.addedConfigs} конфигов, ${result.addedSubscriptions} подписок'
                    : 'Добавлено: ${result.addedConfigs} новых конфигов';
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(msg, style: AppTheme.mono(size: 12, color: t.bg)),
                  backgroundColor: t.accent,
                  duration: const Duration(seconds: 2),
                ));
              }
            },
            child: Text('Импортировать', style: AppTheme.mono(size: 11, color: t.accent)),
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
        title: Text('Загрузить по ссылке?',
            style: AppTheme.sans(size: 16, color: t.text, weight: FontWeight.w500)),
        content: Text(
            'Данные для импорта будут загружены с $host напрямую, мимо VPN: '
            'сервер увидит ваш реальный IP.',
            style: AppTheme.mono(size: 12, color: t.text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: AppTheme.mono(size: 11, color: t.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Загрузить', style: AppTheme.mono(size: 11, color: t.accent)),
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
