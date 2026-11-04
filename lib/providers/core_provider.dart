import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/cores/core_backend.dart';
import '../core/models/core_kind.dart';
import '../protocols/xray/xray_go_backend.dart';
import '../protocols/xray/xray_rust_backend.dart';
import 'settings_provider.dart';

CoreBackend coreBackendFor(CoreKind kind) => switch (kind) {
      CoreKind.xrayGo => const XrayGoBackend(),
      CoreKind.xrayRust => const XrayRustBackend(),
    };

/// Backend ядра, выбранного в настройках.
final coreBackendProvider = Provider<CoreBackend>((ref) {
  final kind = ref.watch(settingsProvider.select((s) => s.value?.core ?? CoreKind.xrayGo));
  return coreBackendFor(kind);
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
