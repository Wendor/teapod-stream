import '../models/core_kind.dart';
import '../models/vpn_config.dart';
import '../services/settings_service.dart';
import 'core_backend.dart';
import 'engine_options.dart';

/// Ядро в порядке проверки: [reason] == null — ядро может запустить профиль.
typedef CoreVerdict = ({CoreKind kind, String? reason});

/// Каким ядром запустится профиль и почему не другими.
class CoreResolution {
  /// null — профиль не запускает ни одно ядро.
  final CoreBackend? backend;

  /// Все ядра в порядке проверки: закреплённое, затем по приоритету.
  final List<CoreVerdict> verdicts;

  /// Ядро закреплено за профилем.
  final bool pinned;

  const CoreResolution(this.backend, this.verdicts, {this.pinned = false});

  /// Почему профиль не запустится; null — запустится. Причина от самого
  /// ядра важнее «выключено»/«не загружается».
  String? get reason {
    if (backend != null) return null;
    final reasons = verdicts.map((v) => v.reason).nonNulls;
    return reasons.where((r) => r != CoreResolver.disabledReason && r != CoreResolver.unavailableReason).firstOrNull ??
        reasons.firstOrNull ??
        'Нет доступных ядер.';
  }
}

/// Выбор ядра для профиля: первое по приоритету, которое может его запустить.
/// Предупреждения ядра (проигнорированные настройки) на выбор не влияют.
class CoreResolver {
  final AppSettings settings;

  /// Ядра, нативные библиотеки которых загружаются на устройстве.
  final Set<CoreKind> available;
  final CoreBackend Function(CoreKind) backendFor;

  const CoreResolver(this.settings, this.available, this.backendFor);

  static const unavailableReason = 'Не загружается на этом устройстве.';
  static const disabledReason = 'Выключено в настройках.';

  /// Включённые и доступные ядра по приоритету.
  List<CoreKind> get usable => [
        for (final k in settings.coreOrder)
          if (available.contains(k) && !settings.disabledCores.contains(k)) k,
      ];

  /// Ядро, которым запускается большинство профилей.
  CoreKind? get primary => usable.firstOrNull;

  CoreResolution resolve(VpnConfig config) {
    final pin = config.core;
    final order = [?pin, ...settings.coreOrder.where((k) => k != pin)];
    final verdicts = [for (final k in order) (kind: k, reason: _check(k, config))];
    final chosen = verdicts.where((v) => v.reason == null).firstOrNull;
    return CoreResolution(
      chosen == null ? null : backendFor(chosen.kind),
      verdicts,
      pinned: pin != null && chosen?.kind == pin,
    );
  }

  String? _check(CoreKind kind, VpnConfig config) {
    if (!available.contains(kind)) return unavailableReason;
    if (settings.disabledCores.contains(kind)) return disabledReason;
    final backend = backendFor(kind);
    return backend.checkConfig(config) ??
        backend.checkOptions(config, buildEngineOptions(settings, config, backend)).blocking;
  }
}
