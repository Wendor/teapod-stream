import '../models/app_message.dart';
import '../interfaces/vpn_engine.dart';

/// Accumulates replacements of options the core won't apply, and warnings about them.
final class OptionsSanitizer {
  OptionsSanitizer(this._options);

  VpnEngineOptions _options;
  final List<AppMessage> _warnings = [];

  /// [when] — replace options via [fix] and record [warning].
  void drop({
    required bool when,
    required AppMessage warning,
    required VpnEngineOptions Function(VpnEngineOptions) fix,
  }) {
    if (!when) return;
    _options = fix(_options);
    _warnings.add(warning);
  }

  /// [when] — a warning only: the core will ignore the setting itself.
  void warn({required bool when, required AppMessage warning}) {
    if (when) _warnings.add(warning);
  }

  ({VpnEngineOptions options, List<AppMessage> warnings}) get result =>
      (options: _options, warnings: List.unmodifiable(_warnings));
}
