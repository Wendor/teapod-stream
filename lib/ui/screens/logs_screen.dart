// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/vpn_log_entry.dart';
import '../../core/services/log_service.dart';
import '../../core/services/share_service.dart';
import '../../providers/config_provider.dart';
import '../../providers/settings_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/hero_panel.dart';
import '../widgets/breadcrumb_bar.dart';
import '../widgets/tap_target.dart';
import '../../l10n/l10n.dart';
import '../../providers/native_logs_provider.dart';
import '../widgets/pressable.dart';

class LogsScreen extends ConsumerStatefulWidget {
  /// Parent screen name for the breadcrumb; null — no breadcrumb.
  final String? breadcrumbParent;
  const LogsScreen({super.key, this.breadcrumbParent});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  final _scrollController = ScrollController();
  bool _autoScroll = true;
  // empty = all
  final Set<LogLevel> _filters = {};

  static const Color _warn = AppColors.accentGold;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - 50;
    if (!atBottom && _autoScroll) setState(() => _autoScroll = false);
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  Future<void> _exportLogs() async {
    final srcPath = await ref.read(nativeLogsProvider).getLogFilePath();
    if (srcPath == null) return;
    final configs = ref.read(configProvider).value;
    final settings = ref.read(settingsProvider).value;
    final secrets = logSecrets(
      configs: configs?.configs ?? const [],
      subscriptions: configs?.subscriptions ?? const [],
      extra: [?settings?.socksUser, ?settings?.socksPassword],
    );
    final shared = await ref.read(shareServiceProvider).shareLog(srcPath, secrets);
    if (!shared && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.logsEmpty), duration: const Duration(seconds: 2)));
    }
  }

  Color _lvlColor(LogLevel lvl, TeapodTokens t) => switch (lvl) {
    LogLevel.error => t.danger,
    LogLevel.warning => _warn,
    LogLevel.info => t.accent,
    LogLevel.debug => t.textMuted,
  };

  String _lvlTag(LogLevel lvl) => switch (lvl) {
    LogLevel.error => 'ERR',
    LogLevel.warning => 'WRN',
    LogLevel.info => 'INF',
    LogLevel.debug => 'DBG',
  };

  static String _fmtTs(DateTime ts) =>
      '${ts.hour.toString().padLeft(2, '0')}:'
      '${ts.minute.toString().padLeft(2, '0')}:'
      '${ts.second.toString().padLeft(2, '0')}';

  Future<void> _toggleLogsEnabled() async {
    final s = ref.read(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null);
    if (s == null) return;
    final enabled = !s.logsEnabled;
    await ref.read(settingsProvider.notifier).edit((c) => c.copyWith(logsEnabled: enabled));
    await ref.read(nativeLogsProvider).setLogsEnabled(enabled);
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(logServiceProvider);
    final logsEnabled = ref.watch(settingsProvider).maybeWhen(data: (d) => d.logsEnabled, orElse: () => true);
    final t = Theme.of(context).extension<TeapodTokens>()!;

    final filtered = _filters.isEmpty ? logs : logs.where((e) => _filters.contains(e.level)).toList();

    final lastTs = logs.isNotEmpty ? _fmtTs(logs.last.timestamp) : '--:--:--';
    final bufStr = logs.length.toString().padLeft(4, '0');

    final errCount = logs.where((e) => e.level == LogLevel.error).length;
    final wrnCount = logs.where((e) => e.level == LogLevel.warning).length;
    final infCount = logs.where((e) => e.level == LogLevel.info).length;
    final dbgCount = logs.where((e) => e.level == LogLevel.debug).length;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_autoScroll && mounted) _scrollToBottom();
    });

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Console header strip ────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.line)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('teapod.stream // logs', style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                  Text('buf[$bufStr]', style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                ],
              ),
            ),
            if (widget.breadcrumbParent != null) BreadcrumbBar(t: t, parent: widget.breadcrumbParent!, current: 'logs'),

            // ── Hero panel ──────────────────────────────────────
            HeroPanel(
              t: t,
              tagline: context.l10n.logsTagline,
              title: 'LOGS',
              subtitle: Row(
                children: [
                  Text(
                    'last $lastTs · ${logsEnabled ? 'stream live' : 'stream paused'}',
                    style: AppTheme.mono(size: 11, color: t.textDim, letterSpacing: 0.5),
                  ),
                  const SizedBox(width: 8),
                  _PulseDot(color: logsEnabled ? t.accent : t.textMuted),
                ],
              ),
              trailing: Row(
                children: [
                  _IconBtn(
                    t: t,
                    icon: logsEnabled ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    label: logsEnabled ? context.l10n.logsPause : context.l10n.logsResume,
                    onTap: _toggleLogsEnabled,
                  ),
                  _IconBtn(
                    t: t,
                    icon: Icons.monitor_heart_outlined,
                    label: context.l10n.logsTunnelDiag,
                    onTap: () => ref.read(nativeLogsProvider).dumpTunnelDiag(),
                  ),
                  _IconBtn(t: t, icon: Icons.upload_file_rounded, label: context.l10n.logsShare, onTap: _exportLogs),
                  _IconBtn(
                    t: t,
                    icon: Icons.delete_sweep_rounded,
                    label: context.l10n.logsClear,
                    onTap: () {
                      ref.read(logServiceProvider.notifier).clear();
                      ref.read(nativeLogsProvider).clear();
                    },
                  ),
                ],
              ),
            ),

            // ── Filter tabs ──────────────────────────────────────
            IntrinsicHeight(
              child: Container(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: t.line)),
                ),
                child: Row(
                  children: [
                    _FilterTab(
                      t: t,
                      label: 'ALL',
                      count: logs.length,
                      active: _filters.isEmpty,
                      color: t.text,
                      last: false,
                      onTap: () => setState(() => _filters.clear()),
                    ),
                    _FilterTab(
                      t: t,
                      label: 'ERR',
                      count: errCount,
                      active: _filters.contains(LogLevel.error),
                      color: t.danger,
                      last: false,
                      onTap: () => setState(
                        () => _filters.contains(LogLevel.error)
                            ? _filters.remove(LogLevel.error)
                            : _filters.add(LogLevel.error),
                      ),
                    ),
                    _FilterTab(
                      t: t,
                      label: 'WRN',
                      count: wrnCount,
                      active: _filters.contains(LogLevel.warning),
                      color: _warn,
                      last: false,
                      onTap: () => setState(
                        () => _filters.contains(LogLevel.warning)
                            ? _filters.remove(LogLevel.warning)
                            : _filters.add(LogLevel.warning),
                      ),
                    ),
                    _FilterTab(
                      t: t,
                      label: 'INF',
                      count: infCount,
                      active: _filters.contains(LogLevel.info),
                      color: t.accent,
                      last: false,
                      onTap: () => setState(
                        () => _filters.contains(LogLevel.info)
                            ? _filters.remove(LogLevel.info)
                            : _filters.add(LogLevel.info),
                      ),
                    ),
                    _FilterTab(
                      t: t,
                      label: 'DBG',
                      count: dbgCount,
                      active: _filters.contains(LogLevel.debug),
                      color: t.textMuted,
                      last: true,
                      onTap: () => setState(
                        () => _filters.contains(LogLevel.debug)
                            ? _filters.remove(LogLevel.debug)
                            : _filters.add(LogLevel.debug),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Log list ─────────────────────────────────────────
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        '[ stream empty ]',
                        style: AppTheme.mono(size: 12, color: t.textMuted, letterSpacing: 1),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final e = filtered[i];
                        final lvlColor = _lvlColor(e.level, t);
                        return Container(
                          padding: const EdgeInsets.fromLTRB(10, 6, 20, 6),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: t.lineSoft)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 70,
                                child: Text(
                                  _fmtTs(e.timestamp),
                                  style: AppTheme.mono(size: 10, color: t.textMuted),
                                  maxLines: 1,
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 28,
                                child: Text(
                                  _lvlTag(e.level),
                                  style: AppTheme.mono(
                                    size: 10,
                                    weight: FontWeight.w700,
                                    color: lvlColor,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(e.message, style: AppTheme.mono(size: 10, color: t.text), softWrap: true),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // ── Footer ───────────────────────────────────────────
            Pressable(
              onTap: () {
                setState(() => _autoScroll = true);
                _scrollToBottom();
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.line)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _autoScroll ? '● auto-scroll' : '○ paused — tap to resume',
                      style: AppTheme.mono(size: 10, color: _autoScroll ? t.accent : t.textMuted, letterSpacing: 1),
                    ),
                    Text(
                      '${filtered.length} / ${logs.length}',
                      style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Filter tab ────────────────────────────────────────────────────

class _FilterTab extends StatelessWidget {
  final TeapodTokens t;
  final String label;
  final int count;
  final bool active;
  final Color color;
  final bool last;
  final VoidCallback onTap;

  const _FilterTab({
    required this.t,
    required this.label,
    required this.count,
    required this.active,
    required this.color,
    required this.last,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        child: Pressable(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active ? color.withAlpha(0x14) : Colors.transparent,
              border: Border(
                right: last ? BorderSide.none : BorderSide(color: t.line),
                bottom: active
                    ? BorderSide(color: color, width: 2)
                    : const BorderSide(color: Colors.transparent, width: 2),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: AppTheme.mono(
                    size: 10,
                    weight: active ? FontWeight.w700 : FontWeight.normal,
                    color: active ? color : t.textDim,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text('$count', style: AppTheme.mono(size: 9, color: active ? color : t.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Icon button ───────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final TeapodTokens t;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _IconBtn({required this.t, required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return TapTarget(
      onTap: onTap,
      label: label,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(border: Border.all(color: t.line)),
        child: Icon(icon, size: 14, color: onTap != null ? t.textDim : t.textMuted.withAlpha(0x66)),
      ),
    );
  }
}

// ── Pulse dot ─────────────────────────────────────────────────────

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0).animate(_ctrl),
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
