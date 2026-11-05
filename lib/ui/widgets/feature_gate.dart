import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cores/core_backend.dart';
import '../../providers/core_provider.dart';

/// Настройка, которую активное ядро не поддерживает: видна, но неактивна,
/// с причиной. Сохранённое значение не трогается — вернётся с другим ядром.
class FeatureGate extends ConsumerWidget {
  final CoreFeature feature;
  final Widget child;

  /// Для тестов; по умолчанию — ядро из настроек.
  final CoreBackend? backend;

  /// Значение включено: оставить переключатель активным, чтобы его можно было
  /// выключить (иначе блокирующую настройку не снять, не вернувшись на другое ядро).
  final bool allowTurnOff;

  const FeatureGate({
    super.key,
    required this.feature,
    required this.child,
    this.backend,
    this.allowTurnOff = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CoreBackend core = backend ?? ref.watch(coreBackendProvider);
    final reason = core.unavailableReason(feature);
    if (reason == null) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (allowTurnOff)
          child
        else
          Semantics(
            enabled: false,
            child: ExcludeFocus(
              child: AbsorbPointer(child: Opacity(opacity: 0.45, child: child)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Text(reason, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}
