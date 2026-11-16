import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cores/core_backend.dart';
import '../../providers/core_provider.dart';
import '../../l10n/l10n.dart';

/// A setting some enabled cores don't support: it stays available
/// (other cores apply it), with the cores that won't apply it listed below.
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
          child: Text(
            context.l10n.featureUnsupported(lacking.join(', ')),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
