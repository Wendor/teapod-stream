import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cores/core_backend.dart';
import '../../core/models/vpn_config.dart';
import '../../providers/core_provider.dart';

/// Профиль, который активное ядро не запустит: приглушён, под ним причина.
class CoreSupportGate extends ConsumerWidget {
  final VpnConfig config;
  final Widget child;

  /// Для тестов; по умолчанию — ядро из настроек.
  final CoreBackend? backend;

  const CoreSupportGate({super.key, required this.config, required this.child, this.backend});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CoreBackend core = backend ?? ref.watch(coreBackendProvider);
    final reason = core.checkConfig(config);
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
    ref.read(coreBackendProvider).checkConfig(config);
