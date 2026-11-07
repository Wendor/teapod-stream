import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cores/core_backend.dart';
import '../../providers/core_provider.dart';

/// Настройка, которую часть включённых ядер не поддерживает: остаётся
/// доступной (её применят другие ядра), под ней — какие ядра её не применят.
class FeatureGate extends ConsumerWidget {
  final CoreFeature feature;
  final Widget child;

  const FeatureGate({super.key, required this.feature, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lacking = [
      for (final k in ref.watch(coreResolverProvider).usable)
        if (!coreBackendFor(k).supports(feature)) k.displayName,
    ];
    if (lacking.isEmpty) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Text('Не поддерживается: ${lacking.join(', ')}.',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}
