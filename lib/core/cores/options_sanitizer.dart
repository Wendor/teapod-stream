import '../interfaces/vpn_engine.dart';

/// Накапливает замены опций, которые ядро не применит, и предупреждения о них.
final class OptionsSanitizer {
  OptionsSanitizer(this._options);

  VpnEngineOptions _options;
  final List<String> _warnings = [];

  /// [when] — заменить опции через [fix] и записать [warning].
  void drop({required bool when, required String warning, required VpnEngineOptions Function(VpnEngineOptions) fix}) {
    if (!when) return;
    _options = fix(_options);
    _warnings.add(warning);
  }

  /// [when] — только предупреждение: ядро проигнорирует настройку само.
  void warn({required bool when, required String warning}) {
    if (when) _warnings.add(warning);
  }

  ({VpnEngineOptions options, List<String> warnings}) get result =>
      (options: _options, warnings: List.unmodifiable(_warnings));
}
