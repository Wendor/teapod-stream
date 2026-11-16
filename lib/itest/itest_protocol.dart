import 'dart:convert';

import '../core/cores/core_resolver.dart';
import '../core/models/core_kind.dart';

/// Build with the integration test agent (`./build.sh itest`).
const bool kItest = bool.fromEnvironment('ITEST');

/// Marker line in logcat read by the `tool/itest` runner.
String itestMarker(Map<String, Object?> payload) => 'TEAPOD_ITEST ${jsonEncode(payload)}';

/// Nested Maps are merged, other values (including lists) are replaced.
Map<String, dynamic> deepMerge(Map<String, dynamic> base, Map<String, dynamic> patch) => {
      ...base,
      for (final e in patch.entries)
        e.key: e.value is Map && base[e.key] is Map
            ? deepMerge(Map<String, dynamic>.from(base[e.key] as Map),
                Map<String, dynamic>.from(e.value as Map))
            : e.value,
    };

/// null — the profile will start exactly on core [wanted]; otherwise the reason.
String? pickCoreError(CoreResolution r, CoreKind wanted) {
  if (r.backend?.kind == wanted && r.pinned) return null;
  final reason = r.verdicts.where((v) => v.kind == wanted).firstOrNull?.reason;
  return reason ?? 'resolved to ${r.backend?.kind.displayName ?? 'none'}';
}
