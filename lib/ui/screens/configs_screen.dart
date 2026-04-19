import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/models/vpn_config.dart';
import '../../core/services/config_storage_service.dart';
import '../../core/services/subscription_service.dart';
import '../../protocols/xray/vless_parser.dart';
import '../../providers/config_provider.dart';
import '../../providers/vpn_provider.dart';
import '../../core/interfaces/vpn_engine.dart';
import '../theme/app_colors.dart';
import '../widgets/config_card.dart';
import 'add_config_screen.dart';

class ConfigsScreen extends ConsumerStatefulWidget {
  const ConfigsScreen({super.key});

  @override
  ConsumerState<ConfigsScreen> createState() => _ConfigsScreenState();
}

class _ConfigsScreenState extends ConsumerState<ConfigsScreen> {
  final Set<String> _expandedSubs = {};
  bool _isPinging = false;

  @override
  Widget build(BuildContext context) {
    final configStateAsync = ref.watch(configProvider);
    final vpnState = ref.watch(vpnProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Конфигурации'),
        actions: [
          if (_isPinging)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.network_ping_rounded),
              tooltip: 'Проверить пинг',
              onPressed: configStateAsync.maybeWhen(
                data: (s) => s.configs.isNotEmpty ? () => _pingAll(s.configs) : null,
                orElse: () => null,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _openAddConfig(context),
          ),
        ],
      ),
      body: configStateAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
        data: (configState) {
          if (configState.configs.isEmpty && configState.subscriptions.isEmpty) {
            return _EmptyState(onAdd: () => _openAddConfig(context));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: configState.subscriptions.length + (configState.standaloneConfigs.isNotEmpty ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(height: 16),
            itemBuilder: (context, i) {
              if (i < configState.subscriptions.length) {
                final sub = configState.subscriptions[i];
                final subConfigs = configState.configsBySubscription[sub.id] ?? [];
                final isExpanded = _expandedSubs.contains(sub.id);
                return _SubscriptionGroup(
                  subscription: sub,
                  configs: subConfigs,
                  activeConfigId: configState.activeConfigId,
                  isExpanded: isExpanded,
                  vpnState: vpnState.connectionState,
                  onToggle: () => setState(() {
                    if (isExpanded) {
                      _expandedSubs.remove(sub.id);
                    } else {
                      _expandedSubs.add(sub.id);
                    }
                  }),
                  onRefresh: () => _refreshSubscription(context, ref, sub),
                  onRename: () => _renameSubscription(context, ref, sub),
                  onEditUrl: () => _editSubscriptionUrl(context, ref, sub),
                  onDelete: () => _deleteSubscription(context, ref, sub),
                  onSelectConfig: (config) => _selectConfig(ref, config),
                  onConfigLongPress: (config) => _showConfigMenu(context, ref, config),
                );
              }
              return _StandaloneSection(
                configs: configState.standaloneConfigs,
                activeConfigId: configState.activeConfigId,
                vpnState: vpnState.connectionState,
                onSelectConfig: (config) => _selectConfig(ref, config),
                onConfigLongPress: (config) => _showConfigMenu(context, ref, config),
              );
            },
          );
        },
      ),
    );
  }

  void _selectConfig(WidgetRef ref, VpnConfig config) {
    ref.read(configProvider.notifier).setActiveConfig(config.id);
    final vpnState = ref.read(vpnProvider);
    if (vpnState.isConnected || vpnState.isBusy) {
      ref.read(vpnProvider.notifier).reconnectWithNewConfig();
    }
  }

  Future<void> _pingAll(List<VpnConfig> configs) async {
    if (_isPinging) return;
    setState(() => _isPinging = true);
    try {
      await ref.read(vpnProvider.notifier).pingAllConfigs();
    } finally {
      if (mounted) setState(() => _isPinging = false);
    }
  }

  Future<void> _showConfigMenu(
    BuildContext context, WidgetRef ref, VpnConfig config) async {
    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem(value: 'rename', child: _MenuRow(Icons.edit_rounded, 'Переименовать')),
      const PopupMenuItem(value: 'edit', child: _MenuRow(Icons.code_rounded, 'Редактировать URI')),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'copy', child: _MenuRow(Icons.copy_rounded, 'Копировать URL')),
      const PopupMenuItem(value: 'share', child: _MenuRow(Icons.share_rounded, 'Поделиться')),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'delete', child: _MenuRow(Icons.delete_rounded, 'Удалить', color: AppColors.error)),
    ];

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.of(context).size.width - 200,
        MediaQuery.of(context).padding.top + kToolbarHeight + 56,
        20,
        0,
      ),
      items: items,
      color: AppColors.surfaceElevated,
    );

    if (result == null) return;
    if (!context.mounted) return;
    switch (result) {
      case 'rename':
        await _renameConfig(context, ref, config);
        break;
      case 'edit':
        await _editConfig(context, ref, config);
        break;
      case 'share':
        if (config.rawUri != null) {
          await Share.share(config.rawUri!);
        }
        break;
      case 'copy':
        if (config.rawUri != null) {
          await Clipboard.setData(ClipboardData(text: config.rawUri!));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('URL скопирован'), duration: Duration(seconds: 1)),
            );
          }
        }
        break;
      case 'delete':
        await _deleteConfig(context, ref, config);
        break;
    }
  }

  Future<void> _renameConfig(
    BuildContext context, WidgetRef ref, VpnConfig config) async {
    final controller = TextEditingController(text: config.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Переименовать'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Имя',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сохранить', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty) {
      final updated = config.copyWith(name: controller.text.trim());
      ref.read(configProvider.notifier).updateConfig(updated);
    }
  }

  Future<void> _editConfig(
    BuildContext context, WidgetRef ref, VpnConfig config) async {
    final controller = TextEditingController(text: config.rawUri ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Редактировать URI'),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          child: TextField(
            controller: controller,
            maxLines: 5,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              hintText: 'vless://...',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сохранить', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty) {
      final updated = VlessParser.parseUri(controller.text.trim());
      if (updated != null) {
        final renamed = VpnConfig(
          id: config.id,
          name: updated.name,
          protocol: updated.protocol,
          address: updated.address,
          port: updated.port,
          uuid: updated.uuid,
          security: updated.security,
          transport: updated.transport,
          sni: updated.sni,
          wsPath: updated.wsPath,
          wsHost: updated.wsHost,
          grpcServiceName: updated.grpcServiceName,
          publicKey: updated.publicKey,
          shortId: updated.shortId,
          spiderX: updated.spiderX,
          flow: updated.flow,
          encryption: updated.encryption,
          createdAt: config.createdAt,
          rawUri: controller.text.trim(),
          latencyMs: config.latencyMs,
          subscriptionId: config.subscriptionId,
        );
        ref.read(configProvider.notifier).updateConfig(renamed);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось распознать URI')),
        );
      }
    }
  }

  Future<void> _deleteConfig(
    BuildContext context, WidgetRef ref, VpnConfig config) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Удалить?'),
        content: Text('Конфигурация "${config.name}" будет удалена.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(configProvider.notifier).removeConfig(config.id);
    }
  }

  Future<void> _refreshSubscription(
    BuildContext context, WidgetRef ref, Subscription sub, {bool allowSelfSigned = false}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await ref.read(configProvider.notifier).addSubscriptionFromUrl(
        sub.url,
        name: sub.name,
        allowSelfSigned: allowSelfSigned,
      );
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Подписка обновлена')),
        );
      }
    } on UntrustedCertificateException catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // close loading spinner
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ненадёжный сертификат'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Сервер использует самоподписанный или неизвестный сертификат. '
                'Соединение может быть небезопасным.',
              ),
              const SizedBox(height: 12),
              Text('Сервер: ${e.host}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              Text('Сертификат: ${e.subject}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              Text('Издатель: ${e.issuer}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              const SizedBox(height: 12),
              const Text('Продолжить всё равно?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Продолжить'),
            ),
          ],
        ),
      );
      if (confirmed == true && context.mounted) {
        await _refreshSubscription(context, ref, sub, allowSelfSigned: true);
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка обновления: $e')),
        );
      }
    }
  }

  Future<void> _renameSubscription(
    BuildContext context, WidgetRef ref, Subscription sub) async {
    final controller = TextEditingController(text: sub.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Переименовать подписку'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Имя',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сохранить', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty) {
      await ref.read(configProvider.notifier).renameSubscription(sub.id, controller.text.trim());
    }
  }

  Future<void> _editSubscriptionUrl(
    BuildContext context, WidgetRef ref, Subscription sub) async {
    final controller = TextEditingController(text: sub.url);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Изменить URL подписки'),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          child: TextField(
            controller: controller,
            maxLines: 3,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'URL',
              hintText: 'https://...',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сохранить и обновить', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty) {
      // Update subscription URL and re-fetch
      final updatedUrl = controller.text.trim();
      // Remove old configs
      await ConfigNotifier.storage.removeSubscription(sub.id);
      // Re-add with new URL
      try {
        await ref.read(configProvider.notifier).addSubscriptionFromUrl(updatedUrl, name: sub.name);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Подписка обновлена по новому URL')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка обновления: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteSubscription(
    BuildContext context, WidgetRef ref, Subscription sub) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Удалить подписку?'),
        content: Text('Подписка "${sub.name}" и все её конфигурации будут удалены.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(configProvider.notifier).removeSubscription(sub.id);
    }
  }

  void _openAddConfig(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddConfigScreen()),
    );
  }
}

// ─── Subscription Group ─────────────────────────────────────────

class _SubscriptionGroup extends StatelessWidget {
  final Subscription subscription;
  final List<VpnConfig> configs;
  final String? activeConfigId;
  final bool isExpanded;
  final VpnState vpnState;
  final VoidCallback onToggle;
  final VoidCallback onRefresh;
  final VoidCallback onRename;
  final VoidCallback onEditUrl;
  final VoidCallback onDelete;
  final void Function(VpnConfig) onSelectConfig;
  final void Function(VpnConfig) onConfigLongPress;

  const _SubscriptionGroup({
    required this.subscription,
    required this.configs,
    required this.activeConfigId,
    required this.isExpanded,
    required this.vpnState,
    required this.onToggle,
    required this.onRefresh,
    required this.onRename,
    required this.onEditUrl,
    required this.onDelete,
    required this.onSelectConfig,
    required this.onConfigLongPress,
  });

  String get _lastRefresh {
    final at = subscription.lastFetchedAt;
    if (at == null) return 'Не обновлялась';
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'Только что';
    if (diff.inHours < 1) return '${diff.inMinutes} мин назад';
    if (diff.inDays < 1) return '${diff.inHours} ч назад';
    return '${diff.inDays} д назад';
  }

  String? get _expireLabel {
    final exp = subscription.expireAt;
    if (exp == null) return null;
    final days = exp.difference(DateTime.now()).inDays;
    if (days < 0) return 'Истёк';
    if (days == 0) return 'Истекает сегодня';
    return 'Ещё $days д';
  }

  Color get _expireColor {
    final exp = subscription.expireAt;
    if (exp == null) return AppColors.textSecondary;
    final days = exp.difference(DateTime.now()).inDays;
    if (days < 0) return AppColors.error;
    if (days <= 7) return AppColors.error;
    if (days <= 14) return AppColors.connecting;
    return AppColors.connected;
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} ГБ';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} МБ';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} КБ';
  }

  @override
  Widget build(BuildContext context) {
    final expireLabel = _expireLabel;
    final hasTraffic = subscription.totalBytes != null;
    final announce = subscription.announce;
    final announceUrl = subscription.announceUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        GestureDetector(
          onTap: onToggle,
          onLongPress: () => _showSubSubMenu(context),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.rss_feed_rounded, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subscription.name,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '${configs.length} конф. • $_lastRefresh',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (expireLabel != null) ...[
                      const SizedBox(width: 6),
                      _ExpiryBadge(label: expireLabel, color: _expireColor),
                    ],
                    const SizedBox(width: 4),
                    _SubAction(Icons.refresh_rounded, onRefresh),
                    const SizedBox(width: 4),
                    _SubAction(Icons.more_vert_rounded, () => _showSubSubMenu(context)),
                  ],
                ),
                // Traffic bar
                if (hasTraffic) ...[
                  const SizedBox(height: 8),
                  _TrafficBar(
                    upload: subscription.uploadBytes ?? 0,
                    download: subscription.downloadBytes ?? 0,
                    total: subscription.totalBytes!,
                    formatBytes: _formatBytes,
                  ),
                ],
                // Announce message + link
                if (announce != null && announce.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _AnnounceBanner(
                    message: announce,
                    url: announceUrl,
                  ),
                ],
              ],
            ),
          ),
        ),
        // Configs
        if (isExpanded) ...[
          const SizedBox(height: 8),
          ...configs.map((c) {
            final isActive = c.id == activeConfigId;
            final isConnected = vpnState == VpnState.connected && isActive;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ConfigCard(
                config: c,
                isActive: isActive,
                isConnected: isConnected,
                onTap: () => onSelectConfig(c),
                onLongPress: () => onConfigLongPress(c),
              ),
            );
          }),
        ],
      ],
    );
  }

  Future<void> _showSubSubMenu(BuildContext context) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.of(context).size.width - 220,
        MediaQuery.of(context).padding.top + kToolbarHeight,
        20,
        0,
      ),
      items: const [
        PopupMenuItem(value: 'rename', child: _MenuRow(Icons.edit_rounded, 'Переименовать')),
        PopupMenuItem(value: 'edit_url', child: _MenuRow(Icons.link_rounded, 'Изменить URL')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'copy_url', child: _MenuRow(Icons.copy_rounded, 'Копировать URL')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'refresh', child: _MenuRow(Icons.refresh_rounded, 'Обновить')),
        PopupMenuItem(value: 'delete', child: _MenuRow(Icons.delete_rounded, 'Удалить', color: AppColors.error)),
      ],
      color: AppColors.surfaceElevated,
    );

    switch (result) {
      case 'rename': onRename(); break;
      case 'edit_url': onEditUrl(); break;
      case 'copy_url':
        await Clipboard.setData(ClipboardData(text: subscription.url));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('URL скопирован'), duration: Duration(seconds: 1)),
          );
        }
        break;
      case 'refresh': onRefresh(); break;
      case 'delete': onDelete(); break;
    }
  }
}

class _SubAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _SubAction(this.icon, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.surfaceHighlight,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: AppColors.textSecondary),
      ),
    );
  }
}

// ─── Standalone Section ─────────────────────────────────────────

class _StandaloneSection extends StatelessWidget {
  final List<VpnConfig> configs;
  final String? activeConfigId;
  final VpnState vpnState;
  final void Function(VpnConfig) onSelectConfig;
  final void Function(VpnConfig) onConfigLongPress;

  const _StandaloneSection({
    required this.configs,
    required this.activeConfigId,
    required this.vpnState,
    required this.onSelectConfig,
    required this.onConfigLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Отдельные конфигурации',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ),
        ...configs.map((c) {
          final isActive = c.id == activeConfigId;
          final isConnected = vpnState == VpnState.connected && isActive;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ConfigCard(
              config: c,
              isActive: isActive,
              isConnected: isConnected,
              onTap: () => onSelectConfig(c),
              onLongPress: () => onConfigLongPress(c),
            ),
          );
        }),
      ],
    );
  }
}

// ─── Helpers ────────────────────────────────────────────────────

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _MenuRow(this.icon, this.label, {this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color ?? AppColors.textPrimary),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: color ?? AppColors.textPrimary)),
      ],
    );
  }
}

class _ExpiryBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _ExpiryBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _TrafficBar extends StatelessWidget {
  final int upload;
  final int download;
  final int total;
  final String Function(int) formatBytes;
  const _TrafficBar({
    required this.upload,
    required this.download,
    required this.total,
    required this.formatBytes,
  });

  @override
  Widget build(BuildContext context) {
    final used = upload + download;
    final ratio = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
    final barColor = ratio > 0.9
        ? AppColors.error
        : ratio > 0.75
            ? AppColors.connecting
            : AppColors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Трафик: ${formatBytes(used)} / ${formatBytes(total)}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            Text(
              '${(ratio * 100).toStringAsFixed(0)}%',
              style: TextStyle(color: barColor, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 4,
            backgroundColor: AppColors.surfaceHighlight,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
      ],
    );
  }
}

class _AnnounceBanner extends StatelessWidget {
  final String message;
  final String? url;
  const _AnnounceBanner({required this.message, this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
          if (url != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () {
                final uri = Uri.tryParse(url!);
                if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.4), width: 0.5),
                ),
                child: const Text(
                  'Продлить',
                  style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.vpn_key_outlined,
              color: AppColors.textDisabled,
              size: 36,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Нет конфигураций',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Добавьте конфигурацию или подписку\nдля подключения',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Добавить'),
          ),
        ],
      ),
    );
  }
}
