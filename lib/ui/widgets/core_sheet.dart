import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cores/engine_options.dart';
import '../../core/models/core_kind.dart';
import '../../core/models/vpn_config.dart';
import '../../providers/config_provider.dart';
import '../../providers/core_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'settings_shared.dart';

/// Каким ядром запускается профиль, почему не другими; закрепление ядра.
Future<void> showCoreSheet(BuildContext context, VpnConfig config) {
  final t = Theme.of(context).extension<TeapodTokens>()!;
  return showModalBottomSheet(
    context: context,
    backgroundColor: t.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    isScrollControlled: true,
    builder: (_) => _CoreSheet(configId: config.id),
  );
}

class _CoreSheet extends ConsumerWidget {
  final String configId;
  const _CoreSheet({required this.configId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    final config = ref.watch(configProvider).value?.configs.where((c) => c.id == configId).firstOrNull;
    if (config == null) return const SizedBox.shrink();
    final resolver = ref.watch(coreResolverProvider);
    final r = resolver.resolve(config);
    final chosen = r.backend;
    final warnings = chosen == null
        ? const <String>[]
        : chosen.checkOptions(config, buildEngineOptions(resolver.settings, config, chosen)).warnings;
    final pinOptions = [
      for (final v in r.verdicts)
        if (v.reason == null || v.kind == config.core) v.kind,
    ];

    void pin(String value) {
      final kind = CoreKind.tryName(value);
      ref.read(configProvider.notifier).updateConfig(
          kind == null ? config.copyWith(clearCore: true) : config.copyWith(core: kind));
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(config.name,
                      style: AppTheme.sans(size: 16, color: t.text, weight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis),
                ),
                Text('CORE', style: AppTheme.mono(size: 10, color: t.textMuted)),
              ],
            ),
          ),
          Container(height: 1, color: t.line),
          for (final v in r.verdicts)
            _VerdictRow(
              t: t,
              mark: v.kind == config.core ? '★' : '${resolver.settings.coreOrder.indexOf(v.kind) + 1}',
              name: v.kind.displayName,
              status: v.kind == chosen?.kind ? 'используется' : (v.reason ?? 'совместимо'),
              active: v.kind == chosen?.kind,
              warnings: v.kind == chosen?.kind ? warnings : const [],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Text('ЯДРО ПРОФИЛЯ',
                style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SetSegSquare(
                  t: t,
                  value: config.core?.name ?? '',
                  opts: [('', 'АВТО'), for (final k in pinOptions) (k.name, k.shortLabel)],
                  onChanged: pin,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text(
                'АВТО — первое подходящее ядро по приоритету из настроек. '
                'Закреплённое ядро пробуется первым.',
                style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 0.3)),
          ),
        ],
      ),
    );
  }
}

class _VerdictRow extends StatelessWidget {
  final TeapodTokens t;
  final String mark;
  final String name;
  final String status;
  final bool active;
  final List<String> warnings;

  const _VerdictRow({
    required this.t,
    required this.mark,
    required this.name,
    required this.status,
    required this.active,
    required this.warnings,
  });

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: active ? t.accentFade : Colors.transparent,
          border: Border(bottom: BorderSide(color: t.lineSoft)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              child: Text(mark, style: AppTheme.mono(size: 11, color: active ? t.accent : t.textMuted)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: AppTheme.sans(size: 14, color: active ? t.accent : t.text)),
                  const SizedBox(height: 3),
                  Text(status,
                      style: AppTheme.mono(size: 10, color: active ? t.accent : t.textMuted, letterSpacing: 0.3)),
                  for (final w in warnings) ...[
                    const SizedBox(height: 3),
                    Text('⚠ $w',
                        style: AppTheme.mono(size: 10, color: AppColors.accentOrange, letterSpacing: 0.3)),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}
