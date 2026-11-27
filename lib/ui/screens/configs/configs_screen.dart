// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import '../../widgets/core_support_gate.dart';
import '../../widgets/core_sheet.dart';
import '../../../providers/core_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/models/connections_bundle.dart';
import '../../../core/models/vpn_config.dart';
import '../../../core/models/pinned_ref.dart';
import '../../../core/models/subscription.dart';
import '../../../core/services/subscription_service.dart';
import '../../../providers/config_provider.dart';
import '../../../providers/theme_provider.dart';
import '../../../providers/vpn_provider.dart';
import '../../../core/interfaces/vpn_engine.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/hero_panel.dart';
import '../../widgets/pressable.dart';
import '../../widgets/untrusted_cert_dialog.dart';
import '../add_config_screen.dart';
import '../subscription_settings_screen.dart';
import '../../../l10n/l10n.dart';
import '../../../providers/ping_provider.dart';

part 'config_row.dart';
part 'groups.dart';
part 'header.dart';
part 'pinned.dart';
part 'tiles.dart';

class ConfigsScreen extends ConsumerStatefulWidget {
  const ConfigsScreen({super.key});

  @override
  ConsumerState<ConfigsScreen> createState() => _ConfigsScreenState();
}

class _ConfigsScreenState extends ConsumerState<ConfigsScreen> {
  final Set<String> _expandedSubs = {'__local__'};
  bool _isRefreshingAll = false;
  bool _sortMode = false; // explicit manual sort mode (not persisted)

  // The view is watched in build.
  bool get _hideGroups => ref.read(configsViewProvider).hideGroups;
  bool get _sortByPing => ref.read(configsViewProvider).sortByPing;

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
    ref.watch(configsViewProvider);
    final t = Theme.of(context).extension<TeapodTokens>()!;

    ref.listen<AsyncValue<ConfigState>>(configProvider, (prev, next) {
      next.whenData((cs) {
        final id = cs.activeConfigId;
        if (id == null) return;
        final prevId = prev?.maybeWhen(data: (d) => d.activeConfigId, orElse: () => null);
        if (id == prevId && prev != null) return;
        final active = cs.configs.where((c) => c.id == id).firstOrNull;
        if (active == null) return;
        final group = active.subscriptionId ?? '__local__';
        if (!_expandedSubs.contains(group)) setState(() => _expandedSubs.add(group));
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
              isPinging: ref.watch(pingProvider),
              onPing: configStateAsync.maybeWhen(
                data: (s) => s.configs.isNotEmpty ? () => ref.read(pingProvider.notifier).pingAll() : null,
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
                MaterialPageRoute<void>(builder: (_) => const SubscriptionSettingsScreen(breadcrumbParent: 'configs')),
              ),
              onExport: configStateAsync.maybeWhen(
                data: (s) => s.configs.isNotEmpty ? () => _exportAll(s.configs) : null,
                orElse: () => null,
              ),
            ),
            Expanded(
              child: configStateAsync.when(
                loading: () => Center(child: CircularProgressIndicator(color: t.accent, strokeWidth: 1.5)),
                error: (e, _) => Center(
                  child: Text(context.l10n.commonErrorWith('$e'), style: AppTheme.mono(size: 12, color: t.danger)),
                ),
                data: (cs) => _buildBody(context, cs, vpnState, t),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ConfigState cs, VpnStatus vpnState, TeapodTokens t) {
    if (cs.configs.isEmpty && cs.subscriptions.isEmpty) {
      return _EmptyState(onAdd: () => _openAddConfig(context));
    }
    if (_hideGroups) return _buildFlatList(context, cs, vpnState, t);
    return _buildGroupedList(context, cs, vpnState, t);
  }

  Widget _buildFlatList(BuildContext context, ConfigState cs, VpnStatus vpnState, TeapodTokens t) {
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

  Widget _buildGroupedList(BuildContext context, ConfigState cs, VpnStatus vpnState, TeapodTokens t) {
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
              onReorderConfigs: (o, n) => ref.read(configProvider.notifier).reorderGroupConfigs(null, o, n),
            ),
        ],
      );
    }

    return ReorderableListView(
      buildDefaultDragHandles: false,
      padding: EdgeInsets.zero,
      onReorderItem: (old, nw) {
        if (old < localOffset) return;
        final safeNew = nw < localOffset ? localOffset : nw;
        ref.read(configProvider.notifier).reorderSubscriptions(old - localOffset, safeNew - localOffset);
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
            onReorderConfigs: (o, n) => ref.read(configProvider.notifier).reorderGroupConfigs(null, o, n),
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
            onReorderConfigs: (o, n) => ref.read(configProvider.notifier).reorderGroupConfigs(subs[i].id, o, n),
          ),
      ],
    );
  }

  // ── Settings sheet ─────────────────────────────────────────────

  void _showSettingsSheet(BuildContext context, TeapodTokens t) {
    showModalBottomSheet<void>(
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
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'configs // display',
                        style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1),
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: t.line),
              _ToggleTile(
                t: t,
                label: context.l10n.configsHideGroups,
                value: _hideGroups,
                onChanged: (v) {
                  ref.read(configsViewProvider.notifier).set(hideGroups: v);
                  setSheet(() {});
                },
              ),
              _ToggleTile(
                t: t,
                label: context.l10n.configsSortByPing,
                value: _sortByPing,
                onChanged: (v) {
                  ref.read(configsViewProvider.notifier).set(sortByPing: v);
                  setSheet(() {});
                  if (v) setState(() => _sortMode = false);
                },
              ),
              _ToggleTile(
                t: t,
                label: context.l10n.configsSortMode,
                value: _sortMode,
                onChanged: (v) {
                  if (v) ref.read(configsViewProvider.notifier).set(sortByPing: false);
                  setSheet(() {});
                  setState(() => _sortMode = v);
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

  Future<void> _selectConfig(WidgetRef ref, VpnConfig config) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final reason = await ref.read(vpnProvider.notifier).selectConfig(config);
    if (reason != null) messenger.showSnackBar(SnackBar(content: Text(reason.localize(l))));
  }

  Future<void> _exportAll(List<VpnConfig> configs) async {
    final cs = ref.read(configProvider).maybeWhen(data: (d) => d, orElse: () => null);
    if (cs == null || cs.configs.isEmpty) return;
    final bundle = ConnectionsBundle(
      exportedAt: DateTime.now(),
      configs: cs.standaloneConfigs,
      subscriptions: cs.subscriptions,
    );
    await SharePlus.instance.share(ShareParams(text: bundle.toCompactDeeplink(), subject: 'teapod configs'));
  }

  Future<void> _showConfigMenu(BuildContext context, WidgetRef ref, VpnConfig config) async {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    final isPinned = ref.read(configProvider).maybeWhen(data: (d) => d.isPinned(config), orElse: () => false);
    await showModalBottomSheet<void>(
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
                    child: Text(
                      config.name,
                      style: AppTheme.sans(size: 16, color: t.text, weight: FontWeight.w500),
                    ),
                  ),
                  Text(config.protocol.name.toUpperCase(), style: AppTheme.mono(size: 10, color: t.textMuted)),
                ],
              ),
            ),
            Container(height: 1, color: t.line),
            _SheetTile(
              t: t,
              label: isPinned ? context.l10n.configsUnpin : context.l10n.configsPin,
              onTap: () {
                Navigator.pop(ctx);
                ref.read(configProvider.notifier).togglePin(config);
              },
            ),
            _SheetTile(
              t: t,
              label:
                  '${context.l10n.configsCore} · ${ref.read(coreResolverProvider).resolve(config).backend?.kind.displayName ?? context.l10n.configsCoreNone}',
              onTap: () {
                Navigator.pop(ctx);
                showCoreSheet(context, config);
              },
            ),
            _SheetTile(
              t: t,
              label: context.l10n.commonRename,
              onTap: () async {
                Navigator.pop(ctx);
                if (!context.mounted) return;
                await _renameConfig(context, ref, config);
              },
            ),
            _SheetTile(
              t: t,
              label: context.l10n.configsEditUri,
              onTap: () async {
                Navigator.pop(ctx);
                if (!context.mounted) return;
                await _editConfig(context, ref, config);
              },
            ),
            _SheetTile(
              t: t,
              label: context.l10n.configsCopyUrl,
              onTap: () async {
                Navigator.pop(ctx);
                if (config.rawUri != null) {
                  await Clipboard.setData(ClipboardData(text: config.rawUri!));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.l10n.configsUrlCopied), duration: const Duration(seconds: 1)),
                    );
                  }
                }
              },
            ),
            _SheetTile(
              t: t,
              label: context.l10n.configsShare,
              onTap: () async {
                Navigator.pop(ctx);
                if (config.rawUri != null) await SharePlus.instance.share(ShareParams(text: config.rawUri!));
              },
            ),
            _SheetTile(
              t: t,
              label: context.l10n.commonDelete,
              color: t.danger,
              onTap: () async {
                Navigator.pop(ctx);
                if (!context.mounted) return;
                await _deleteConfig(context, ref, config);
              },
            ),
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
        title: Text(context.l10n.commonRename),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: context.l10n.commonName, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.l10n.commonSave)),
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
        title: Text(context.l10n.configsEditUri),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          child: TextField(
            controller: controller,
            maxLines: 5,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(hintText: 'vless://...', border: OutlineInputBorder(), isDense: true),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.l10n.commonSave)),
        ],
      ),
    );
    if (ok != true || controller.text.trim().isEmpty || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.l10n.configsUriParseFailed;
    try {
      if (!await ref.read(configProvider.notifier).editLink(config.id, controller.text)) {
        messenger.showSnackBar(SnackBar(content: Text(failed)));
      }
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deleteConfig(BuildContext context, WidgetRef ref, VpnConfig config) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.configsDeleteTitle),
        content: Text(context.l10n.configsDeleteMessage(config.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.l10n.commonCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(context.l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(configProvider.notifier).removeConfig(config.id);
    }
  }

  Future<void> _refreshSubscription(
    BuildContext context,
    WidgetRef ref,
    Subscription sub, {
    String? pinnedCertDer,
  }) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await ref
          .read(configProvider.notifier)
          .addSubscriptionFromUrl(sub.url, name: sub.name, pinnedCertDer: pinnedCertDer);
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.configsSubUpdated)));
      }
    } on UntrustedCertificateException catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      if (await confirmUntrustedCertificate(context, e) && context.mounted) {
        await _refreshSubscription(context, ref, sub, pinnedCertDer: e.der);
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.configsUpdateError('$e'))));
      }
    }
  }

  Future<void> _renameSubscription(BuildContext context, WidgetRef ref, Subscription sub) async {
    final controller = TextEditingController(text: sub.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.configsRenameSub),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: context.l10n.commonName, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.l10n.commonSave)),
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
        title: Text(context.l10n.configsEditSubUrl),
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.l10n.configsSaveAndRefresh)),
        ],
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty) {
      final updatedUrl = controller.text.trim();
      try {
        await ref.read(configProvider.notifier).addSubscriptionFromUrl(updatedUrl, name: sub.name, replaceId: sub.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.configsSubUpdatedNewUrl)));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.configsUpdateError('$e'))));
        }
      }
    }
  }

  Future<void> _deleteSubscription(BuildContext context, WidgetRef ref, Subscription sub) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.configsDeleteSubTitle),
        content: Text(context.l10n.configsDeleteSubMessage(sub.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.l10n.commonCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(context.l10n.commonDelete),
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
      final configState = ref.read(configProvider).maybeWhen(data: (d) => d, orElse: () => null);
      if (configState == null) return;
      final failed = <String>[];
      for (final sub in configState.subscriptions) {
        try {
          await ref.read(configProvider.notifier).addSubscriptionFromUrl(sub.url, name: sub.name);
        } catch (e) {
          failed.add('${sub.name}: ${e.toString().replaceFirst('Exception: ', '')}');
        }
      }
      if (mounted) {
        final total = configState.subscriptions.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failed.isEmpty
                  ? context.l10n.configsSubsUpdated(total)
                  : '${context.l10n.configsSubsUpdatedPartial(total - failed.length, total)}\n${failed.join('\n')}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshingAll = false);
    }
  }

  void _openAddConfig(BuildContext context) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AddConfigScreen()));
  }
}

// ── Console header strip ──────────────────────────────────────────
