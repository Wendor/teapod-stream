import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/cores/core_backend.dart';
import '../core/cores/core_resolver.dart';
import '../core/models/core_kind.dart';
import '../protocols/singbox/singbox_backend.dart';
import '../protocols/xray/xray_go_backend.dart';
import '../protocols/xray/xray_rust_backend.dart';
import '../core/services/settings_service.dart';
import 'config_provider.dart';
import 'settings_provider.dart';

CoreBackend coreBackendFor(CoreKind kind) => switch (kind) {
      CoreKind.xrayGo => const XrayGoBackend(),
      CoreKind.xrayRust => const XrayRustBackend(),
      CoreKind.singBox => const SingBoxBackend(),
    };

/// Выбор ядра для профилей по текущим настройкам. Пока список доступных ядер
/// не загружен, доступными считаются все.
final coreResolverProvider = Provider<CoreResolver>((ref) => CoreResolver(
      ref.watch(settingsProvider).value ?? const AppSettings(),
      ref.watch(availableCoresProvider).value ?? CoreKind.values.toSet(),
      coreBackendFor,
    ));

/// Ядро, которым запустится активный профиль (`kind` null — ни одним или
/// профиля нет); null — настройки или профили ещё не загружены.
final activeCoreProvider = Provider<({CoreKind? kind})?>((ref) {
  if (!ref.watch(settingsProvider).hasValue || !ref.watch(configProvider).hasValue) return null;
  final config = ref.watch(effectiveConfigProvider);
  return (kind: config == null ? null : ref.watch(coreResolverProvider).resolve(config).backend?.kind);
});

/// Ядра, нативные библиотеки которых загружаются на этом устройстве.
final availableCoresProvider = FutureProvider<Set<CoreKind>>((ref) async {
  try {
    final ids = await const MethodChannel(AppConstants.methodChannel)
            .invokeListMethod<String>('getAvailableEngines') ??
        const <String>[];
    return CoreKind.values.where((k) => ids.contains(k.nativeId)).toSet();
  } catch (_) {
    return {CoreKind.xrayGo};
  }
});
