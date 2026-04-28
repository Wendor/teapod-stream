import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/models/vpn_config.dart';
import '../../core/services/config_storage_service.dart';
import '../../core/services/subscription_service.dart';
import '../../protocols/xray/vless_parser.dart';
import '../../providers/config_provider.dart';
import '../../providers/vpn_provider.dart';
import '../../core/interfaces/vpn_engine.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/hero_panel.dart';
import 'add_config_screen.dart';

class ConfigsScreen extends ConsumerStatefulWidget {
  const ConfigsScreen({super.key});

  @override
  ConsumerState<ConfigsScreen> createState() => _ConfigsScreenState();
}

class _ConfigsScreenState extends ConsumerState<ConfigsScreen> {
  final Set<String> _expandedSubs = {};
  bool _isPinging = false;
  bool _isRefreshingAll = false;

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final configStateAsync = ref.watch(configProvider);
    final vpnState = ref.watch(vpnProvider);
    final t = Theme.of(context).extension<TeapodTokens>()!;

    // Auto-expand subscription containing active config
    ref.listen<AsyncValue<ConfigState>>(configProvider, (prev, next) {
      next.whenData((cs) {
        final id = cs.activeConfigId;
        if (id == null) return;
        final prevId = prev?.maybeWhen(
            data: (d) => d.activeConfigId, orElse: () => null);
        if (id == prevId && prev != null) return;
        for (final entry in cs.configsBySubscription.entries) {
          if (entry.value.any((c) => c.id == id)) {
            if (!_expandedSubs.contains(entry.key)) {
              setState(() => _expandedSubs.add(entry.key));
            }
            break;
          }
        }
      });
    });

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Console header strip
            _CfgHeaderStrip(
              t: t,
              total: configStateAsync.maybeWhen(
                data: (d) => d.configs.length + d.subscriptions.length,
                orElse: () => 0,
              ),
              isPinging: _isPinging,
              onPing: configStateAsync.maybeWhen(
                data: (s) =>
                    s.configs.isNotEmpty ? () => _pingAll(s.configs) : null,
                orElse: () => null,
              ),
            ),

            // Title panel
            _CfgTitlePanel(
              t: t,
              onAdd: () => _openAddConfig(context),
              onRefreshAll: configStateAsync.maybeWhen(
                data: (s) => s.subscriptions.isNotEmpty ? _refreshAllSubscriptions : null,
                orElse: () => null,
              ),
              isRefreshing: _isRefreshingAll,
            ),

            // List body
            Expanded(
              child: configStateAsync.when(
                loading: () => Center(
                  child: CircularProgressIndicator(
                    color: t.accent,
                    strokeWidth: 1.5,
                  ),
                ),
                error: (e, _) => Center(
                  child: Text('Ошибка: $e',
                      style: AppTheme.mono(size: 12, color: t.danger)),
                ),
                data: (configState) {
                  if (configState.configs.isEmpty &&
                      configState.subscriptions.isEmpty) {
                    return _EmptyState(onAdd: () => _openAddConfig(context));
                  }

                  final items = <Widget>[];

                  // [subs] section
                  if (configState.subscriptions.isNotEmpty) {
                    items.add(_SectionHeader(
                      t: t,
                      label: '[subs]',
                      count: configState.subscriptions.length,
                    ));
                    for (var i = 0; i < configState.subscriptions.length; i++) {
                      final sub = configState.subscriptions[i];
                      final subConfigs =
                          configState.configsBySubscription[sub.id] ?? [];
                      final isExpanded = _expandedSubs.contains(sub.id);
                      items.add(_SubRow(
                        t: t,
                        sub: sub,
                        configs: subConfigs,
                        addr: i + 1,
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
                        onRefresh: () =>
                            _refreshSubscription(context, ref, sub),
                        onRename: () =>
                            _renameSubscription(context, ref, sub),
                        onEditUrl: () =>
                            _editSubscriptionUrl(context, ref, sub),
                        onDelete: () =>
                            _deleteSubscription(context, ref, sub),
                        onSelectConfig: (c) => _selectConfig(ref, c),
                        onConfigLongPress: (c) =>
                            _showConfigMenu(context, ref, c),
                      ));
                    }
                  }

                  // [standalone] section
                  if (configState.standaloneConfigs.isNotEmpty) {
                    items.add(_SectionHeader(
                      t: t,
                      label: '[standalone]',
                      count: configState.standaloneConfigs.length,
                    ));
                    final offset = configState.subscriptions.length + 1;
                    for (var i = 0;
                        i < configState.standaloneConfigs.length;
                        i++) {
                      final c = configState.standaloneConfigs[i];
                      items.add(_ConfigRow(
                        t: t,
                        config: c,
                        addr: offset + i,
                        isActive: c.id == configState.activeConfigId,
                        onTap: () => _selectConfig(ref, c),
                        onLongPress: () =>
                            _showConfigMenu(context, ref, c),
                      ));
                    }
                  }

                  return ListView(
                    padding: EdgeInsets.zero,
                    children: items,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Actions (unchanged logic) ──────────────────────────────────

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
    final t = Theme.of(context).extension<TeapodTokens>()!;
    await showModalBottomSheet(
      context: context,
      backgroundColor: t.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(config.name,
                        style: AppTheme.sans(
                            size: 16, color: t.text, weight: FontWeight.w500)),
                  ),
                  Text(config.protocol.name.toUpperCase(),
                      style: AppTheme.mono(size: 10, color: t.textMuted)),
                ],
              ),
            ),
            Container(height: 1, color: t.line),
            _SheetTile(t: t, label: 'Переименовать', onTap: () async {
              Navigator.pop(ctx);
              if (!context.mounted) return;
              await _renameConfig(context, ref, config);
            }),
            _SheetTile(t: t, label: 'Редактировать URI', onTap: () async {
              Navigator.pop(ctx);
              if (!context.mounted) return;
              await _editConfig(context, ref, config);
            }),
            _SheetTile(t: t, label: 'Копировать URL', onTap: () async {
              Navigator.pop(ctx);
              if (config.rawUri != null) {
                await Clipboard.setData(ClipboardData(text: config.rawUri!));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('URL скопирован'),
                      duration: Duration(seconds: 1)));
                }
              }
            }),
            _SheetTile(t: t, label: 'Поделиться', onTap: () async {
              Navigator.pop(ctx);
              if (config.rawUri != null) await Share.share(config.rawUri!);
            }),
            _SheetTile(t: t, label: 'Удалить', color: t.danger, onTap: () async {
              Navigator.pop(ctx);
              if (!context.mounted) return;
              await _deleteConfig(context, ref, config);
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _renameConfig(
      BuildContext context, WidgetRef ref, VpnConfig config) async {
    final controller = TextEditingController(text: config.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty) {
      ref.read(configProvider.notifier)
          .updateConfig(config.copyWith(name: controller.text.trim()));
    }
  }

  Future<void> _editConfig(
      BuildContext context, WidgetRef ref, VpnConfig config) async {
    final controller = TextEditingController(text: config.rawUri ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить')),
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
        title: const Text('Удалить?'),
        content: Text('Конфигурация "${config.name}" будет удалена.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.danger),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(configProvider.notifier).removeConfig(config.id);
    }
  }

  Future<void> _refreshSubscription(
      BuildContext context, WidgetRef ref, Subscription sub,
      {bool allowSelfSigned = false}) async {
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
      Navigator.pop(context);
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
                  'Соединение может быть небезопасным.'),
              const SizedBox(height: 12),
              Text('Сервер: ${e.host}',
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12)),
              Text('Сертификат: ${e.subject}',
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12)),
              Text('Издатель: ${e.issuer}',
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12)),
              const SizedBox(height: 12),
              const Text('Продолжить всё равно?'),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Продолжить')),
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
        title: const Text('Переименовать подписку'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Имя', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty) {
      await ref
          .read(configProvider.notifier)
          .renameSubscription(sub.id, controller.text.trim());
    }
  }

  Future<void> _editSubscriptionUrl(
      BuildContext context, WidgetRef ref, Subscription sub) async {
    final controller = TextEditingController(text: sub.url);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить и обновить')),
        ],
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty) {
      final updatedUrl = controller.text.trim();
      await ConfigNotifier.storage.removeSubscription(sub.id);
      try {
        await ref
            .read(configProvider.notifier)
            .addSubscriptionFromUrl(updatedUrl, name: sub.name);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Подписка обновлена по новому URL')),
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
        title: const Text('Удалить подписку?'),
        content: Text(
            'Подписка "${sub.name}" и все её конфигурации будут удалены.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.danger),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(configProvider.notifier).removeSubscription(sub.id);
    }
  }

  Future<void> _refreshAllSubscriptions() async {
    if (_isRefreshingAll) return;
    setState(() => _isRefreshingAll = true);
    try {
      final configState = ref.read(configProvider).maybeWhen(data: (d) => d, orElse: () => null);
      if (configState == null) return;
      for (final sub in configState.subscriptions) {
        try {
          await ref.read(configProvider.notifier).addSubscriptionFromUrl(
            sub.url,
            name: sub.name,
          );
        } catch (_) {}
      }
    } finally {
      if (mounted) setState(() => _isRefreshingAll = false);
    }
  }

  void _openAddConfig(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddConfigScreen()),
    );
  }
}

// ── Console header strip ──────────────────────────────────────────

class _CfgHeaderStrip extends StatelessWidget {
  final TeapodTokens t;
  final int total;
  final bool isPinging;
  final VoidCallback? onPing;

  const _CfgHeaderStrip({
    required this.t,
    required this.total,
    required this.isPinging,
    this.onPing,
  });

  @override
  Widget build(BuildContext context) {
    final totalStr = total.toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('teapod.stream // configs',
              style: AppTheme.mono(
                  size: 10, color: t.textMuted, letterSpacing: 1)),
          Row(
            children: [
              if (isPinging)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      color: t.accent, strokeWidth: 1.2),
                )
              else if (onPing != null)
                GestureDetector(
                  onTap: onPing,
                  child: Text('ping',
                      style: AppTheme.mono(
                          size: 10, color: t.accent, letterSpacing: 1)),
                ),
              const SizedBox(width: 12),
              Text('total [$totalStr]',
                  style: AppTheme.mono(
                      size: 10, color: t.textMuted, letterSpacing: 1)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Title panel ───────────────────────────────────────────────────

class _CfgTitlePanel extends StatelessWidget {
  final TeapodTokens t;
  final VoidCallback onAdd;
  final VoidCallback? onRefreshAll;
  final bool isRefreshing;

  const _CfgTitlePanel({
    required this.t,
    required this.onAdd,
    this.onRefreshAll,
    this.isRefreshing = false,
  });

  @override
  Widget build(BuildContext context) {
    return HeroPanel(
      t: t,
      tagline: 'КОНФИГУРАЦИИ · VPN · XRAY',
      title: 'CONFIGS',
      subtitle: Text('subs · standalone · imported',
          style: AppTheme.mono(size: 11, color: t.textDim, letterSpacing: 0.5)),
      trailing: Row(
        children: [
          if (isRefreshing)
            SizedBox(
              width: 32, height: 32,
              child: Center(
                child: SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(color: t.textDim, strokeWidth: 1.2),
                ),
              ),
            )
          else
            _IconBtn(t: t, icon: Icons.refresh_rounded, accent: false, onTap: onRefreshAll),
          const SizedBox(width: 6),
          _IconBtn(t: t, icon: Icons.add_rounded, accent: true, onTap: onAdd),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final TeapodTokens t;
  final IconData icon;
  final bool accent;
  final VoidCallback? onTap;

  const _IconBtn({
    required this.t,
    required this.icon,
    required this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: accent ? t.accent : Colors.transparent,
          border: Border.all(color: accent ? t.accent : t.line),
        ),
        child: Icon(icon,
            size: 14, color: accent ? t.bg : t.textDim),
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final TeapodTokens t;
  final String label;
  final int count;

  const _SectionHeader(
      {required this.t, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.lineSoft))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: AppTheme.mono(
                  size: 10, color: t.textMuted, letterSpacing: 1)),
          Text('${count.toString().padLeft(2, '0')} rows',
              style: AppTheme.mono(
                  size: 10, color: t.textMuted, letterSpacing: 1)),
        ],
      ),
    );
  }
}

// ── Subscription row ──────────────────────────────────────────────

class _SubRow extends StatelessWidget {
  final TeapodTokens t;
  final Subscription sub;
  final List<VpnConfig> configs;
  final int addr;
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

  const _SubRow({
    required this.t,
    required this.sub,
    required this.configs,
    required this.addr,
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
    final at = sub.lastFetchedAt;
    if (at == null) return 'Не обновлялась';
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'Только что';
    if (diff.inHours < 1) return '${diff.inMinutes} мин назад';
    if (diff.inDays < 1) return '${diff.inHours} ч назад';
    return '${diff.inDays} д назад';
  }

  String? get _expireLabel {
    final exp = sub.expireAt;
    if (exp == null) return null;
    final days = exp.difference(DateTime.now()).inDays;
    if (days < 0) return 'Истёк';
    if (days == 0) return 'expires:today';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hexAddr = '0x${addr.toString().padLeft(2, '0')}';
    final expireLabel = _expireLabel;

    return Column(
      children: [
        // Sub header row
        GestureDetector(
          onTap: onToggle,
          onLongPress: () => _showSubMenu(context),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 11, 20, 11),
            decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.lineSoft))),
            child: Row(
              children: [
                // Addr
                SizedBox(
                  width: 32,
                  child: Text(hexAddr,
                      style: AppTheme.mono(
                          size: 10, color: t.textMuted)),
                ),
                const SizedBox(width: 10),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sub.name,
                          style: AppTheme.sans(
                              size: 13,
                              weight: FontWeight.w500,
                              color: t.text,
                              letterSpacing: -0.2)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text('cnt=${configs.length}',
                              style: AppTheme.mono(
                                  size: 10, color: t.textMuted)),
                          Text(' · $_lastRefresh',
                              style: AppTheme.mono(
                                  size: 10, color: t.textMuted)),
                          if (expireLabel != null) ...[
                            Text(' · ',
                                style: AppTheme.mono(
                                    size: 10, color: t.textMuted)),
                            Text(expireLabel,
                                style: AppTheme.mono(
                                    size: 10, color: t.danger)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Refresh + chevron
                GestureDetector(
                  onTap: onRefresh,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 18),
                    child: Icon(Icons.refresh_rounded,
                        size: 16, color: t.textMuted),
                  ),
                ),
                Icon(
                  isExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 16,
                  color: t.textMuted,
                ),
              ],
            ),
          ),
        ),

        // Expanded: sub configs + optional renew footer
        if (isExpanded)
          Container(
            color: t.bgSunken,
            child: Column(
              children: [
                if (sub.expireAt != null &&
                    sub.expireAt!.difference(DateTime.now()).inDays <= 0)
                  Container(
                    padding: const EdgeInsets.fromLTRB(52, 10, 20, 12),
                    decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: t.lineSoft))),
                    child: Row(
                      children: [
                        Icon(Icons.bolt_rounded, size: 11, color: t.accent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('trial // renew subscription',
                              style: AppTheme.mono(
                                  size: 11, color: t.textDim)),
                        ),
                        GestureDetector(
                          onTap: onRefresh,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            color: t.line,
                            child: Text('RENEW',
                                style: AppTheme.mono(
                                    size: 10, color: t.textDim, letterSpacing: 1)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ...configs.asMap().entries.map((e) {
                  final c = e.value;
                  return _ConfigRow(
                    t: t,
                    config: c,
                    addr: addr * 100 + e.key + 1,
                    isActive: c.id == activeConfigId,
                    indent: false,
                    onTap: () => onSelectConfig(c),
                    onLongPress: () => onConfigLongPress(c),
                  );
                })
                ],
            ),
          ),
      ],
    );
  }

  Future<void> _showSubMenu(BuildContext context) async {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    await showModalBottomSheet(
      context: context,
      backgroundColor: t.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(sub.name,
                        style: AppTheme.sans(
                            size: 16, color: t.text, weight: FontWeight.w500)),
                  ),
                  Text('sub · ${configs.length} конфигов',
                      style: AppTheme.mono(size: 10, color: t.textMuted)),
                ],
              ),
            ),
            Container(height: 1, color: t.line),
            _SheetTile(t: t, label: 'Переименовать', onTap: () {
              Navigator.pop(ctx);
              onRename();
            }),
            _SheetTile(t: t, label: 'Изменить URL', onTap: () {
              Navigator.pop(ctx);
              onEditUrl();
            }),
            _SheetTile(t: t, label: 'Копировать URL', onTap: () async {
              Navigator.pop(ctx);
              await Clipboard.setData(ClipboardData(text: sub.url));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('URL скопирован'),
                    duration: Duration(seconds: 1)));
              }
            }),
            _SheetTile(t: t, label: 'Обновить', onTap: () {
              Navigator.pop(ctx);
              onRefresh();
            }),
            _SheetTile(t: t, label: 'Удалить', color: t.danger, onTap: () {
              Navigator.pop(ctx);
              onDelete();
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Config row (standalone + sub-inner) ───────────────────────────

class _ConfigRow extends StatelessWidget {
  final TeapodTokens t;
  final VpnConfig config;
  final int addr;
  final bool isActive;
  final bool indent;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ConfigRow({
    required this.t,
    required this.config,
    required this.addr,
    required this.isActive,
    required this.onTap,
    required this.onLongPress,
    this.indent = false,
  });

  String get _protoTag {
    switch (config.protocol) {
      case VpnProtocol.vless:       return 'VLESS';
      case VpnProtocol.vmess:       return 'VMESS';
      case VpnProtocol.trojan:      return 'TROJAN';
      case VpnProtocol.shadowsocks: return 'SS';
      case VpnProtocol.hysteria2:   return 'HY2';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hexAddr =
        '0x${addr.toString().padLeft(2, '0')}';
    final ping = config.latencyMs;
    final tagColor = isActive ? t.accent : t.textDim;
    final tagBorder = isActive ? t.accent : t.line;
    final leftPad = indent ? 52.0 : 20.0;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: isActive ? t.accentFade : Colors.transparent,
          border: Border(bottom: BorderSide(color: t.lineSoft)),
        ),
        child: Stack(
          children: [
            // Active left bar
            if (isActive)
              Positioned(
                left: 0, top: 0, bottom: 0,
                child: Container(width: 2, color: t.accent),
              ),

            Padding(
              padding: EdgeInsets.fromLTRB(leftPad, 11, 20, 11),
              child: Row(
                children: [
                  // Addr
                  SizedBox(
                    width: 32,
                    child: Text(hexAddr,
                        style: AppTheme.mono(
                            size: 10, color: t.textMuted)),
                  ),
                  const SizedBox(width: 10),

                  // Proto tag
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      border: Border.all(color: tagBorder),
                    ),
                    constraints: const BoxConstraints(minWidth: 44),
                    child: Text(
                      _protoTag,
                      textAlign: TextAlign.center,
                      style: AppTheme.mono(
                          size: 10, color: tagColor, letterSpacing: 1),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Name + host
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          config.name,
                          style: AppTheme.sans(
                              size: 13,
                              weight: FontWeight.w500,
                              color: t.text,
                              letterSpacing: -0.2),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${config.address}:${config.port}',
                          style: AppTheme.mono(
                              size: 10, color: t.textMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Ping
                  if (ping != null)
                    Text(
                      '${ping}ms',
                      style: AppTheme.mono(
                          size: 11, color: t.accent),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────

class _SheetTile extends StatelessWidget {
  final TeapodTokens t;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _SheetTile({required this.t, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.lineSoft))),
        child: Text(label,
            style: AppTheme.sans(size: 14, color: color ?? t.text)),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('[ no configs ]',
              style: AppTheme.mono(size: 14, color: t.textMuted,
                  letterSpacing: 1)),
          const SizedBox(height: 20),
          Text(
            'Добавьте конфигурацию\nили подписку',
            textAlign: TextAlign.center,
            style: AppTheme.sans(size: 14, color: t.textDim),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: t.accent,
              ),
              child: Text('+ ADD CONFIG',
                  style: AppTheme.mono(
                      size: 11, color: t.bg, letterSpacing: 1)),
            ),
          ),
        ],
      ),
    );
  }
}
