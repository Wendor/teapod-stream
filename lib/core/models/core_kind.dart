/// VPN core.
enum CoreKind {
  xrayGo('go', 'xray-core', 'XRAY-CORE', 'xray-go'),
  xrayRust('rust', 'xray-rust', 'XRAY-RUST', 'xray-rust'),
  singBox('box', 'sing-box', 'SING-BOX', 'sing-box');

  const CoreKind(this.nativeId, this.displayName, this.shortLabel, this.versionKey);

  /// Core identifier in native (`engine` in the MethodChannel).
  final String nativeId;
  final String displayName;

  /// Short label (core order in settings).
  final String shortLabel;

  /// Core version key in `getBinaryVersions`.
  final String versionKey;

  /// Default priority: the experimental Rust is last.
  static const defaultOrder = [xrayGo, singBox, xrayRust];

  static CoreKind? tryName(String? name) {
    for (final k in values) {
      if (k.name == name) return k;
    }
    return null;
  }

  /// Order from saved names: unknown ones are dropped, missing ones
  /// are appended in default order. [first] (the core from versions before
  /// priorities) goes first if there's no order yet.
  static List<CoreKind> parseOrder(Iterable<String>? names, {String? first}) {
    final order = <CoreKind>{if (names == null) ?tryName(first), ...?names?.map(tryName).nonNulls, ...defaultOrder};
    return List.unmodifiable(order);
  }
}
