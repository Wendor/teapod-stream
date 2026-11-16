import '../models/core_kind.dart';
import '../models/vpn_config.dart';
import '../services/settings_service.dart';
import 'core_backend.dart';
import 'engine_options.dart';
import '../../l10n/l10n.dart';

/// A core in check order: [reason] == null — the core can run the profile.
typedef CoreVerdict = ({CoreKind kind, String? reason});

/// Which core runs the profile and why not the others.
class CoreResolution {
  /// null — no core runs the profile.
  final CoreBackend? backend;

  /// All cores in check order: the pinned one, then by priority.
  final List<CoreVerdict> verdicts;

  /// The core is pinned to the profile.
  final bool pinned;

  const CoreResolution(this.backend, this.verdicts, {this.pinned = false});

  /// Why the profile won't start; null — it will. A reason from the core
  /// itself beats "disabled"/"doesn't load".
  String? get reason {
    if (backend != null) return null;
    final reasons = verdicts.map((v) => v.reason).nonNulls;
    return reasons.where((r) => r != CoreResolver.disabledReason && r != CoreResolver.unavailableReason).firstOrNull ??
        reasons.firstOrNull ??
        L10n.current.coreNoneAvailable;
  }
}

/// Core choice for a profile: the first by priority that can run it.
/// Core warnings (ignored settings) don't affect the choice.
class CoreResolver {
  final AppSettings settings;

  /// Cores whose native libraries load on the device.
  final Set<CoreKind> available;
  final CoreBackend Function(CoreKind) backendFor;

  CoreResolver(this.settings, this.available, this.backendFor);

  /// The resolver is recreated on settings/core changes and VpnConfig is immutable — the result
  /// is cached per instance: config list rows call resolve on every rebuild.
  final _cache = Expando<CoreResolution>();

  static String get unavailableReason => L10n.current.coreUnavailable;
  static String get disabledReason => L10n.current.coreDisabled;

  /// Enabled and available cores by priority.
  List<CoreKind> get usable => [
    for (final k in settings.coreOrder)
      if (available.contains(k) && !settings.disabledCores.contains(k)) k,
  ];

  /// The core that runs most profiles.
  CoreKind? get primary => usable.firstOrNull;

  CoreResolution resolve(VpnConfig config) => _cache[config] ??= _resolve(config);

  CoreResolution _resolve(VpnConfig config) {
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
