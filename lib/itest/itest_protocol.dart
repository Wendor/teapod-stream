import 'dart:convert';

import '../core/cores/core_resolver.dart';
import '../core/models/core_kind.dart';

/// Сборка с агентом интеграционных тестов (`./build.sh itest`).
const bool kItest = bool.fromEnvironment('ITEST');

/// Строка-маркер в logcat, которую читает раннер `tool/itest`.
String itestMarker(Map<String, Object?> payload) => 'TEAPOD_ITEST ${jsonEncode(payload)}';

/// Вложенные Map сливаются, остальные значения (в т.ч. списки) заменяются.
Map<String, dynamic> deepMerge(Map<String, dynamic> base, Map<String, dynamic> patch) => {
      ...base,
      for (final e in patch.entries)
        e.key: e.value is Map && base[e.key] is Map
            ? deepMerge(Map<String, dynamic>.from(base[e.key] as Map),
                Map<String, dynamic>.from(e.value as Map))
            : e.value,
    };

/// null — профиль запустится именно ядром [wanted]; иначе причина.
String? pickCoreError(CoreResolution r, CoreKind wanted) {
  if (r.backend?.kind == wanted && r.pinned) return null;
  final reason = r.verdicts.where((v) => v.kind == wanted).firstOrNull?.reason;
  return reason ?? 'resolved to ${r.backend?.kind.displayName ?? 'none'}';
}
