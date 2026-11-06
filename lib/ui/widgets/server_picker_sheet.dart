import 'package:flutter/material.dart';
import 'core_support_gate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/vpn_config.dart';
import '../../providers/config_provider.dart';
import '../../providers/vpn_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Bottom sheet быстрой смены сервера: пины сверху, дальше группы.
/// Выбор при подключённом VPN — автоматический reconnect.
Future<void> showServerPicker(BuildContext context, WidgetRef ref) {
  final t = Theme.of(context).extension<TeapodTokens>()!;
  return showModalBottomSheet(
    context: context,
    backgroundColor: t.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    isScrollControlled: true,
    builder: (ctx) => const _ServerPickerSheet(),
  );
}

class _ServerPickerSheet extends ConsumerWidget {
  const _ServerPickerSheet();

  void _select(BuildContext context, WidgetRef ref, VpnConfig c) {
    final reason = unsupportedReason(ref, c);
    if (reason != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reason)));
      return;
    }
    Navigator.pop(context);
    ref.read(configProvider.notifier).setActiveConfig(c.id);
    final vpnState = ref.read(vpnProvider);
    if (vpnState.isConnected || vpnState.isBusy) {
      ref.read(vpnProvider.notifier).reconnectWithNewConfig();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    final cs = ref.watch(configProvider).maybeWhen(data: (d) => d, orElse: () => null);
    if (cs == null) return const SizedBox.shrink();

    final pinned = cs.resolvedPins
        .where((e) => e.$2 != null)
        .map((e) => e.$2!)
        .toList();

    final sections = <(String, List<VpnConfig>)>[
      if (pinned.isNotEmpty) ('[pinned]', pinned),
      if (cs.standaloneConfigs.isNotEmpty) ('[local]', cs.standaloneConfigs),
      for (final sub in cs.subscriptions)
        if ((cs.configsBySubscription[sub.id] ?? []).isNotEmpty)
          (sub.name, cs.configsBySubscription[sub.id]!),
    ];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(children: [
                Expanded(
                  child: Text('select // server',
                      style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                ),
                Text('${cs.configs.length}',
                    style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
              ]),
            ),
            Container(height: 1, color: t.line),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final (title, configs) in sections) ...[
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                      child: Text(title,
                          style: AppTheme.mono(
                              size: 10, color: t.textMuted, letterSpacing: 1)),
                    ),
                    for (final c in configs)
                      _PickerRow(
                        t: t,
                        config: c,
                        isActive: c.id == cs.activeConfigId,
                        onTap: () => _select(context, ref, c),
                      ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  final TeapodTokens t;
  final VpnConfig config;
  final bool isActive;
  final VoidCallback onTap;

  const _PickerRow({
    required this.t,
    required this.config,
    required this.isActive,
    required this.onTap,
  });

  String get _protoTag => config.protoTag;

  @override
  Widget build(BuildContext context) =>
      CoreSupportGate(config: config, child: _buildRow(context));

  Widget _buildRow(BuildContext context) {
    final ping = config.latencyMs;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: isActive ? t.accentFade : Colors.transparent,
          border: Border(bottom: BorderSide(color: t.lineSoft)),
        ),
        child: Stack(
          children: [
            if (isActive)
              Positioned(
                left: 0, top: 0, bottom: 0,
                child: Container(width: 2, color: t.accent),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 11, 20, 11),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                        border: Border.all(color: isActive ? t.accent : t.line)),
                    constraints: const BoxConstraints(minWidth: 44),
                    child: Text(_protoTag,
                        textAlign: TextAlign.center,
                        style: AppTheme.mono(
                            size: 10,
                            color: isActive ? t.accent : t.textDim,
                            letterSpacing: 1)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(config.name,
                        style: AppTheme.sans(
                            size: 13,
                            weight: FontWeight.w500,
                            color: t.text,
                            letterSpacing: -0.2),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (ping != null) ...[
                    const SizedBox(width: 8),
                    Text('${ping}ms',
                        style: AppTheme.mono(size: 11, color: t.accent)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
