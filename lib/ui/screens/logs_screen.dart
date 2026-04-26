import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/vpn_log_entry.dart';
import '../../core/services/log_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  final _scrollController = ScrollController();
  bool _autoScroll = true;
  // empty = all
  final Set<LogLevel> _filters = {};

  static const Color _warn = Color(0xFFD9A65B);

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
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _copyToClipboard(List<VpnLogEntry> logs) async {
    final text = logs
        .map((e) => '[${_fmtTs(e.timestamp)}] [${_lvlTag(e.level)}] ${e.message}')
        .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Логи скопированы'), duration: Duration(seconds: 2)),
      );
    }
  }

  Color _lvlColor(LogLevel lvl, TeapodTokens t) => switch (lvl) {
    LogLevel.error   => t.danger,
    LogLevel.warning => _warn,
    LogLevel.info    => t.accent,
    LogLevel.debug   => t.textMuted,
  };

  String _lvlTag(LogLevel lvl) => switch (lvl) {
    LogLevel.error   => 'ERR',
    LogLevel.warning => 'WRN',
    LogLevel.info    => 'INF',
    LogLevel.debug   => 'DBG',
  };

  static String _fmtTs(DateTime ts) =>
      '${ts.hour.toString().padLeft(2, '0')}:'
      '${ts.minute.toString().padLeft(2, '0')}:'
      '${ts.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(logServiceProvider);
    final t = Theme.of(context).extension<TeapodTokens>()!;

    final filtered = _filters.isEmpty
        ? logs
        : logs.where((e) => _filters.contains(e.level)).toList();

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
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('teapod.stream // logs',
                      style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                  Text('buf[$bufStr]',
                      style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                ],
              ),
            ),

            // ── Hero panel ──────────────────────────────────────
            Container(
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
              child: Stack(
                children: [
                  _CornerTicksLogs(t: t),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ЖУРНАЛ · XRAY · TUN2SOCKS',
                                style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1.5)),
                            const SizedBox(height: 8),
                            Text('LOGS',
                                style: AppTheme.sans(
                                    size: 30, weight: FontWeight.w500,
                                    color: t.text, letterSpacing: -1, height: 1)),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text('last $lastTs · stream live',
                                    style: AppTheme.mono(size: 11, color: t.textDim, letterSpacing: 0.5)),
                                const SizedBox(width: 8),
                                _PulseDot(color: t.accent),
                              ],
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            _IconBtn(
                              t: t,
                              icon: Icons.copy_rounded,
                              onTap: logs.isEmpty ? null : () => _copyToClipboard(filtered),
                            ),
                            const SizedBox(width: 6),
                            _IconBtn(
                              t: t,
                              icon: Icons.delete_sweep_rounded,
                              onTap: () => ref.read(logServiceProvider.notifier).clear(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Filter tabs ──────────────────────────────────────
            IntrinsicHeight(
              child: Container(
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
                child: Row(
                  children: [
                    _FilterTab(t: t, label: 'ALL', count: logs.length,    active: _filters.isEmpty,                     color: t.text,      last: false, onTap: () => setState(() => _filters.clear())),
                    _FilterTab(t: t, label: 'ERR', count: errCount,       active: _filters.contains(LogLevel.error),    color: t.danger,    last: false, onTap: () => setState(() => _filters.contains(LogLevel.error) ? _filters.remove(LogLevel.error) : _filters.add(LogLevel.error))),
                    _FilterTab(t: t, label: 'WRN', count: wrnCount,       active: _filters.contains(LogLevel.warning),  color: _warn,       last: false, onTap: () => setState(() => _filters.contains(LogLevel.warning) ? _filters.remove(LogLevel.warning) : _filters.add(LogLevel.warning))),
                    _FilterTab(t: t, label: 'INF', count: infCount,       active: _filters.contains(LogLevel.info),     color: t.accent,    last: false, onTap: () => setState(() => _filters.contains(LogLevel.info) ? _filters.remove(LogLevel.info) : _filters.add(LogLevel.info))),
                    _FilterTab(t: t, label: 'DBG', count: dbgCount,       active: _filters.contains(LogLevel.debug),    color: t.textMuted, last: true,  onTap: () => setState(() => _filters.contains(LogLevel.debug) ? _filters.remove(LogLevel.debug) : _filters.add(LogLevel.debug))),
                  ],
                ),
              ),
            ),

            // ── Log list ─────────────────────────────────────────
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text('[ stream empty ]',
                          style: AppTheme.mono(size: 12, color: t.textMuted, letterSpacing: 1)),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: filtered.length + 1,
                      itemBuilder: (ctx, i) {
                        if (i == filtered.length) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                            child: Text('▌ stream active · ${filtered.length} entries',
                                style: AppTheme.mono(size: 10, color: t.textMuted)),
                          );
                        }
                        final e = filtered[i];
                        final lvlColor = _lvlColor(e.level, t);
                        return Container(
                          padding: const EdgeInsets.fromLTRB(10, 6, 20, 6),
                          decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: t.lineSoft))),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 56,
                                child: Text(_fmtTs(e.timestamp),
                                    style: AppTheme.mono(size: 10, color: t.textMuted)),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 28,
                                child: Text(_lvlTag(e.level),
                                    style: AppTheme.mono(
                                        size: 10,
                                        weight: FontWeight.w700,
                                        color: lvlColor,
                                        letterSpacing: 0.5)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(e.message,
                                    style: AppTheme.mono(size: 10, color: t.text),
                                    softWrap: true),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // ── Footer ───────────────────────────────────────────
            GestureDetector(
              onTap: () {
                setState(() => _autoScroll = true);
                _scrollToBottom();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: t.line))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_autoScroll ? '● auto-scroll' : '○ paused — tap to resume',
                        style: AppTheme.mono(
                            size: 10,
                            color: _autoScroll ? t.accent : t.textMuted,
                            letterSpacing: 1)),
                    Text('${filtered.length} / ${logs.length}',
                        style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
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
      child: GestureDetector(
        onTap: onTap,
        child: Container(
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
              Text(label,
                  style: AppTheme.mono(
                      size: 10,
                      weight: active ? FontWeight.w700 : FontWeight.normal,
                      color: active ? color : t.textDim,
                      letterSpacing: 1)),
              const SizedBox(height: 2),
              Text('$count',
                  style: AppTheme.mono(size: 9, color: active ? color : t.textMuted)),
            ],
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
  final VoidCallback? onTap;

  const _IconBtn({required this.t, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          border: Border.all(color: t.line),
        ),
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
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
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

// ── Corner ticks (reused pattern) ────────────────────────────────

class _CornerTicksLogs extends StatelessWidget {
  final TeapodTokens t;
  const _CornerTicksLogs({required this.t});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(top: 6, left: 6,   child: _Tick(color: t.textMuted, isTop: true,  isLeft: true)),
            Positioned(top: 6, right: 6,  child: _Tick(color: t.textMuted, isTop: true,  isLeft: false)),
            Positioned(bottom: 6, left: 6,  child: _Tick(color: t.textMuted, isTop: false, isLeft: true)),
            Positioned(bottom: 6, right: 6, child: _Tick(color: t.textMuted, isTop: false, isLeft: false)),
          ],
        ),
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  final Color color;
  final bool isTop;
  final bool isLeft;
  const _Tick({required this.color, required this.isTop, required this.isLeft});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(8, 8),
      painter: _TickPainter(color: color, isTop: isTop, isLeft: isLeft),
    );
  }
}

class _TickPainter extends CustomPainter {
  final Color color;
  final bool isTop;
  final bool isLeft;
  const _TickPainter({required this.color, required this.isTop, required this.isLeft});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..strokeWidth = 1..style = PaintingStyle.stroke;
    final w = size.width;
    final h = size.height;
    if (isTop && isLeft) {
      canvas.drawLine(Offset.zero, Offset(w, 0), p);
      canvas.drawLine(Offset.zero, Offset(0, h), p);
    } else if (isTop && !isLeft) {
      canvas.drawLine(Offset(0, 0), Offset(w, 0), p);
      canvas.drawLine(Offset(w, 0), Offset(w, h), p);
    } else if (!isTop && isLeft) {
      canvas.drawLine(Offset(0, h), Offset(w, h), p);
      canvas.drawLine(Offset(0, 0), Offset(0, h), p);
    } else {
      canvas.drawLine(Offset(0, h), Offset(w, h), p);
      canvas.drawLine(Offset(w, 0), Offset(w, h), p);
    }
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.color != color;
}
