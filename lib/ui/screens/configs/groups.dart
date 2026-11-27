part of 'configs_screen.dart';

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
        Semantics(
          expanded: isExpanded,
          child: Pressable(
            onTap: onToggle,
            child: Container(
              constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
              padding: const EdgeInsets.fromLTRB(20, 11, 20, 11),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.lineSoft)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Text('[00]', style: AppTheme.mono(size: 10, color: t.textMuted)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '[local]',
                          style: AppTheme.sans(size: 13, weight: FontWeight.w500, color: t.text),
                        ),
                        const SizedBox(height: 2),
                        Text('cnt=${configs.length} · standalone', style: AppTheme.mono(size: 10, color: t.textMuted)),
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
        ),
        if (isExpanded)
          Container(
            color: t.bgSunken,
            child: sortMode
                ? ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    onReorderItem: onReorderConfigs,
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

  String _lastRefresh(AppLocalizations l) {
    final at = sub.lastFetchedAt;
    if (at == null) return l.subNeverUpdated;
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return l.subJustNow;
    if (diff.inHours < 1) return l.subMinutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return l.subHoursAgo(diff.inHours);
    return l.subDaysAgo(diff.inDays);
  }

  String? _expireLabel(AppLocalizations l) {
    final exp = sub.expireAt;
    if (exp == null) return null;
    final days = exp.difference(DateTime.now()).inDays;
    if (days < 0) return l.subExpired;
    if (days == 0) return 'expires:today';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hexAddr = '0x${addr.toString().padLeft(2, '0')}';
    final expireLabel = _expireLabel(context.l10n);

    final Widget addrWidget = SizedBox(
      width: 32,
      child: Text(hexAddr, style: AppTheme.mono(size: 10, color: isActiveSubscription ? t.accent : t.textMuted)),
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
                  Padding(padding: const EdgeInsets.fromLTRB(20, 11, 0, 11), child: addrWidget),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Semantics(
                      expanded: isExpanded,
                      child: Pressable(
                        onTap: onToggle,
                        onLongPress: () => _showSubMenu(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sub.name,
                                style: AppTheme.sans(
                                  size: 13,
                                  weight: FontWeight.w500,
                                  color: isActiveSubscription ? t.accent : t.text,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text('cnt=${configs.length}', style: AppTheme.mono(size: 10, color: t.textMuted)),
                                  Text(
                                    ' · ${_lastRefresh(context.l10n)}',
                                    style: AppTheme.mono(size: 10, color: t.textMuted),
                                  ),
                                  if (expireLabel != null) ...[
                                    Text(' · ', style: AppTheme.mono(size: 10, color: t.textMuted)),
                                    Text(expireLabel, style: AppTheme.mono(size: 10, color: t.danger)),
                                  ],
                                ],
                              ),
                            ],
                          ),
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
                    TapTarget(
                      label: context.l10n.configsRefresh,
                      onTap: onRefresh,
                      child: Icon(Icons.refresh_rounded, size: 16, color: t.textMuted),
                    ),
                    TapTarget(
                      label: context.l10n.configsSubMenu,
                      onTap: () => _showSubMenu(context),
                      child: Icon(Icons.more_vert, size: 16, color: t.textMuted),
                    ),
                  ],
                  // Repeats the name's toggle for TalkBack, so it stays out of the semantics tree.
                  ExcludeSemantics(
                    child: TapTarget(
                      onTap: onToggle,
                      minWidth: 0,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 20, 0),
                        child: Icon(
                          isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                          size: 16,
                          color: t.textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (isActiveSubscription)
              Positioned(left: 0, top: 0, bottom: 0, child: Container(width: 2, color: t.accent)),
          ],
        ),

        // Expanded configs
        if (isExpanded)
          Container(
            color: t.bgSunken,
            child: Column(
              children: [
                if (sub.totalBytes != null && sub.totalBytes! > 0) _DataUsageBanner(t: t, sub: sub),
                // Provider message (announce header), link — announce-url
                if (sub.announce?.isNotEmpty == true)
                  Semantics(
                    link: sub.announceUrl != null,
                    child: Pressable(
                      onTap: sub.announceUrl == null
                          ? null
                          : () => launchUrl(Uri.parse(sub.announceUrl!), mode: LaunchMode.externalApplication).ignore(),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(52, 10, 20, 12),
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: t.lineSoft)),
                        ),
                        child: Text(
                          sub.announce!,
                          style: AppTheme.sans(size: 12, color: sub.announceUrl == null ? t.textDim : t.accent),
                        ),
                      ),
                    ),
                  ),
                // Expired renewal banner
                if (sub.expireAt != null && sub.expireAt!.difference(DateTime.now()).inDays <= 0)
                  Container(
                    padding: const EdgeInsets.fromLTRB(52, 10, 20, 12),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: t.lineSoft)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.bolt_rounded, size: 11, color: t.accent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('trial // renew subscription', style: AppTheme.mono(size: 11, color: t.textDim)),
                        ),
                        TapTarget(
                          onTap: onRefresh,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            color: t.line,
                            child: Text('RENEW', style: AppTheme.mono(size: 10, color: t.textDim, letterSpacing: 1)),
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
                    onReorderItem: onReorderConfigs,
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
                      sub.name,
                      style: AppTheme.sans(size: 16, color: t.text, weight: FontWeight.w500),
                    ),
                  ),
                  Text(
                    'sub · ${context.l10n.configsCount(configs.length)}',
                    style: AppTheme.mono(size: 10, color: t.textMuted),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: t.line),
            _SheetTile(
              t: t,
              label: isActiveSubscription ? context.l10n.configsAutoSelectReset : context.l10n.configsAutoSelectBest,
              onTap: () {
                Navigator.pop(ctx);
                onSelectSubscription();
              },
            ),
            _SheetTile(
              t: t,
              label: context.l10n.commonRename,
              onTap: () {
                Navigator.pop(ctx);
                onRename();
              },
            ),
            _SheetTile(
              t: t,
              label: context.l10n.configsEditUrl,
              onTap: () {
                Navigator.pop(ctx);
                onEditUrl();
              },
            ),
            _SheetTile(
              t: t,
              label: context.l10n.configsCopyUrl,
              onTap: () async {
                Navigator.pop(ctx);
                await Clipboard.setData(ClipboardData(text: sub.url));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.l10n.configsUrlCopied), duration: const Duration(seconds: 1)),
                  );
                }
              },
            ),
            _SheetTile(
              t: t,
              label: context.l10n.configsRefresh,
              onTap: () {
                Navigator.pop(ctx);
                onRefresh();
              },
            ),
            _SheetTile(
              t: t,
              label: context.l10n.commonDelete,
              color: t.danger,
              onTap: () {
                Navigator.pop(ctx);
                onDelete();
              },
            ),
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
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.lineSoft)),
      ),
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
              Container(height: 2, width: double.infinity, color: t.line),
              if (percent > 0)
                FractionallySizedBox(
                  widthFactor: percent,
                  alignment: Alignment.centerLeft,
                  child: Container(height: 2, color: percent > 0.9 ? t.danger : t.accent),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Config row ────────────────────────────────────────────────────
