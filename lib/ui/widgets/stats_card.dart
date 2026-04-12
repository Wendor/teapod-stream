import 'package:flutter/material.dart';
import '../../core/interfaces/vpn_engine.dart';
import '../../core/models/vpn_stats.dart';
import '../theme/app_colors.dart';

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
          // Stats rows
          Padding(
            padding: const EdgeInsets.all(16),
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
