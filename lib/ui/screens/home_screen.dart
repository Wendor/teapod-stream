import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/vpn_stats.dart';
import '../../providers/vpn_provider.dart';
import '../../providers/config_provider.dart';
import '../../providers/ip_info_provider.dart';
import '../../providers/app_info_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/live_sparkline.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState    = ref.watch(vpnProvider);
    final configAsync = ref.watch(configProvider);
    final version     = ref.watch(appVersionProvider).maybeWhen(data: (v) => v, orElse: () => 'v?');
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
        child: SingleChildScrollView(
          child: Column(
            children: [
              _HeaderStrip(t: t, stateCode: stateCode, version: version),
              _HeroPanel(
                t: t,
                vpnState: vpnState,
                protoLabel: protoLabel,
                pingMs: pingMs,
                canToggle: canToggle,
                onToggle: () => ref.read(vpnProvider.notifier).toggle(),
              ),
              _MetricsGrid(
                t: t,
                stats: vpnState.stats,
                protoLabel: protoLabel,
                serverHint: serverHint,
                isConnected: isConn,
                pingMs: pingMs,
                history: history,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header strip ──────────────────────────────────────────────────

class _HeaderStrip extends StatelessWidget {
  final TeapodTokens t;
  final String stateCode;
  final String version;
  const _HeaderStrip({required this.t, required this.stateCode, required this.version});

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
          Text('teapod.stream // $version',
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
  final bool canToggle;
  final VoidCallback onToggle;

  const _HeroPanel({
    required this.t,
    required this.vpnState,
    required this.protoLabel,
    required this.pingMs,
    required this.canToggle,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isConn = vpnState.isConnected;
    final isBusy = vpnState.isBusy;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.line, width: 1)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          _CornerTicks(t: t),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              children: [
                Text(
                  'ТУННЕЛЬ · $protoLabel',
                  style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1.5),
                ),
                const SizedBox(height: 20),
                _PowerCore(
                  t: t,
                  isConnected: isConn,
                  isBusy: isBusy,
                  enabled: canToggle,
                  onTap: onToggle,
                ),
                const SizedBox(height: 16),
                _StateInfo(
                  t: t,
                  vpnState: vpnState,
                  pingMs: pingMs,
                ),
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
  final int? pingMs;

  const _StateInfo({
    required this.t,
    required this.vpnState,
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          stateWord,
          style: AppTheme.sans(
            size: 28, weight: FontWeight.w500,
            color: stateColor, letterSpacing: -1, height: 1),
        ),
        const SizedBox(height: 6),
        Text(subtitle,
            style: AppTheme.mono(size: 11, color: t.textDim, letterSpacing: 0.5)),
      ],
    );
  }
}

// ── Power core ────────────────────────────────────────────────────

class _PowerCore extends StatefulWidget {
  final TeapodTokens t;
  final bool isConnected;
  final bool isBusy;
  final bool enabled;
  final VoidCallback onTap;

  const _PowerCore({
    required this.t,
    required this.isConnected,
    required this.isBusy,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_PowerCore> createState() => _PowerCoreState();
}

class _PowerCoreState extends State<_PowerCore> with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t    = widget.t;
    final conn = widget.isConnected;
    final busy = widget.isBusy;
    final actionLabel = conn ? 'отключить' : (busy ? 'ожидание' : 'подключить');

    const coreSize  = 220.0;
    const outerSize = coreSize + 32.0;
    const innerSize = coreSize - 44.0;

    return GestureDetector(
      onTap: widget.enabled ? widget.onTap : null,
      child: SizedBox(
        width: outerSize,
        height: outerSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outermost faint ring
            Container(
              width: outerSize,
              height: outerSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: conn ? t.accentSoft : t.line,
                  width: 1,
                ),
              ),
            ),
            // Spinning arc when connecting/disconnecting
            if (busy)
              SizedBox(
                width: coreSize + 10,
                height: coreSize + 10,
                child: RotationTransition(
                  turns: _spin,
                  child: CustomPaint(painter: _SpinArcPainter(t.accent)),
                ),
              ),
            // Main ring
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: coreSize,
              height: coreSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: conn ? t.accent : t.line, width: 1),
                boxShadow: conn
                    ? [BoxShadow(color: t.accentSoft, blurRadius: 60, spreadRadius: 4)]
                    : null,
              ),
            ),
            // Inner disk
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: innerSize,
              height: innerSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: conn ? t.accent : t.bgElev,
                border: Border.all(color: conn ? t.accent : t.line, width: 1),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PowerIcon(color: conn ? t.bg : t.text, size: 40),
                  const SizedBox(height: 6),
                  Text(
                    actionLabel.toUpperCase(),
                    style: AppTheme.mono(
                      size: 9,
                      color: conn ? t.bg : t.textDim,
                      letterSpacing: 2,
                    ),
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

class _SpinArcPainter extends CustomPainter {
  final Color color;
  const _SpinArcPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromLTWH(0, 0, size.width, size.height),
      -math.pi / 2,
      math.pi * 1.5,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_SpinArcPainter old) => old.color != color;
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

    canvas.drawLine(const Offset(12, 2), const Offset(12, 9), paint);
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

  @override
  Widget build(BuildContext context) {
    final upSpeed   = isConnected ? stats.uploadSpeedBps   : 0;
    final downSpeed = isConnected ? stats.downloadSpeedBps : 0;

    final sparkSamples = history
        .map((s) => s.downloadSpeed / (1024.0 * 1024.0))
        .toList();
    final peakDown = sparkSamples.fold<double>(0, (m, v) => v > m ? v : m);

    final pingStr = pingMs != null ? '$pingMs' : '—';

    return Column(
      children: [
        IntrinsicHeight(
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
        IntrinsicHeight(
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      clipBehavior: Clip.hardEdge,
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
          const SizedBox(height: 3),
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
                    style: AppTheme.mono(size: 9, color: t.textDim)),
              ],
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint!,
                maxLines: 1,
                style: AppTheme.mono(size: 9, color: t.textMuted),
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

// ── Clock icon ────────────────────────────────────────────────────

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
    canvas.drawLine(c, c + Offset(-r * 0.35, -r * 0.5), p);
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
