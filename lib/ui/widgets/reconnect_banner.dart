// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/vpn_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../../l10n/l10n.dart';
import 'tap_target.dart';

/// "Settings changed — reconnect" banner.
/// Visible only when pendingReconnectProvider == true.
class ReconnectBanner extends ConsumerWidget {
  const ReconnectBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingReconnectProvider);
    if (!pending) return const SizedBox.shrink();
    final t = Theme.of(context).extension<TeapodTokens>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: BoxDecoration(
        color: t.accentFade,
        border: Border(bottom: BorderSide(color: t.accent, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.l10n.reconnectBanner,
              style: AppTheme.mono(size: 10, color: t.text, letterSpacing: 0.5),
            ),
          ),
          const SizedBox(width: 12),
          TapTarget(
            label: context.l10n.homeActionReconnect,
            onTap: () => ref.read(vpnProvider.notifier).reconnectWithNewConfig(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: t.accent,
              child: Text(context.l10n.reconnectButton, style: AppTheme.mono(size: 9, color: t.bg, letterSpacing: 1)),
            ),
          ),
        ],
      ),
    );
  }
}
