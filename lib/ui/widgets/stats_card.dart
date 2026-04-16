import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/vpn_stats.dart';
import '../theme/app_colors.dart';

class _SpeedPoint {
  final double upload;
  final double download;
  const _SpeedPoint({required this.upload, required this.download});
}

class StatsCard extends StatefulWidget {
  final VpnStats stats;
  final VpnState connectionState;

  const StatsCard({
    super.key,
    required this.stats,
    required this.connectionState,
  });

  @override
  State<StatsCard> createState() => _StatsCardState();
}

class _StatsCardState extends State<StatsCard> {
  static const _maxPoints = 300; // 5 minutes × 1 tick/sec
  final List<_SpeedPoint> _history = [];
  Timer? _ticker;
  DateTime? _lastTickTime;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        final now = DateTime.now();

        // Если с последнего тика прошло больше 2 секунд — приложение было
        // в фоне. Заполняем пропуск нулями, чтобы не было длинных полос.
        if (_lastTickTime != null) {
          final gap = now.difference(_lastTickTime!).inSeconds;
          if (gap > 2) {
            final zeros = min(gap - 1, _maxPoints);
            for (var i = 0; i < zeros; i++) {
              _history.add(const _SpeedPoint(upload: 0, download: 0));
              if (_history.length > _maxPoints) _history.removeAt(0);
            }
          }
        }
        _lastTickTime = now;

        final connected = widget.connectionState == VpnState.connected;
        _history.add(_SpeedPoint(
          upload: connected ? widget.stats.uploadSpeedBps.toDouble() : 0,
          download: connected ? widget.stats.downloadSpeedBps.toDouble() : 0,
        ));
        if (_history.length > _maxPoints) _history.removeAt(0);
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  // Всегда 300 слотов: слева нули, справа реальные данные.
  // По мере заполнения нули «уходят» влево — эффект прокрутки.
  List<_SpeedPoint> get _paddedHistory {
    if (_history.length >= _maxPoints) return _history;
    final pad = List.filled(
      _maxPoints - _history.length,
      const _SpeedPoint(upload: 0, download: 0),
    );
    return [...pad, ..._history];
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.connectionState == VpnState.connected;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Speed chart
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: SizedBox(
              height: 80,
              width: double.infinity,
              child: CustomPaint(
                painter: _SpeedChartPainter(_paddedHistory),
              ),
            ),
          ),
          // Stats rows
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    _StatItem(
                      icon: Icons.arrow_upward_rounded,
                      label: 'Отдача',
                      value: isActive
                          ? VpnStats.formatSpeed(widget.stats.uploadSpeedBps)
                          : '—',
                      color: AppColors.chartUpload,
                    ),
                    const SizedBox(width: 12),
                    _StatItem(
                      icon: Icons.arrow_downward_rounded,
                      label: 'Загрузка',
                      value: isActive
                          ? VpnStats.formatSpeed(
                              widget.stats.downloadSpeedBps)
                          : '—',
                      color: AppColors.chartDownload,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _StatItem(
                      icon: Icons.cloud_upload_outlined,
                      label: 'Отдано',
                      value: isActive
                          ? VpnStats.formatBytes(widget.stats.uploadBytes)
                          : '—',
                      color: AppColors.chartUpload,
                    ),
                    const SizedBox(width: 12),
                    _StatItem(
                      icon: Icons.cloud_download_outlined,
                      label: 'Загружено',
                      value: isActive
                          ? VpnStats.formatBytes(widget.stats.downloadBytes)
                          : '—',
                      color: AppColors.chartDownload,
                    ),
                  ],
                ),
                if (isActive) ...[
                  const SizedBox(height: 12),
                  _StatItem(
                    icon: Icons.timer_outlined,
                    label: 'Время подключения',
                    value: VpnStats.formatDuration(
                        widget.stats.connectedDuration),
                    color: AppColors.textSecondary,
                    expanded: true,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedChartPainter extends CustomPainter {
  final List<_SpeedPoint> history;

  _SpeedChartPainter(this.history);

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = AppColors.surfaceElevated,
    );

    // Center divider
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()
        ..color = AppColors.border
        ..strokeWidth = 0.5,
    );

    if (history.length < 2) return;

    final maxVal = history.fold(
      0.0,
      (m, p) => max(m, max(p.upload, p.download)),
    );
    if (maxVal == 0) return;

    final mid = size.height / 2;
    final amplitude = mid * 0.88;

    // Download — top half, green
    _drawArea(
      canvas,
      size,
      history.map((p) => p.download / maxVal).toList(),
      mid,
      amplitude,
      isUp: true,
      color: AppColors.chartDownload,
    );

    // Upload — bottom half, blue
    _drawArea(
      canvas,
      size,
      history.map((p) => p.upload / maxVal).toList(),
      mid,
      amplitude,
      isUp: false,
      color: AppColors.chartUpload,
    );
  }

  void _drawArea(
    Canvas canvas,
    Size size,
    List<double> ratios,
    double mid,
    double amplitude, {
    required bool isUp,
    required Color color,
  }) {
    final n = ratios.length;
    final xStep = size.width / (n - 1);

    double _y(int i) {
      final v = ratios[i].clamp(0.0, 1.0) * amplitude;
      return isUp ? mid - v : mid + v;
    }

    final fillPath = Path()..moveTo(0, mid);
    final linePath = Path()..moveTo(0, _y(0));

    for (int i = 0; i < n - 1; i++) {
      final x0 = i * xStep;
      final x1 = (i + 1) * xStep;
      final y0 = _y(i);
      final y1 = _y(i + 1);
      final cpx = (x0 + x1) / 2;
      fillPath.cubicTo(cpx, y0, cpx, y1, x1, y1);
      linePath.cubicTo(cpx, y0, cpx, y1, x1, y1);
    }

    fillPath.lineTo((n - 1) * xStep, mid);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..color = color.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      linePath,
      Paint()
        ..color = color.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SpeedChartPainter old) => true;
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool expanded;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (expanded) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: content,
      );
    }

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: content,
      ),
    );
  }
}
