import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/vpn_stats.dart';
import '../../providers/vpn_provider.dart';
import '../../providers/config_provider.dart';
import '../../providers/ip_info_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/live_sparkline.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState    = ref.watch(vpnProvider);
    final configAsync = ref.watch(configProvider);
    final t = Theme.of(context).extension<TeapodTokens>()!;

    final activeConfig = configAsync.maybeWhen(
      data: (d) => d.activeConfig,
      orElse: () => null,
    );
    final canToggle = activeConfig != null;
    final pingMs    = activeConfig?.latencyMs;

    final isConn  = vpnState.isConnected;
    final isBusy  = vpnState.isBusy;
    final stateCode = isConn ? '01' : (isBusy ? '02' : '00');

    final protoLabel = activeConfig != null
        ? _protoLabel(activeConfig.protocol)
        : '—';
    final serverHint = activeConfig != null
        ? '${activeConfig.address}:${activeConfig.port}'
        : '—';

    final history = vpnState.stats.speedHistory;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _HeaderStrip(t: t, stateCode: stateCode),
            _HeroPanel(
              t: t,
              vpnState: vpnState,
              protoLabel: protoLabel,
              pingMs: pingMs,
              history: history,
              canToggle: canToggle,
              onToggle: () => ref.read(vpnProvider.notifier).toggle(),
            ),
            Expanded(
              child: _MetricsGrid(
                t: t,
                stats: vpnState.stats,
                protoLabel: protoLabel,
                serverHint: serverHint,
                isConnected: isConn,
                pingMs: pingMs,
                history: history,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header strip ──────────────────────────────────────────────────

class _HeaderStrip extends StatelessWidget {
  final TeapodTokens t;
  final String stateCode;
  const _HeaderStrip({required this.t, required this.stateCode});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.line, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('teapod.stream // v2.4',
              style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
          Text('sys.state [$stateCode]',
              style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
        ],
      ),
    );
  }
}

// ── Hero panel ────────────────────────────────────────────────────

class _HeroPanel extends StatelessWidget {
  final TeapodTokens t;
  final VpnState2 vpnState;
  final String protoLabel;
  final int? pingMs;
  final List<SpeedPoint> history;
  final bool canToggle;
  final VoidCallback onToggle;

  const _HeroPanel({
    required this.t,
    required this.vpnState,
    required this.protoLabel,
    required this.pingMs,
    required this.history,
    required this.canToggle,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isConn = vpnState.isConnected;
    final isBusy = vpnState.isBusy;

    // Corner ticks fill the container; content padded inside
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.line, width: 1)),
      ),
      child: Stack(
        children: [
          _CornerTicks(t: t),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: _StateInfo(
                        t: t,
                        vpnState: vpnState,
                        protoLabel: protoLabel,
                        pingMs: pingMs,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _SquareToggle(
                      t: t,
                      isConnected: isConn,
                      isBusy: isBusy,
                      enabled: canToggle,
                      onTap: onToggle,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _PingBars(t: t, history: history, isConnected: isConn),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── State info ────────────────────────────────────────────────────

class _StateInfo extends ConsumerWidget {
  final TeapodTokens t;
  final VpnState2 vpnState;
  final String protoLabel;
  final int? pingMs;

  const _StateInfo({
    required this.t,
    required this.vpnState,
    required this.protoLabel,
    this.pingMs,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConn          = vpnState.isConnected;
    final isConnecting    = vpnState.isConnecting;
    final isDisconnecting = vpnState.isDisconnecting;
    final ipAsync         = ref.watch(ipInfoProvider);

    final stateWord = isConn
        ? 'ONLINE'
        : (isConnecting ? 'HANDSHAKE' : (isDisconnecting ? 'SHUTDOWN' : 'OFFLINE'));
    final stateColor = isConn ? t.accent : t.textDim;

    String subtitle;
    if (isConn) {
      final ipStr = ipAsync.maybeWhen(data: (d) => d?.ip, orElse: () => null) ?? '—';
      final cc    = ipAsync.maybeWhen(data: (d) => d?.countryCode.toLowerCase(), orElse: () => null) ?? '—';
      subtitle = pingMs != null ? '${pingMs}ms · $cc · $ipStr' : '$cc · $ipStr';
    } else if (isConnecting) {
      subtitle = 'negotiating session…';
    } else if (isDisconnecting) {
      subtitle = 'closing session…';
    } else {
      subtitle = 'tap to connect';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ТУННЕЛЬ · $protoLabel',
          style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1.5),
        ),
        const SizedBox(height: 8),
        Text(
          stateWord,
          style: AppTheme.sans(
            size: 34, weight: FontWeight.w500,
            color: stateColor, letterSpacing: -1, height: 1),
        ),
        const SizedBox(height: 8),
        Text(subtitle,
            style: AppTheme.mono(size: 11, color: t.textDim, letterSpacing: 0.5)),
      ],
    );
  }
}

// ── Square toggle ─────────────────────────────────────────────────

class _SquareToggle extends StatefulWidget {
  final TeapodTokens t;
  final bool isConnected;
  final bool isBusy;
  final bool enabled;
  final VoidCallback onTap;

  const _SquareToggle({
    required this.t,
    required this.isConnected,
    required this.isBusy,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_SquareToggle> createState() => _SquareToggleState();
}

class _SquareToggleState extends State<_SquareToggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t    = widget.t;
    final conn = widget.isConnected;
    final busy = widget.isBusy;
    final label = conn ? 'active' : (busy ? 'wait' : 'engage');

    final borderColor = conn ? t.accent : t.line;
    final bgColor     = conn ? t.accent : Colors.transparent;
    final iconColor   = conn ? t.bg : t.text;

    return GestureDetector(
      onTap: widget.enabled ? widget.onTap : null,
      child: Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: borderColor, width: 1),
          boxShadow: conn ? [BoxShadow(color: t.accentSoft, blurRadius: 24)] : null,
        ),
        child: Stack(
          children: [
            if (!conn) ...[
              Positioned(top: -1, left: -1,
                child: _Notch(accent: t.accent, corner: _Corner.topLeft)),
              Positioned(bottom: -1, right: -1,
                child: _Notch(accent: t.accent, corner: _Corner.bottomRight)),
            ],
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PowerIcon(color: iconColor, size: 30),
                  const SizedBox(height: 4),
                  busy
                      ? FadeTransition(
                          opacity: _blink,
                          child: _labelText(label, iconColor, t),
                        )
                      : _labelText(label, iconColor, t),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labelText(String text, Color color, TeapodTokens t) => Text(
    text.toUpperCase(),
    style: AppTheme.mono(size: 9, color: color, letterSpacing: 1.5),
  );
}

enum _Corner { topLeft, bottomRight }

class _Notch extends StatelessWidget {
  final Color accent;
  final _Corner corner;
  const _Notch({required this.accent, required this.corner});

  @override
  Widget build(BuildContext context) {
    final isTop = corner == _Corner.topLeft;
    return SizedBox(
      width: 8, height: 8,
      child: CustomPaint(painter: _NotchPainter(color: accent, isTopLeft: isTop)),
    );
  }
}

class _NotchPainter extends CustomPainter {
  final Color color;
  final bool isTopLeft;
  const _NotchPainter({required this.color, required this.isTopLeft});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 2..style = PaintingStyle.stroke;
    if (isTopLeft) {
      canvas.drawLine(Offset.zero, Offset(size.width, 0), paint);
      canvas.drawLine(Offset.zero, Offset(0, size.height), paint);
    } else {
      canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), paint);
      canvas.drawLine(Offset(size.width, 0), Offset(size.width, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_NotchPainter old) => old.color != color;
}

// ── Power icon ────────────────────────────────────────────────────

class _PowerIcon extends StatelessWidget {
  final Color color;
  final double size;
  const _PowerIcon({required this.color, required this.size});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size), painter: _PowerPainter(color));
}

class _PowerPainter extends CustomPainter {
  final Color color;
  const _PowerPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final s = size.width / 24.0;
    canvas.scale(s, s);

    // Stem from top to circle entry
    canvas.drawLine(const Offset(12, 2), const Offset(12, 9), paint);
    // Arc: center (12,13), radius 8, gap at top ~60°
    // Start at -60° (1 o'clock), sweep 300° clockwise
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(12, 13), radius: 8),
      -math.pi / 3,
      math.pi * 5 / 3,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_PowerPainter old) => old.color != color;
}

// ── Corner ticks ──────────────────────────────────────────────────

class _CornerTicks extends StatelessWidget {
  final TeapodTokens t;
  const _CornerTicks({required this.t});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(top: 6, left: 6,   child: _Tick(color: t.textMuted, corner: _TickCorner.tl)),
            Positioned(top: 6, right: 6,  child: _Tick(color: t.textMuted, corner: _TickCorner.tr)),
            Positioned(bottom: 6, left: 6,  child: _Tick(color: t.textMuted, corner: _TickCorner.bl)),
            Positioned(bottom: 6, right: 6, child: _Tick(color: t.textMuted, corner: _TickCorner.br)),
          ],
        ),
      ),
    );
  }
}

enum _TickCorner { tl, tr, bl, br }

class _Tick extends StatelessWidget {
  final Color color;
  final _TickCorner corner;
  const _Tick({required this.color, required this.corner});

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: 8, height: 8,
        child: CustomPaint(painter: _TickPainter(color, corner)));
  }
}

class _TickPainter extends CustomPainter {
  final Color color;
  final _TickCorner corner;
  const _TickPainter(this.color, this.corner);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..strokeWidth = 1..style = PaintingStyle.stroke;
    final w = size.width;
    final h = size.height;
    switch (corner) {
      case _TickCorner.tl:
        canvas.drawLine(Offset.zero, Offset(w, 0), p);
        canvas.drawLine(Offset.zero, Offset(0, h), p);
      case _TickCorner.tr:
        canvas.drawLine(Offset(0, 0), Offset(w, 0), p);
        canvas.drawLine(Offset(w, 0), Offset(w, h), p);
      case _TickCorner.bl:
        canvas.drawLine(Offset(0, h), Offset(w, h), p);
        canvas.drawLine(Offset(0, 0), Offset(0, h), p);
      case _TickCorner.br:
        canvas.drawLine(Offset(0, h), Offset(w, h), p);
        canvas.drawLine(Offset(w, 0), Offset(w, h), p);
    }
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.color != color;
}

// ── Ping bars ─────────────────────────────────────────────────────

class _PingBars extends StatelessWidget {
  final TeapodTokens t;
  final List<SpeedPoint> history;
  final bool isConnected;

  const _PingBars({
    required this.t,
    required this.history,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    const barCount = 40;
    final samples = history.map((s) => s.downloadSpeed.toDouble()).toList();
    while (samples.length < barCount) { samples.insert(0, 0.0); }
    final last40 = samples.length > barCount
        ? samples.sublist(samples.length - barCount)
        : samples;

    final maxVal = last40.fold<double>(1.0, (m, v) => v > m ? v : m);

    return SizedBox(
      height: 24,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: last40.asMap().entries.map((e) {
          final i = e.key;
          final v = e.value;
          final h = math.max(2.0, (v / maxVal) * 22.0);
          final opacity = isConnected ? 0.4 + (i / barCount) * 0.6 : 0.35;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.8),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    height: h,
                    color: isConnected ? t.accent : t.line,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Metrics grid ──────────────────────────────────────────────────

class _MetricsGrid extends StatelessWidget {
  final TeapodTokens t;
  final VpnStats stats;
  final String protoLabel;
  final String serverHint;
  final bool isConnected;
  final int? pingMs;
  final List<SpeedPoint> history;

  const _MetricsGrid({
    required this.t,
    required this.stats,
    required this.protoLabel,
    required this.serverHint,
    required this.isConnected,
    required this.pingMs,
    required this.history,
  });

  String _bitrateValue(int bps) {
    final bits = bps * 8;
    if (bits < 1024) return '$bits';
    if (bits < 1024 * 1024) return (bits / 1024).toStringAsFixed(1);
    return (bits / (1024 * 1024)).toStringAsFixed(2);
  }

  String _bitrateUnit(int bps) {
    final bits = bps * 8;
    if (bits < 1024) return 'bit/s';
    if (bits < 1024 * 1024) return 'Kbit/s';
    return 'Mbit/s';
  }

  String _bytesValue(int bytes) {
    if (bytes < 1024) return '$bytes';
    if (bytes < 1024 * 1024) return (bytes / 1024).toStringAsFixed(1);
    if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toStringAsFixed(2);
    return (bytes / (1024 * 1024 * 1024)).toStringAsFixed(2);
  }

  String _bytesUnit(int bytes) {
    if (bytes < 1024) return 'B';
    if (bytes < 1024 * 1024) return 'KB';
    if (bytes < 1024 * 1024 * 1024) return 'MB';
    return 'GB';
  }

  @override
  Widget build(BuildContext context) {
    final upSpeed    = isConnected ? stats.uploadSpeedBps   : 0;
    final downSpeed  = isConnected ? stats.downloadSpeedBps : 0;
    final upBytes    = isConnected ? stats.uploadBytes   : 0;
    final downBytes  = isConnected ? stats.downloadBytes : 0;

    final sparkSamples = history
        .map((s) => s.downloadSpeed / (1024.0 * 1024.0))
        .toList();
    final peakDown = sparkSamples.fold<double>(0, (m, v) => v > m ? v : m);

    final pingStr = pingMs != null ? '$pingMs' : '—';

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _MetricCell(
                  t: t,
                  label: 'Протокол',
                  value: protoLabel,
                  hint: serverHint,
                  borderRight: true,
                ),
              ),
              Expanded(
                child: _MetricCell(
                  t: t,
                  label: 'Пинг',
                  value: pingStr,
                  unit: pingMs != null ? 'ms' : null,
                  alignRight: true,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _MetricCell(
                  t: t,
                  label: '↑ Отдача',
                  value: _bitrateValue(upSpeed),
                  unit: _bitrateUnit(upSpeed),
                  borderRight: true,
                ),
              ),
              Expanded(
                child: _MetricCell(
                  t: t,
                  label: '↓ Загрузка',
                  value: _bitrateValue(downSpeed),
                  unit: _bitrateUnit(downSpeed),
                  alignRight: true,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _MetricCell(
                  t: t,
                  label: '↑ Отдано',
                  value: _bytesValue(upBytes),
                  unit: _bytesUnit(upBytes),
                  borderRight: true,
                ),
              ),
              Expanded(
                child: _MetricCell(
                  t: t,
                  label: '↓ Загружено',
                  value: _bytesValue(downBytes),
                  unit: _bytesUnit(downBytes),
                  alignRight: true,
                ),
              ),
            ],
          ),
        ),
        _SparklineRow(
          t: t,
          stats: stats,
          samples: sparkSamples,
          peakMbps: peakDown,
        ),
      ],
    );
  }
}

class _MetricCell extends StatelessWidget {
  final TeapodTokens t;
  final String label;
  final String value;
  final String? unit;
  final String? hint;
  final bool borderRight;
  final bool alignRight;

  const _MetricCell({
    required this.t,
    required this.label,
    required this.value,
    this.unit,
    this.hint,
    this.borderRight = false,
    this.alignRight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 11),
      decoration: BoxDecoration(
        border: Border(
          top:   BorderSide(color: t.line, width: 1),
          right: borderRight ? BorderSide(color: t.line, width: 1) : BorderSide.none,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment:
                alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: AppTheme.mono(
                  size: 20, weight: FontWeight.w500,
                  color: t.text, letterSpacing: -0.5),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(unit!,
                    style: AppTheme.mono(size: 10, color: t.textDim)),
              ],
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 3),
            Text(hint!,
                style: AppTheme.mono(size: 10, color: t.textMuted),
                overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

// ── Sparkline row ─────────────────────────────────────────────────

class _SparklineRow extends StatelessWidget {
  final TeapodTokens t;
  final VpnStats stats;
  final List<double> samples;
  final double peakMbps;

  const _SparklineRow({
    required this.t,
    required this.stats,
    required this.samples,
    required this.peakMbps,
  });

  @override
  Widget build(BuildContext context) {
    final upTotal   = VpnStats.formatBytes(stats.uploadBytes);
    final downTotal = VpnStats.formatBytes(stats.downloadBytes);
    final duration  = VpnStats.formatDuration(stats.connectedDuration);
    final peakStr   = peakMbps >= 0.01
        ? '${peakMbps.toStringAsFixed(1)}M'
        : '0.0M';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.line, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ТРАФИК — LIVE',
                  style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
              Text('пик $peakStr',
                  style: AppTheme.mono(size: 10, color: t.textDim)),
            ],
          ),
          const SizedBox(height: 6),
          LiveSparkline(
            samples: samples.isEmpty ? List.filled(80, 0.0) : samples,
            color: t.accent,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('↑ $upTotal',
                  style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ClockIcon(color: t.textMuted, size: 10),
                  const SizedBox(width: 5),
                  Text(duration,
                      style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                ],
              ),
              Text('↓ $downTotal',
                  style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Clock icon (replaces hourglass emoji) ─────────────────────────

class _ClockIcon extends StatelessWidget {
  final Color color;
  final double size;
  const _ClockIcon({required this.color, required this.size});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size), painter: _ClockPainter(color));
}

class _ClockPainter extends CustomPainter {
  final Color color;
  const _ClockPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 0.5;
    canvas.drawCircle(c, r, p);
    // Hour hand (pointing ~10:30)
    canvas.drawLine(c, c + Offset(-r * 0.35, -r * 0.5), p);
    // Minute hand (pointing ~12:00)
    canvas.drawLine(c, c + Offset(0, -r * 0.65), p);
  }

  @override
  bool shouldRepaint(_ClockPainter old) => old.color != color;
}

// ── Helpers ───────────────────────────────────────────────────────

String _protoLabel(dynamic proto) {
  final s = proto.toString().split('.').last.toLowerCase();
  switch (s) {
    case 'vless':       return 'VLESS';
    case 'vmess':       return 'VMESS';
    case 'trojan':      return 'TROJAN';
    case 'shadowsocks': return 'SS';
    case 'hysteria2':   return 'HY2';
    default:            return s.toUpperCase();
  }
}
