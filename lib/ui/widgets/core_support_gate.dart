import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/vpn_config.dart';
import '../../providers/core_provider.dart';

/// A profile no core can run: dimmed, with the reason below.
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

/// Why [config] can't be selected for connection, or null.
String? unsupportedReason(WidgetRef ref, VpnConfig config) =>
    ref.read(coreResolverProvider).resolve(config).reason;

/// The profile's core for a list row — only if it's not the primary core
/// (the first enabled one): this way only exceptions are visible.
String? coreNote(WidgetRef ref, VpnConfig config) {
  final resolver = ref.watch(coreResolverProvider);
  final kind = resolver.resolve(config).backend?.kind;
  return kind == null || kind == resolver.primary ? null : kind.displayName;
}
