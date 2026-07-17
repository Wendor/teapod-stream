import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/connections_bundle.dart';
import '../../core/models/vpn_config.dart';
import '../../core/models/pinned_ref.dart';
import '../../core/services/config_storage_service.dart';
import '../../core/services/subscription_service.dart';
import '../../protocols/xray/vless_parser.dart';
import '../../providers/config_provider.dart';
import '../../providers/vpn_provider.dart';
import '../../core/interfaces/vpn_engine.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/hero_panel.dart';
import '../widgets/pressable.dart';
import 'add_config_screen.dart';
import 'subscription_settings_screen.dart';

class ConfigsScreen extends ConsumerStatefulWidget {
  const ConfigsScreen({super.key});

  @override
  ConsumerState<ConfigsScreen> createState() => _ConfigsScreenState();
}

class _ConfigsScreenState extends ConsumerState<ConfigsScreen> {
  final Set<String> _expandedSubs = {};
  bool _isPinging = false;
  bool _isRefreshingAll = false;
  bool _hideGroups = false;
  bool _sortByPing = false;
  bool _sortMode = false; // явный режим ручной сортировки (не персистится)

  static const _keyHideGroups = 'cfg_hide_groups';
  static const _keySortByPing = 'cfg_sort_by_ping';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hideGroups = prefs.getBool(_keyHideGroups) ?? false;
      _sortByPing = prefs.getBool(_keySortByPing) ?? false;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHideGroups, _hideGroups);
    await prefs.setBool(_keySortByPing, _sortByPing);
  }

  List<VpnConfig> _applySort(List<VpnConfig> configs) {
    if (!_sortByPing) return configs;
    return [...configs]..sort((a, b) {
        if (a.latencyMs == null && b.latencyMs == null) return 0;
        if (a.latencyMs == null) return 1;
        if (b.latencyMs == null) return -1;
        return a.latencyMs!.compareTo(b.latencyMs!);
      });
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final configStateAsync = ref.watch(configProvider);
    final vpnState = ref.watch(vpnProvider);
    final t = Theme.of(context).extension<TeapodTokens>()!;

    ref.listen<AsyncValue<ConfigState>>(configProvider, (prev, next) {
      next.whenData((cs) {
        final id = cs.activeConfigId;
        if (id == null) return;
        final prevId = prev?.maybeWhen(data: (d) => d.activeConfigId, orElse: () => null);
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
            _CfgHeaderStrip(
              t: t,
              total: configStateAsync.maybeWhen(
                data: (d) => d.configs.length + d.subscriptions.length,
                orElse: () => 0,
              ),
              isPinging: _isPinging,
              onPing: configStateAsync.maybeWhen(
                data: (s) => s.configs.isNotEmpty ? () => _pingAll(s.configs) : null,
                orElse: () => null,
              ),
            ),
            _CfgTitlePanel(
              t: t,
              onAdd: () => _openAddConfig(context),
              onRefreshAll: configStateAsync.maybeWhen(
                data: (s) => s.subscriptions.isNotEmpty ? _refreshAllSubscriptions : null,
                orElse: () => null,
              ),
              isRefreshing: _isRefreshingAll,
              onSettings: () => _showSettingsSheet(context, t),
              onSubSettings: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const SubscriptionSettingsScreen(breadcrumbParent: 'configs'),
                ),
              ),
              onExport: configStateAsync.maybeWhen(
                data: (s) => s.configs.isNotEmpty ? () => _exportAll(s.configs) : null,
                orElse: () => null,
              ),
            ),
            Expanded(
              child: configStateAsync.when(
                loading: () => Center(
                  child: CircularProgressIndicator(color: t.accent, strokeWidth: 1.5),
                ),
                error: (e, _) => Center(
                  child: Text('Ошибка: $e',
                      style: AppTheme.mono(size: 12, color: t.danger)),
                ),
                data: (cs) => _buildBody(context, cs, vpnState, t),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ConfigState cs, VpnState2 vpnState, TeapodTokens t) {
    if (cs.configs.isEmpty && cs.subscriptions.isEmpty) {
      return _EmptyState(onAdd: () => _openAddConfig(context));
    }
    if (_hideGroups) return _buildFlatList(context, cs, vpnState, t);
    return _buildGroupedList(context, cs, vpnState, t);
  }

  Widget _buildFlatList(BuildContext context, ConfigState cs, VpnState2 vpnState, TeapodTokens t) {
    final allConfigs = _applySort([
      ...cs.standaloneConfigs,
      for (final s in cs.subscriptions) ...(cs.configsBySubscription[s.id] ?? []),
    ]);
    final hasPins = cs.pins.isNotEmpty;
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: allConfigs.length + (hasPins ? 1 : 0),
      itemBuilder: (_, index) {
        if (hasPins && index == 0) {
          return _PinnedGroup(
            key: const Key('__pinned__'),
            t: t,
            pins: cs.resolvedPins,
            activeConfigId: cs.activeConfigId,
            onSelectConfig: (c) => _selectConfig(ref, c),
            onConfigMenu: (c) => _showConfigMenu(context, ref, c),
            onUnpin: (p) => ref.read(configProvider.notifier).unpin(p),
          );
        }
        final i = hasPins ? index - 1 : index;
        final c = allConfigs[i];
        return _ConfigRow(
          key: ValueKey(c.id),
          t: t,
          config: c,
          addr: i + 1,
          isActive: c.id == cs.activeConfigId,
          onTap: () => _selectConfig(ref, c),
          onLongPress: () => _showConfigMenu(context, ref, c),
        );
      },
    );
  }

  Widget _buildGroupedList(BuildContext context, ConfigState cs, VpnState2 vpnState, TeapodTokens t) {
    final standalone = _applySort(cs.standaloneConfigs);
    final subs = cs.subscriptions;
    final pinnedOffset = cs.pins.isNotEmpty ? 1 : 0;
    final localOffset = pinnedOffset + (standalone.isNotEmpty ? 1 : 0);
    final canReorderSubs = _sortMode && !_sortByPing && subs.length > 1;

    final pinnedGroup = cs.pins.isNotEmpty
        ? _PinnedGroup(
            key: const Key('__pinned__'),
            t: t,
            pins: cs.resolvedPins,
            activeConfigId: cs.activeConfigId,
            onSelectConfig: (c) => _selectConfig(ref, c),
            onConfigMenu: (c) => _showConfigMenu(context, ref, c),
            onUnpin: (p) => ref.read(configProvider.notifier).unpin(p),
          )
        : null;

    if (subs.isEmpty) {
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          ?pinnedGroup,
          if (standalone.isNotEmpty)
            _LocalGroup(
              key: const Key('__local__'),
              t: t,
              configs: standalone,
              isExpanded: _expandedSubs.contains('__local__'),
              activeConfigId: cs.activeConfigId,
              sortMode: _sortMode && !_sortByPing,
              onToggle: () => setState(() {
                if (_expandedSubs.contains('__local__')) {
                  _expandedSubs.remove('__local__');
                } else {
                  _expandedSubs.add('__local__');
                }
              }),
              onSelectConfig: (c) => _selectConfig(ref, c),
              onConfigMenu: (c) => _showConfigMenu(context, ref, c),
              onReorderConfigs: (o, n) =>
                  ref.read(configProvider.notifier).reorderGroupConfigs(null, o, n),
            ),
        ],
      );
    }

    return ReorderableListView(
      buildDefaultDragHandles: false,
      padding: EdgeInsets.zero,
      onReorder: (old, nw) {
        if (old < localOffset) return;
        final safeNew = nw < localOffset ? localOffset : nw;
        ref
            .read(configProvider.notifier)
            .reorderSubscriptions(old - localOffset, safeNew - localOffset);
      },
      children: [
        ?pinnedGroup,
        if (standalone.isNotEmpty)
          _LocalGroup(
            key: const Key('__local__'),
            t: t,
            configs: standalone,
            isExpanded: _expandedSubs.contains('__local__'),
            activeConfigId: cs.activeConfigId,
            sortMode: _sortMode && !_sortByPing,
            onToggle: () => setState(() {
              if (_expandedSubs.contains('__local__')) {
                _expandedSubs.remove('__local__');
              } else {
                _expandedSubs.add('__local__');
              }
            }),
            onSelectConfig: (c) => _selectConfig(ref, c),
            onConfigMenu: (c) => _showConfigMenu(context, ref, c),
            onReorderConfigs: (o, n) =>
                ref.read(configProvider.notifier).reorderGroupConfigs(null, o, n),
          ),
        for (var i = 0; i < subs.length; i++)
          _SubGroup(
            key: Key(subs[i].id),
            t: t,
            sub: subs[i],
            configs: _applySort(cs.configsBySubscription[subs[i].id] ?? []),
            outerIndex: localOffset + i,
            addr: localOffset + i + 1,
            activeConfigId: cs.activeConfigId,
            isActiveSubscription: cs.activeSubscriptionId == subs[i].id,
            isExpanded: _expandedSubs.contains(subs[i].id),
            vpnState: vpnState.connectionState,
            canReorderGroup: canReorderSubs,
            sortMode: _sortMode && !_sortByPing,
            onToggle: () {
              final id = subs[i].id;
              setState(() {
                if (_expandedSubs.contains(id)) {
                  _expandedSubs.remove(id);
                } else {
                  _expandedSubs.add(id);
                }
              });
            },
            onRefresh: () => _refreshSubscription(context, ref, subs[i]),
            onRename: () => _renameSubscription(context, ref, subs[i]),
            onEditUrl: () => _editSubscriptionUrl(context, ref, subs[i]),
            onDelete: () => _deleteSubscription(context, ref, subs[i]),
            onSelectSubscription: () {
              final id = subs[i].id;
              final isActive = cs.activeSubscriptionId == id;
              ref.read(configProvider.notifier).setActiveSubscription(isActive ? null : id);
            },
            onSelectConfig: (c) => _selectConfig(ref, c),
            onConfigMenu: (c) => _showConfigMenu(context, ref, c),
            onReorderConfigs: (o, n) =>
                ref.read(configProvider.notifier).reorderGroupConfigs(subs[i].id, o, n),
          ),
      ],
    );
  }

  // ── Settings sheet ─────────────────────────────────────────────

  void _showSettingsSheet(BuildContext context, TeapodTokens t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: t.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(children: [
                  Expanded(
                    child: Text('configs // display',
                        style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                  ),
                ]),
              ),
              Container(height: 1, color: t.line),
              _ToggleTile(
                t: t,
                label: 'скрыть группы',
                value: _hideGroups,
                onChanged: (v) {
                  setSheet(() {});
                  setState(() => _hideGroups = v);
                  _savePrefs();
                },
              ),
              _ToggleTile(
                t: t,
                label: 'сортировать по ping',
                value: _sortByPing,
                onChanged: (v) {
                  setSheet(() {});
                  setState(() {
                    _sortByPing = v;
                    if (v) _sortMode = false;
                  });
                  _savePrefs();
                },
              ),
              _ToggleTile(
                t: t,
                label: 'режим сортировки',
                value: _sortMode,
                onChanged: (v) {
                  setSheet(() {});
                  setState(() {
                    _sortMode = v;
                    if (v) _sortByPing = false;
                  });
                  _savePrefs();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────

  void _selectConfig(WidgetRef ref, VpnConfig config) {
    ref.read(configProvider.notifier).setActiveConfig(config.id);
    final vpnState = ref.read(vpnProvider);
    if (vpnState.isConnected || vpnState.isBusy) {
      ref.read(vpnProvider.notifier).reconnectWithNewConfig();
    }
  }

  Future<void> _exportAll(List<VpnConfig> configs) async {
    final cs = ref.read(configProvider).maybeWhen(data: (d) => d, orElse: () => null);
    if (cs == null || cs.configs.isEmpty) return;
    final bundle = ConnectionsBundle(
      exportedAt: DateTime.now(),
      configs: cs.standaloneConfigs,
      subscriptions: cs.subscriptions,
    );
    await Share.share(bundle.toCompactDeeplink(), subject: 'teapod configs');
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

  Future<void> _showConfigMenu(BuildContext context, WidgetRef ref, VpnConfig config) async {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    final isPinned = ref.read(configProvider).maybeWhen(
          data: (d) => d.isPinned(config),
          orElse: () => false,
        );
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
                        style: AppTheme.sans(size: 16, color: t.text, weight: FontWeight.w500)),
                  ),
                  Text(config.protocol.name.toUpperCase(),
                      style: AppTheme.mono(size: 10, color: t.textMuted)),
                ],
              ),
            ),
            Container(height: 1, color: t.line),
            _SheetTile(
              t: t,
              label: isPinned ? 'Открепить' : 'Закрепить',
              onTap: () {
                Navigator.pop(ctx);
                ref.read(configProvider.notifier).togglePin(config);
              },
            ),
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
                      content: Text('URL скопирован'), duration: Duration(seconds: 1)));
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

  Future<void> _renameConfig(BuildContext context, WidgetRef ref, VpnConfig config) async {
    final controller = TextEditingController(text: config.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Переименовать'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Имя', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty) {
      ref.read(configProvider.notifier).updateConfig(config.copyWith(name: controller.text.trim()));
    }
  }

  Future<void> _editConfig(BuildContext context, WidgetRef ref, VpnConfig config) async {
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
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

  Future<void> _deleteConfig(BuildContext context, WidgetRef ref, VpnConfig config) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить?'),
        content: Text('Конфигурация "${config.name}" будет удалена.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(configProvider.notifier).removeConfig(config.id);
    }
  }

  Future<void> _refreshSubscription(BuildContext context, WidgetRef ref, Subscription sub,
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
            const SnackBar(content: Text('Подписка обновлена')));
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
              const Text('Сервер использует самоподписанный или неизвестный сертификат. '
                  'Соединение может быть небезопасным.'),
              const SizedBox(height: 12),
              Text('Сервер: ${e.host}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              Text('Сертификат: ${e.subject}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              Text('Издатель: ${e.issuer}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              const SizedBox(height: 12),
              const Text('Продолжить всё равно?'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Продолжить')),
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

  Future<void> _renameSubscription(BuildContext context, WidgetRef ref, Subscription sub) async {
    final controller = TextEditingController(text: sub.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Переименовать подписку'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Имя', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty) {
      await ref.read(configProvider.notifier).renameSubscription(sub.id, controller.text.trim());
    }
  }

  Future<void> _editSubscriptionUrl(BuildContext context, WidgetRef ref, Subscription sub) async {
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить и обновить')),
        ],
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty) {
      final updatedUrl = controller.text.trim();
      await ConfigNotifier.storage.removeSubscription(sub.id);
      try {
        await ref.read(configProvider.notifier).addSubscriptionFromUrl(updatedUrl, name: sub.name);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Подписка обновлена по новому URL')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Ошибка обновления: $e')));
        }
      }
    }
  }

  Future<void> _deleteSubscription(BuildContext context, WidgetRef ref, Subscription sub) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить подписку?'),
        content: Text('Подписка "${sub.name}" и все её конфигурации будут удалены.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Удалить'),
          ),
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
      final configState =
          ref.read(configProvider).maybeWhen(data: (d) => d, orElse: () => null);
      if (configState == null) return;
      for (final sub in configState.subscriptions) {
        try {
          await ref
              .read(configProvider.notifier)
              .addSubscriptionFromUrl(sub.url, name: sub.name);
        } catch (_) {}
      }
    } finally {
      if (mounted) setState(() => _isRefreshingAll = false);
    }
  }

  void _openAddConfig(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AddConfigScreen()));
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
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('teapod.stream // configs',
              style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
          Row(
            children: [
              if (isPinging)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(color: t.accent, strokeWidth: 1.2),
                )
              else if (onPing != null)
                GestureDetector(
                  onTap: onPing,
                  child: Text('ping',
                      style: AppTheme.mono(size: 10, color: t.accent, letterSpacing: 1)),
                ),
              const SizedBox(width: 12),
              Text('total [$totalStr]',
                  style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
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
  final VoidCallback onSettings;
  final VoidCallback onSubSettings;
  final VoidCallback? onExport;

  const _CfgTitlePanel({
    required this.t,
    required this.onAdd,
    this.onRefreshAll,
    this.isRefreshing = false,
    required this.onSettings,
    required this.onSubSettings,
    this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return HeroPanel(
      t: t,
      tagline: 'КОНФИГУРАЦИИ',
      title: 'CONFIGS',
      subtitle: Text('subs · standalone · imported',
          style: AppTheme.mono(size: 11, color: t.textDim, letterSpacing: 0.5)),
      trailing: Row(
        children: [
          _IconBtn(t: t, icon: Icons.tune_rounded, accent: false, label: 'настройки отображения', onTap: onSettings),
          const SizedBox(width: 6),
          _IconBtn(t: t, icon: Icons.schedule_rounded, accent: false, label: 'настройки подписок', onTap: onSubSettings),
          const SizedBox(width: 6),
          _IconBtn(t: t, icon: Icons.ios_share_rounded, accent: false, label: 'экспорт подключений', onTap: onExport),
          const SizedBox(width: 6),
          if (isRefreshing)
            SizedBox(
              width: 32,
              height: 32,
              child: Center(
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(color: t.textDim, strokeWidth: 1.2),
                ),
              ),
            )
          else
            _IconBtn(t: t, icon: Icons.refresh_rounded, accent: false, label: 'обновить подписки', onTap: onRefreshAll),
          const SizedBox(width: 6),
          _IconBtn(t: t, icon: Icons.add_rounded, accent: true, label: 'добавить', onTap: onAdd),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final TeapodTokens t;
  final IconData icon;
  final bool accent;
  final String label;
  final VoidCallback? onTap;

  const _IconBtn({
    required this.t,
    required this.icon,
    required this.accent,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      enabled: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accent ? t.accent : Colors.transparent,
            border: Border.all(color: accent ? t.accent : t.line),
          ),
          child: Icon(icon, size: 15, color: accent ? t.bg : onTap != null ? t.textDim : t.textMuted),
        ),
      ),
    );
  }
}

// ── [local] group ─────────────────────────────────────────────────

class _LocalGroup extends StatelessWidget {
  final TeapodTokens t;
  final List<VpnConfig> configs;
  final bool isExpanded;
  final String? activeConfigId;
  final bool sortMode;
  final VoidCallback onToggle;
  final void Function(VpnConfig) onSelectConfig;
  final void Function(VpnConfig) onConfigMenu;
  final void Function(int, int) onReorderConfigs;

  const _LocalGroup({
    super.key,
    required this.t,
    required this.configs,
    required this.isExpanded,
    required this.activeConfigId,
    required this.sortMode,
    required this.onToggle,
    required this.onSelectConfig,
    required this.onConfigMenu,
    required this.onReorderConfigs,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 11, 20, 11),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.lineSoft))),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text('[00]',
                      style: AppTheme.mono(size: 10, color: t.textMuted)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('[local]',
                          style: AppTheme.sans(
                              size: 13, weight: FontWeight.w500, color: t.text)),
                      const SizedBox(height: 2),
                      Text('cnt=${configs.length} · standalone',
                          style: AppTheme.mono(size: 10, color: t.textMuted)),
                    ],
                  ),
                ),
                Icon(
                  isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 16,
                  color: t.textMuted,
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Container(
            color: t.bgSunken,
            child: sortMode
                ? ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    onReorder: onReorderConfigs,
                    children: [
                      for (var i = 0; i < configs.length; i++)
                        _ConfigRow(
                          key: ValueKey(configs[i].id),
                          t: t,
                          config: configs[i],
                          addr: i + 1,
                          isActive: configs[i].id == activeConfigId,
                          draggableIndex: i,
                          onTap: () => onSelectConfig(configs[i]),
                          onLongPress: () => onConfigMenu(configs[i]),
                        ),
                    ],
                  )
                : Column(
                    children: [
                      for (var i = 0; i < configs.length; i++)
                        _ConfigRow(
                          key: ValueKey(configs[i].id),
                          t: t,
                          config: configs[i],
                          addr: i + 1,
                          isActive: configs[i].id == activeConfigId,
                          onTap: () => onSelectConfig(configs[i]),
                          onLongPress: () => onConfigMenu(configs[i]),
                        ),
                    ],
                  ),
          ),
      ],
    );
  }
}

// ── Subscription group ────────────────────────────────────────────

class _SubGroup extends StatelessWidget {
  final TeapodTokens t;
  final Subscription sub;
  final List<VpnConfig> configs;
  final int outerIndex;
  final int addr;
  final String? activeConfigId;
  final bool isActiveSubscription;
  final bool isExpanded;
  final VpnState vpnState;
  final bool canReorderGroup;
  final bool sortMode;
  final VoidCallback onToggle;
  final VoidCallback onRefresh;
  final VoidCallback onRename;
  final VoidCallback onEditUrl;
  final VoidCallback onDelete;
  final VoidCallback onSelectSubscription;
  final void Function(VpnConfig) onSelectConfig;
  final void Function(VpnConfig) onConfigMenu;
  final void Function(int, int) onReorderConfigs;

  const _SubGroup({
    super.key,
    required this.t,
    required this.sub,
    required this.configs,
    required this.outerIndex,
    required this.addr,
    required this.activeConfigId,
    this.isActiveSubscription = false,
    required this.isExpanded,
    required this.vpnState,
    required this.canReorderGroup,
    required this.sortMode,
    required this.onToggle,
    required this.onRefresh,
    required this.onRename,
    required this.onEditUrl,
    required this.onDelete,
    required this.onSelectSubscription,
    required this.onSelectConfig,
    required this.onConfigMenu,
    required this.onReorderConfigs,
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

    final Widget addrWidget = SizedBox(
      width: 32,
      child: Text(hexAddr,
          style: AppTheme.mono(
              size: 10,
              color: isActiveSubscription ? t.accent : t.textMuted)),
    );

    return Column(
      children: [
        // Header
        Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: isActiveSubscription ? t.accentFade : null,
                border: Border(bottom: BorderSide(color: t.lineSoft)),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 11, 0, 11),
                    child: addrWidget,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: onToggle,
                      onLongPress: () => _showSubMenu(context),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(sub.name,
                                style: AppTheme.sans(
                                    size: 13,
                                    weight: FontWeight.w500,
                                    color: isActiveSubscription ? t.accent : t.text,
                                    letterSpacing: -0.2)),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text('cnt=${configs.length}',
                                    style: AppTheme.mono(size: 10, color: t.textMuted)),
                                Text(' · $_lastRefresh',
                                    style: AppTheme.mono(size: 10, color: t.textMuted)),
                                if (expireLabel != null) ...[
                                  Text(' · ',
                                      style: AppTheme.mono(size: 10, color: t.textMuted)),
                                  Text(expireLabel,
                                      style: AppTheme.mono(size: 10, color: t.danger)),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (canReorderGroup)
                    ReorderableDragStartListener(
                      index: outerIndex,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 11, 8, 11),
                        child: Icon(Icons.drag_handle_rounded, size: 18, color: t.accent),
                      ),
                    )
                  else ...[
                    GestureDetector(
                      onTap: onRefresh,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 11, 8, 11),
                        child: Icon(Icons.refresh_rounded, size: 16, color: t.textMuted),
                      ),
                    ),
                    Semantics(
                      label: 'меню подписки',
                      button: true,
                      child: GestureDetector(
                        onTap: () => _showSubMenu(context),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 11, 4, 11),
                          child: Icon(Icons.more_vert, size: 16, color: t.textMuted),
                        ),
                      ),
                    ),
                  ],
                  GestureDetector(
                    onTap: onToggle,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 11, 20, 11),
                      child: Icon(
                        isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                        size: 16,
                        color: t.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (isActiveSubscription)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 2, color: t.accent),
              ),
          ],
        ),

        // Expanded configs
        if (isExpanded)
          Container(
            color: t.bgSunken,
            child: Column(
              children: [
                if (sub.totalBytes != null && sub.totalBytes! > 0)
                  _DataUsageBanner(t: t, sub: sub),
                // Expired renewal banner
                if (sub.expireAt != null &&
                    sub.expireAt!.difference(DateTime.now()).inDays <= 0)
                  Container(
                    padding: const EdgeInsets.fromLTRB(52, 10, 20, 12),
                    decoration:
                        BoxDecoration(border: Border(top: BorderSide(color: t.lineSoft))),
                    child: Row(
                      children: [
                        Icon(Icons.bolt_rounded, size: 11, color: t.accent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('trial // renew subscription',
                              style: AppTheme.mono(size: 11, color: t.textDim)),
                        ),
                        GestureDetector(
                          onTap: onRefresh,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            color: t.line,
                            child: Text('RENEW',
                                style: AppTheme.mono(
                                    size: 10, color: t.textDim, letterSpacing: 1)),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Config list
                if (sortMode)
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    onReorder: onReorderConfigs,
                    children: [
                      for (var i = 0; i < configs.length; i++)
                        _ConfigRow(
                          key: ValueKey(configs[i].id),
                          t: t,
                          config: configs[i],
                          addr: i + 1,
                          isActive: configs[i].id == activeConfigId,
                          indent: true,
                          draggableIndex: i,
                          onTap: () => onSelectConfig(configs[i]),
                          onLongPress: () => onConfigMenu(configs[i]),
                        ),
                    ],
                  )
                else
                  Column(
                    children: [
                      for (var i = 0; i < configs.length; i++)
                        _ConfigRow(
                          key: ValueKey(configs[i].id),
                          t: t,
                          config: configs[i],
                          addr: i + 1,
                          isActive: configs[i].id == activeConfigId,
                          indent: true,
                          onTap: () => onSelectConfig(configs[i]),
                          onLongPress: () => onConfigMenu(configs[i]),
                        ),
                    ],
                  ),
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
                        style:
                            AppTheme.sans(size: 16, color: t.text, weight: FontWeight.w500)),
                  ),
                  Text('sub · ${configs.length} конфигов',
                      style: AppTheme.mono(size: 10, color: t.textMuted)),
                ],
              ),
            ),
            Container(height: 1, color: t.line),
            _SheetTile(
              t: t,
              label: isActiveSubscription ? 'Сбросить авто-выбор' : 'Авто-выбор лучшего',
              onTap: () { Navigator.pop(ctx); onSelectSubscription(); },
            ),
            _SheetTile(t: t, label: 'Переименовать', onTap: () { Navigator.pop(ctx); onRename(); }),
            _SheetTile(t: t, label: 'Изменить URL', onTap: () { Navigator.pop(ctx); onEditUrl(); }),
            _SheetTile(t: t, label: 'Копировать URL', onTap: () async {
              Navigator.pop(ctx);
              await Clipboard.setData(ClipboardData(text: sub.url));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('URL скопирован'), duration: Duration(seconds: 1)));
              }
            }),
            _SheetTile(t: t, label: 'Обновить', onTap: () { Navigator.pop(ctx); onRefresh(); }),
            _SheetTile(t: t, label: 'Удалить', color: t.danger,
                onTap: () { Navigator.pop(ctx); onDelete(); }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Data Usage Banner ─────────────────────────────────────────────

class _DataUsageBanner extends StatelessWidget {
  final TeapodTokens t;
  final Subscription sub;

  const _DataUsageBanner({required this.t, required this.sub});

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes < 1024 * 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB';
  }

  @override
  Widget build(BuildContext context) {
    final used = (sub.uploadBytes ?? 0) + (sub.downloadBytes ?? 0);
    final total = sub.totalBytes!;
    final percent = (used / total).clamp(0.0, 1.0);
    
    final usedStr = _formatBytes(used);
    final totalStr = _formatBytes(total);
    
    return Container(
      padding: const EdgeInsets.fromLTRB(52, 12, 20, 12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: t.lineSoft))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('data usage', style: AppTheme.mono(size: 10, color: t.textDim, letterSpacing: 1)),
              Text('$usedStr / $totalStr', style: AppTheme.mono(size: 10, color: t.textDim)),
            ],
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              Container(
                height: 2,
                width: double.infinity,
                color: t.line,
              ),
              if (percent > 0)
                FractionallySizedBox(
                  widthFactor: percent,
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 2,
                    color: percent > 0.9 ? t.danger : t.accent,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Config row ────────────────────────────────────────────────────

class _ConfigRow extends StatelessWidget {
  final TeapodTokens t;
  final VpnConfig config;
  final int addr;
  final bool isActive;
  final bool indent;
  final bool pinned;

  /// В режиме сортировки — индекс для ручки ≡; иначе показывается «⋮».
  final int? draggableIndex;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ConfigRow({
    super.key,
    required this.t,
    required this.config,
    required this.addr,
    required this.isActive,
    required this.onTap,
    required this.onLongPress,
    this.indent = false,
    this.pinned = false,
    this.draggableIndex,
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
    final hexAddr = '0x${addr.toString().padLeft(2, '0')}';
    final ping = config.latencyMs;
    final tagColor = isActive ? t.accent : t.textDim;
    final tagBorder = isActive ? t.accent : t.line;
    final leftPad = indent ? 52.0 : 20.0;
    final isDraggable = draggableIndex != null;

    final trailing = isDraggable
        ? ReorderableDragStartListener(
            index: draggableIndex!,
            child: SizedBox(
              width: 36,
              height: 40,
              child: Icon(Icons.drag_handle_rounded, size: 18, color: t.accent),
            ),
          )
        : Semantics(
            label: 'меню конфигурации',
            button: true,
            child: GestureDetector(
              onTap: onLongPress,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 36,
                height: 40,
                child: Icon(Icons.more_vert, size: 16, color: t.textMuted),
              ),
            ),
          );

    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: isActive ? t.accentFade : Colors.transparent,
          border: Border(bottom: BorderSide(color: t.lineSoft)),
        ),
        child: Stack(
          children: [
            if (isActive)
              Positioned(
                left: 0, top: 0, bottom: 0,
                child: Container(width: 2, color: t.accent),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(leftPad, 6, 10, 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Text(hexAddr,
                        style: AppTheme.mono(size: 10, color: t.textMuted)),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(border: Border.all(color: tagBorder)),
                    constraints: const BoxConstraints(minWidth: 44),
                    child: Text(_protoTag,
                        textAlign: TextAlign.center,
                        style: AppTheme.mono(size: 10, color: tagColor, letterSpacing: 1)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(config.name,
                            style: AppTheme.sans(
                                size: 13,
                                weight: FontWeight.w500,
                                color: t.text,
                                letterSpacing: -0.2),
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text('${config.address}:${config.port}',
                            style: AppTheme.mono(size: 10, color: t.textMuted),
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  if (pinned) ...[
                    Text('★', style: AppTheme.mono(size: 10, color: t.accent)),
                    const SizedBox(width: 6),
                  ],
                  if (ping != null)
                    Text('${ping}ms',
                        style: AppTheme.mono(size: 11, color: t.accent)),
                  trailing,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pinned group ──────────────────────────────────────────────────

class _PinnedGroup extends StatelessWidget {
  final TeapodTokens t;
  final List<(PinnedRef, VpnConfig?)> pins;
  final String? activeConfigId;
  final void Function(VpnConfig) onSelectConfig;
  final void Function(VpnConfig) onConfigMenu;
  final void Function(PinnedRef) onUnpin;

  const _PinnedGroup({
    super.key,
    required this.t,
    required this.pins,
    required this.activeConfigId,
    required this.onSelectConfig,
    required this.onConfigMenu,
    required this.onUnpin,
  });

  void _showLostMenu(BuildContext context, PinnedRef pin) {
    showModalBottomSheet(
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
                    child: Text(pin.name,
                        style: AppTheme.sans(size: 16, color: t.text, weight: FontWeight.w500)),
                  ),
                  Text('нет в подписке',
                      style: AppTheme.mono(size: 10, color: t.textMuted)),
                ],
              ),
            ),
            Container(height: 1, color: t.line),
            _SheetTile(t: t, label: 'Открепить', color: t.danger, onTap: () {
              Navigator.pop(ctx);
              onUnpin(pin);
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 11, 20, 11),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.lineSoft))),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Text('[★]',
                    style: AppTheme.mono(size: 10, color: t.accent)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('[pinned]',
                        style: AppTheme.sans(
                            size: 13, weight: FontWeight.w500, color: t.text)),
                    const SizedBox(height: 2),
                    Text('cnt=${pins.length} · закреплённые',
                        style: AppTheme.mono(size: 10, color: t.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          color: t.bgSunken,
          child: Column(
            children: [
              for (var i = 0; i < pins.length; i++)
                if (pins[i].$2 != null)
                  _ConfigRow(
                    key: ValueKey('pin_${pins[i].$1.subscriptionId}_${pins[i].$1.name}'),
                    t: t,
                    config: pins[i].$2!,
                    addr: i + 1,
                    isActive: pins[i].$2!.id == activeConfigId,
                    pinned: true,
                    onTap: () => onSelectConfig(pins[i].$2!),
                    onLongPress: () => onConfigMenu(pins[i].$2!),
                  )
                else
                  _LostPinRow(
                    key: ValueKey('lost_${pins[i].$1.subscriptionId}_${pins[i].$1.name}'),
                    t: t,
                    pin: pins[i].$1,
                    addr: i + 1,
                    onTap: () => _showLostMenu(context, pins[i].$1),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LostPinRow extends StatelessWidget {
  final TeapodTokens t;
  final PinnedRef pin;
  final int addr;
  final VoidCallback onTap;

  const _LostPinRow({
    super.key,
    required this.t,
    required this.pin,
    required this.addr,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hexAddr = '0x${addr.toString().padLeft(2, '0')}';
    return GestureDetector(
      onTap: onTap,
      onLongPress: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.lineSoft))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 11, 20, 11),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Text(hexAddr,
                    style: AppTheme.mono(size: 10, color: t.textMuted)),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(border: Border.all(color: t.lineSoft)),
                constraints: const BoxConstraints(minWidth: 44),
                child: Text('LOST',
                    textAlign: TextAlign.center,
                    style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pin.name,
                        style: AppTheme.sans(
                            size: 13,
                            weight: FontWeight.w500,
                            color: t.textMuted,
                            letterSpacing: -0.2),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('недоступен · нажмите чтобы открепить',
                        style: AppTheme.mono(size: 10, color: t.textMuted),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────

class _ToggleTile extends StatelessWidget {
  final TeapodTokens t;
  final String label;
  final bool value;
  final void Function(bool) onChanged;

  const _ToggleTile({
    required this.t,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.lineSoft))),
        child: Row(
          children: [
            Expanded(child: Text(label, style: AppTheme.sans(size: 14, color: t.text))),
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                border: Border.all(color: value ? t.accent : t.line),
                color: value ? t.accentFade : Colors.transparent,
              ),
              child: value ? Icon(Icons.check, size: 12, color: t.accent) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  final TeapodTokens t;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _SheetTile({required this.t, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.lineSoft))),
        child: Text(label, style: AppTheme.sans(size: 14, color: color ?? t.text)),
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
              style: AppTheme.mono(size: 14, color: t.textMuted, letterSpacing: 1)),
          const SizedBox(height: 20),
          Text('Добавьте конфигурацию\nили подписку',
              textAlign: TextAlign.center,
              style: AppTheme.sans(size: 14, color: t.textDim)),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              color: t.accent,
              child: Text('+ ADD CONFIG',
                  style: AppTheme.mono(size: 11, color: t.bg, letterSpacing: 1)),
            ),
          ),
        ],
      ),
    );
  }
}
