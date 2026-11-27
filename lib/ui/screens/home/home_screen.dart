import 'dart:math' as math;
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import '../../../providers/core_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/routing_settings.dart';
import '../../../core/models/vpn_stats.dart';
import '../../../providers/vpn_provider.dart';
import '../../../providers/config_provider.dart';
import '../../../providers/ip_info_provider.dart';
import '../../../providers/app_info_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../../providers/app_lifecycle_provider.dart';
import '../../widgets/live_sparkline.dart';
import '../../widgets/reconnect_banner.dart';
import '../../widgets/server_picker_sheet.dart';
import '../../widgets/core_sheet.dart';
import '../../widgets/pressable.dart';
import '../../widgets/tap_target.dart';
import '../../../core/cores/core_resolver.dart';
import '../logs_screen.dart';
import '../../../l10n/l10n.dart';
import '../../../providers/vpn_stats_provider.dart';

part 'header.dart';
part 'metrics.dart';
part 'power.dart';
part 'ticks.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnProvider);
    final stats = ref.watch(vpnStatsProvider);
    final effectiveConfig = ref.watch(effectiveConfigProvider);
    final version = ref.watch(appVersionProvider).maybeWhen(data: (v) => v, orElse: () => 'v?');
    final t = Theme.of(context).extension<TeapodTokens>()!;
    final core = effectiveConfig == null ? null : ref.watch(coreResolverProvider).resolve(effectiveConfig);
    final unsupported = core?.reason;
    // A profile no core supports can't be connected; disconnecting is still allowed.
    final canToggle = effectiveConfig != null && (unsupported == null || vpnState.isConnected || vpnState.isBusy);
    final pingMs = effectiveConfig?.latencyMs;

    final isConn = vpnState.isConnected;
    final isBusy = vpnState.isBusy;
    final stateCode = isConn ? '01' : (isBusy ? '02' : '00');

    final protoLabel = effectiveConfig != null ? effectiveConfig.protoTag : '—';
    final serverHint = effectiveConfig != null ? '${effectiveConfig.address}:${effectiveConfig.port}' : '—';

    final history = stats.speedHistory;

    final isManaged = effectiveConfig?.rawXrayConfig != null;
    final routingDirection = ref.watch(
      settingsProvider.select(
        (s) => s.maybeWhen(data: (d) => d.routing.direction, orElse: () => RoutingDirection.global),
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _HeaderStrip(t: t, stateCode: stateCode, version: version),
              const ReconnectBanner(),
              _HeroPanel(
                t: t,
                vpnState: vpnState,
                protoLabel: protoLabel,
                pingMs: pingMs,
                canToggle: canToggle,
                disabledLabel: effectiveConfig == null ? context.l10n.homeNoConfigShort : context.l10n.homeUnsupported,
                onToggle: () => ref.read(vpnProvider.notifier).toggle(),
                // Without configs (or on a load error) the button opens the Configs tab;
                // while they are loading (right after launch) it does nothing, otherwise a
                // "Connect" tap led there (#151).
                onDisabledTap: () {
                  final configs = ref.read(configProvider);
                  if (configs.hasValue || configs.hasError) ref.read(tabIndexProvider.notifier).set(1);
                },
                coreLine: core == null
                    ? null
                    : _CoreLine(t: t, core: core, onTap: () => showCoreSheet(context, effectiveConfig!)),
              ),
              _MetricsGrid(
                t: t,
                stats: stats,
                serverName: effectiveConfig?.name ?? '—',
                serverHint: effectiveConfig != null ? '$protoLabel · $serverHint' : context.l10n.homeNoConfig,
                isConnected: isConn,
                pingMs: pingMs,
                history: history,
                onServerTap: () => showServerPicker(context, ref),
              ),
              if (isManaged) _ManagedWarning(t: t, direction: routingDirection),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header strip ──────────────────────────────────────────────────
