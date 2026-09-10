import 'package:flutter/material.dart';
import '../../core/constants/core_features.dart';

/// Keep settings visible, but prevent unsupported changes and explain why.
/// Reset is explicit so imported settings are never silently discarded.
class FeatureGate extends StatelessWidget {
  final CoreFeature feature;
  final Widget child;
  final VoidCallback? onReset;
  final CoreFeatures features;

  const FeatureGate({
    super.key,
    required this.feature,
    required this.child,
    this.onReset,
    this.features = CoreFeatures.current,
  });

  @override
  Widget build(BuildContext context) {
    if (features.supports(feature)) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          enabled: false,
          child: ExcludeFocus(
            child: AbsorbPointer(child: Opacity(opacity: 0.45, child: child)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                features.unavailableReason(feature) ??
                    'Функция недоступна в выбранной сборке.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (onReset != null)
                TextButton(
                  onPressed: onReset,
                  child: const Text('Сбросить неподдерживаемое значение'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
