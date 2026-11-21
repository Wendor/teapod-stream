import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/cores/core_backend.dart';
import '../core/cores/core_resolver.dart';
import '../core/models/core_kind.dart';
import '../protocols/singbox/singbox_backend.dart';
import '../protocols/xray/xray_go_backend.dart';
import '../protocols/xray/xray_rust_backend.dart';
import '../core/models/app_settings.dart';
import 'config_provider.dart';
import 'settings_provider.dart';

CoreBackend coreBackendFor(CoreKind kind) => switch (kind) {
  CoreKind.xrayGo => const XrayGoBackend(),
  CoreKind.xrayRust => const XrayRustBackend(),
  CoreKind.singBox => const SingBoxBackend(),
};

/// Core choice for profiles by current settings. Until the list of available cores
/// is loaded, all are considered available.
final coreResolverProvider = Provider<CoreResolver>(
  (ref) => CoreResolver(
    ref.watch(settingsProvider).value ?? const AppSettings(),
    ref.watch(availableCoresProvider).value ?? CoreKind.values.toSet(),
    coreBackendFor,
  ),
);

/// The core the active profile will run on (`kind` null — none, or
/// no profile); null — settings or profiles aren't loaded yet.
final activeCoreProvider = Provider<({CoreKind? kind})?>((ref) {
  if (!ref.watch(settingsProvider).hasValue || !ref.watch(configProvider).hasValue) return null;
  final config = ref.watch(effectiveConfigProvider);
  return (kind: config == null ? null : ref.watch(coreResolverProvider).resolve(config).backend?.kind);
});

/// Cores whose native libraries load on this device.
final availableCoresProvider = FutureProvider<Set<CoreKind>>((ref) async {
  try {
    final ids =
        await const MethodChannel(AppConstants.methodChannel).invokeListMethod<String>('getAvailableEngines') ??
        const <String>[];
    return CoreKind.values.where((k) => ids.contains(k.nativeId)).toSet();
  } catch (_) {
    return {CoreKind.xrayGo};
  }
});
