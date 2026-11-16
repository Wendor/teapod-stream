import '../interfaces/vpn_engine.dart';

/// Accumulates replacements of options the core won't apply, and warnings about them.
final class OptionsSanitizer {
  OptionsSanitizer(this._options);

  VpnEngineOptions _options;
  final List<String> _warnings = [];

  /// [when] — replace options via [fix] and record [warning].
  void drop({required bool when, required String warning, required VpnEngineOptions Function(VpnEngineOptions) fix}) {
    if (!when) return;
    _options = fix(_options);
    _warnings.add(warning);
  }

  /// [when] — a warning only: the core will ignore the setting itself.
  void warn({required bool when, required String warning}) {
    if (when) _warnings.add(warning);
  }

  ({VpnEngineOptions options, List<String> warnings}) get result =>
      (options: _options, warnings: List.unmodifiable(_warnings));
}
