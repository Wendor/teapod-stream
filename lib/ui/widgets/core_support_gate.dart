import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/vpn_config.dart';
import '../../providers/core_provider.dart';

/// Профиль, который не запускает ни одно ядро: приглушён, под ним причина.
class CoreSupportGate extends ConsumerWidget {
  final VpnConfig config;
  final Widget child;

  const CoreSupportGate({super.key, required this.config, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reason = ref.watch(coreResolverProvider).resolve(config).reason;
    if (reason == null) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(opacity: 0.45, child: child),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
          child: Text(reason, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

/// Причина, по которой [config] нельзя выбрать для подключения, или null.
String? unsupportedReason(WidgetRef ref, VpnConfig config) =>
    ref.read(coreResolverProvider).resolve(config).reason;

/// Ядро профиля для строки списка — только если это не основное ядро
/// (первое включённое): так видны лишь исключения.
String? coreNote(WidgetRef ref, VpnConfig config) {
  final resolver = ref.watch(coreResolverProvider);
  final kind = resolver.resolve(config).backend?.kind;
  return kind == null || kind == resolver.primary ? null : kind.displayName;
}
