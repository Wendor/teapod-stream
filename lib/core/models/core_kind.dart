/// VPN-ядро, выбираемое в настройках.
enum CoreKind {
  xrayGo('go', 'Xray (Go)', 'GO', 'xray-go'),
  xrayRust('rust', 'Xray (Rust)', 'RUST', 'xray-rust'),
  singBox('box', 'sing-box', 'SING-BOX', 'sing-box');

  const CoreKind(this.nativeId, this.displayName, this.shortLabel, this.versionKey);

  /// Идентификатор ядра в native (`engine` в MethodChannel).
  final String nativeId;
  final String displayName;

  /// Подпись в переключателе ядра.
  final String shortLabel;

  /// Ключ версии ядра в `getBinaryVersions`.
  final String versionKey;

  static CoreKind fromName(String? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => CoreKind.xrayGo);
}
