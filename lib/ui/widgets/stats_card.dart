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
  static const _maxPoints = 300;
  final List<_SpeedPoint> _history = [];
  Timer? _ticker;
  DateTime? _lastTickTime;
  int _lastHistoryLength = 0;

  List<_SpeedPoint> _convertHistory(List<SpeedPoint> native) {
    return native.map((p) => _SpeedPoint(
      upload: p.uploadSpeed.toDouble(),
      download: p.downloadSpeed.toDouble(),
    )).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadHistoryFromNative();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.connectionState == VpnState.disconnected) {
        // Clear history when disconnected
        if (_history.isNotEmpty) {
          setState(() {
            _history.clear();
            _lastHistoryLength = 0;
            _lastTickTime = null;
          });
        }
        return;
      }

      setState(() {
        final now = DateTime.now();

        // Gap detection - if app was in background, add zeros
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

        // Always sync with native history - it's the source of truth
        final nativeHistory = widget.stats.speedHistory;
        if (nativeHistory.isEmpty) {
          // No history yet, nothing to do
          return;
        }

        // If length changed, sync - either full reload or append
        if (nativeHistory.length != _lastHistoryLength) {
          if (_lastHistoryLength == 0 || _history.isEmpty) {
            // First load or reload - full sync
            _history.clear();
            _history.addAll(_convertHistory(nativeHistory));
          } else if (nativeHistory.length > _lastHistoryLength) {
            // Append new points
            _history.addAll(_convertHistory(nativeHistory.sublist(_lastHistoryLength)));
          }
          _lastHistoryLength = nativeHistory.length;
        }

        while (_history.length > _maxPoints) {
          _history.removeAt(0);
        }
      });
    });
  }

  void _loadHistoryFromNative() {
    final nativeHistory = widget.stats.speedHistory;
    _history.clear();
    if (nativeHistory.isNotEmpty) {
      _history.addAll(_convertHistory(nativeHistory));
    }
    _lastHistoryLength = nativeHistory.length;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _maxSpeedLabel {
    if (_history.isEmpty) return '';
    final maxVal = _history.fold<double>(0, (m, p) => max(m, max(p.upload, p.download)));
    final bits = maxVal * 8;
    if (bits < 1024) return '';
    if (bits < 1024 * 1024) return 'пик: ${(bits / 1024).toStringAsFixed(0)} Kbit/s';
    return 'пик: ${(bits / (1024 * 1024)).toStringAsFixed(1)} Mbit/s';
  }

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
          // Max speed label
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(
              child: Text(
                _maxSpeedLabel,
                style: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.7),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    _StatItem(
                      icon: Icons.timer_outlined,
                      label: 'Время',
                      value: VpnStats.formatDuration(widget.stats.connectedDuration),
                      color: AppColors.textSecondary,
                    ),
                    const Spacer(),
                    if (widget.stats.connectedServer != null)
                      Text(
                        widget.stats.connectedServer!,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
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
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
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

class _SpeedChartPainter extends CustomPainter {
  final List<_SpeedPoint> history;
  static final _uploadPaint = Paint()
    ..color = AppColors.chartUpload
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke;
  static final _downloadPaint = Paint()
    ..color = AppColors.chartDownload
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke;

  _SpeedChartPainter(this.history);

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;

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

    double y(int i) {
      final v = ratios[i].clamp(0.0, 1.0) * amplitude;
      return isUp ? mid - v : mid + v;
    }

    final fillPath = Path();
    final linePath = Path();

    for (var i = 0; i < n; i++) {
      final x = i * xStep;
      final yVal = y(i);

      if (i == 0) {
        fillPath.moveTo(x, mid);
        fillPath.lineTo(x, yVal);
        linePath.moveTo(x, yVal);
      } else {
        fillPath.lineTo(x, yVal);
        linePath.lineTo(x, yVal);
      }
    }

    fillPath.lineTo(size.width, mid);
    fillPath.close();

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(linePath, color == AppColors.chartDownload ? _downloadPaint : _uploadPaint);
  }

  // Длина _paddedHistory всегда _maxPoints, так что сравнение длин означало
  // «никогда не перерисовывать» — после поворота экрана график оставался в
  // старой раскладке до чужой перерисовки слоя. Painter пересоздаётся только
  // из setState тикера (данные к этому моменту изменились) — репейнт честный.
  @override
  bool shouldRepaint(_SpeedChartPainter old) => true;
}
