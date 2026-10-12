import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/models/vpn_stats.dart';
import '../../core/services/config_storage_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class SubscriptionStatusCard extends StatelessWidget {
  final TeapodTokens t;
  final Subscription subscription;
  final bool isRefreshing;
  final VoidCallback? onRefresh;

  const SubscriptionStatusCard({
    super.key,
    required this.t,
    required this.subscription,
    this.isRefreshing = false,
    this.onRefresh,
  });

  String _formatDate(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year.toString();
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final usedBytes = (subscription.uploadBytes ?? 0) + (subscription.downloadBytes ?? 0);
    final totalBytes = subscription.totalBytes;
    final hasTotal = totalBytes != null && totalBytes > 0;

    int routeRuleCount = 0;
    if (subscription.routingJson != null && subscription.useSubscriptionRouting) {
      try {
        final decoded = jsonDecode(subscription.routingJson!);
        if (decoded is List) routeRuleCount = decoded.length;
      } catch (_) {}
    }

    final usedStr = VpnStats.formatBytes(usedBytes);
    final totalStr = hasTotal ? VpnStats.formatBytes(totalBytes) : '∞';
    final remainingBytes = hasTotal ? (totalBytes - usedBytes).clamp(0, totalBytes) : null;
    final remainingRatio = hasTotal ? (remainingBytes! / totalBytes).clamp(0.0, 1.0) : 1.0;
    final remStr = hasTotal ? VpnStats.formatBytes(remainingBytes!) : '∞';

    final barText = hasTotal
        ? '$remStr / $totalStr'
        : (usedBytes > 0 ? '$usedStr / ∞' : '∞');

    final expireAt = subscription.expireAt;
    final announce = subscription.announce;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: t.bgElev,
        border: Border(bottom: BorderSide(color: t.line, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Name + Refresh
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      'ПОДПИСКА',
                      style: AppTheme.mono(size: 9, color: t.textMuted, letterSpacing: 1.2),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        subscription.name,
                        style: AppTheme.sans(
                          size: 14,
                          weight: FontWeight.w600,
                          color: t.text,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (routeRuleCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                        decoration: BoxDecoration(
                          border: Border.all(color: t.accent.withAlpha(120), width: 0.8),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          'ROUTE: $routeRuleCount',
                          style: AppTheme.mono(size: 8, color: t.accent, letterSpacing: 0.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onRefresh != null)
                Semantics(
                  label: 'обновить подписку',
                  button: true,
                  child: GestureDetector(
                    onTap: isRefreshing ? null : onRefresh,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: isRefreshing
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: t.accent,
                              ),
                            )
                          : Icon(
                              Icons.refresh_rounded,
                              size: 16,
                              color: t.textDim,
                            ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Progress Bar with centered text (full initially, empties as traffic is consumed)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background bar
                Container(
                  height: 20,
                  width: double.infinity,
                  color: t.bg,
                ),
                // Remaining traffic fill (initially 100% full, empties as traffic is spent)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  right: 0,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: remainingRatio,
                    child: Container(
                      color: t.accent.withAlpha(160),
                    ),
                  ),
                ),
                // Text overlay
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    barText,
                    style: AppTheme.mono(
                      size: 11,
                      weight: FontWeight.w600,
                      color: t.text,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Footer info: expireAt, announce
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (expireAt != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.access_time_rounded, size: 11, color: t.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(expireAt),
                      style: AppTheme.mono(size: 10, color: t.textMuted),
                    ),
                  ],
                )
              else
                const SizedBox.shrink(),
              if (hasTotal) ...[
                Text(
                  'потрачено $usedStr',
                  style: AppTheme.mono(size: 10, color: t.textDim),
                ),
              ],
            ],
          ),
          if (announce != null && announce.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              announce.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.mono(size: 9, color: t.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
