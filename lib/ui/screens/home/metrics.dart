part of 'home_screen.dart';

class _MetricsGrid extends StatelessWidget {
  final TeapodTokens t;
  final VpnStats stats;
  final String serverName;
  final String serverHint;
  final bool isConnected;
  final int? pingMs;
  final List<SpeedPoint> history;
  final VoidCallback onServerTap;

  const _MetricsGrid({
    required this.t,
    required this.stats,
    required this.serverName,
    required this.serverHint,
    required this.isConnected,
    required this.pingMs,
    required this.history,
    required this.onServerTap,
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
    final upSpeed = isConnected ? stats.uploadSpeedBps : 0;
    final downSpeed = isConnected ? stats.downloadSpeedBps : 0;

    final sparkSamples = history.map((s) => s.downloadSpeed / (1024.0 * 1024.0)).toList();
    final peakDown = sparkSamples.fold<double>(0, (m, v) => v > m ? v : m);

    final pingStr = pingMs != null ? '$pingMs' : '—';

    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Semantics(
                  label: context.l10n.homeChangeServer,
                  button: true,
                  child: GestureDetector(
                    onTap: onServerTap,
                    behavior: HitTestBehavior.opaque,
                    child: _MetricCell(
                      t: t,
                      label: context.l10n.homeServer,
                      value: serverName,
                      hint: serverHint,
                      borderRight: true,
                      compactValue: true,
                      chevron: true,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _MetricCell(
                  t: t,
                  label: context.l10n.homePing,
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
                  label: '↑ ${context.l10n.homeUpload}',
                  value: _bitrateValue(upSpeed),
                  unit: _bitrateUnit(upSpeed),
                  borderRight: true,
                ),
              ),
              Expanded(
                child: _MetricCell(
                  t: t,
                  label: '↓ ${context.l10n.homeDownload}',
                  value: _bitrateValue(downSpeed),
                  unit: _bitrateUnit(downSpeed),
                  alignRight: true,
                ),
              ),
            ],
          ),
        ),
        _SparklineRow(t: t, stats: stats, samples: sparkSamples, peakMbps: peakDown),
      ],
    );
  }
}

// ── Managed config warning ────────────────────────────────────────

/// Core of the active profile (or why nothing can run it); tap for details.
class _CoreLine extends StatelessWidget {
  final TeapodTokens t;
  final CoreResolution core;
  final VoidCallback onTap;

  const _CoreLine({required this.t, required this.core, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final kind = core.backend?.kind;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        // Animate core changes (pinning, priority), otherwise it's unclear whether they applied.
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: RichText(
            key: ValueKey('${kind?.name}|${core.pinned}|${core.reason}'),
            textAlign: TextAlign.center,
            text: TextSpan(
              style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 0.5),
              children: [
                TextSpan(
                  text: '[core] ',
                  style: AppTheme.mono(
                    size: 10,
                    color: kind == null ? AppColors.accentOrange : t.accent,
                    letterSpacing: 0.5,
                  ),
                ),
                TextSpan(
                  text: kind == null
                      ? '${core.reason} · ${context.l10n.homeCoreEnableHint} ›'
                      : '${kind.displayName}${core.pinned ? ' · ${context.l10n.homeCorePinned}' : ''} ›',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ManagedWarning extends StatelessWidget {
  final TeapodTokens t;
  final RoutingDirection direction;

  const _ManagedWarning({required this.t, required this.direction});

  @override
  Widget build(BuildContext context) {
    final isOnlySelected = direction == RoutingDirection.onlySelected;
    final detail = isOnlySelected ? context.l10n.homeManagedOnlySelected : context.l10n.homeManagedDns;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.line, width: 1)),
      ),
      child: RichText(
        text: TextSpan(
          style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 0.5),
          children: [
            TextSpan(
              text: '[managed] ',
              style: AppTheme.mono(size: 10, color: AppColors.accentOrange, letterSpacing: 0.5),
            ),
            TextSpan(text: detail),
          ],
        ),
      ),
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

  /// Compact value text (for the server name instead of digits).
  final bool compactValue;
  final bool chevron;

  const _MetricCell({
    required this.t,
    required this.label,
    required this.value,
    this.unit,
    this.hint,
    this.borderRight = false,
    this.alignRight = false,
    this.compactValue = false,
    this.chevron = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: t.line, width: 1),
          right: borderRight ? BorderSide(color: t.line, width: 1) : BorderSide.none,
        ),
      ),
      child: Column(
        crossAxisAlignment: alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label.toUpperCase(), style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: compactValue ? CrossAxisAlignment.center : CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: compactValue
                      ? AppTheme.sans(size: 15, weight: FontWeight.w500, color: t.text, letterSpacing: -0.3)
                      : AppTheme.mono(size: 20, weight: FontWeight.w500, color: t.text, letterSpacing: -0.5),
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(unit!, style: AppTheme.mono(size: 9, color: t.textDim)),
              ],
              if (chevron) ...[const SizedBox(width: 6), Text('›', style: AppTheme.mono(size: 14, color: t.textDim))],
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(
              hint!,
              maxLines: 1,
              style: AppTheme.mono(size: 9, color: t.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
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

  const _SparklineRow({required this.t, required this.stats, required this.samples, required this.peakMbps});

  @override
  Widget build(BuildContext context) {
    final upTotal = VpnStats.formatBytes(stats.uploadBytes);
    final downTotal = VpnStats.formatBytes(stats.downloadBytes);
    final duration = VpnStats.formatDuration(stats.connectedDuration);
    final peakStr = peakMbps >= 0.01 ? '${peakMbps.toStringAsFixed(1)}M' : '0.0M';

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
              Text(context.l10n.homeTrafficLive, style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
              Text(context.l10n.homePeak(peakStr), style: AppTheme.mono(size: 10, color: t.textDim)),
            ],
          ),
          const SizedBox(height: 6),
          LiveSparkline(samples: samples.isEmpty ? List.filled(80, 0.0) : samples, color: t.accent),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('↑ $upTotal', style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ClockIcon(color: t.textMuted, size: 10),
                  const SizedBox(width: 5),
                  Text(duration, style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                ],
              ),
              Text('↓ $downTotal', style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
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
  Widget build(BuildContext context) => CustomPaint(size: Size(size, size), painter: _ClockPainter(color));
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
