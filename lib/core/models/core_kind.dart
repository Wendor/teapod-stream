/// VPN-ядро.
enum CoreKind {
  xrayGo('go', 'Xray (Go)', 'GO', 'xray-go'),
  xrayRust('rust', 'Xray (Rust)', 'RUST', 'xray-rust'),
  singBox('box', 'sing-box', 'SING-BOX', 'sing-box');

  const CoreKind(this.nativeId, this.displayName, this.shortLabel, this.versionKey);

  /// Идентификатор ядра в native (`engine` в MethodChannel).
  final String nativeId;
  final String displayName;

  /// Короткая подпись (порядок ядер в настройках).
  final String shortLabel;

  /// Ключ версии ядра в `getBinaryVersions`.
  final String versionKey;

  /// Приоритет по умолчанию: Rust экспериментальный — последний.
  static const defaultOrder = [xrayGo, singBox, xrayRust];

  static CoreKind? tryName(String? name) {
    for (final k in values) {
      if (k.name == name) return k;
    }
    return null;
  }

  /// Порядок из сохранённых имён: неизвестные отбрасываются, недостающие
  /// дописываются в порядке по умолчанию. [first] (ядро из версий до
  /// приоритетов) ставится первым, если порядка ещё нет.
  static List<CoreKind> parseOrder(Iterable<String>? names, {String? first}) {
    final order = <CoreKind>{
      if (names == null) ?tryName(first),
      ...?names?.map(tryName).nonNulls,
      ...defaultOrder,
    };
    return List.unmodifiable(order);
  }
}
