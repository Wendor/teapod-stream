/// VPN-ядро, выбираемое в настройках.
enum CoreKind {
  xrayGo('go', 'Xray (Go)'),
  xrayRust('rust', 'Xray (Rust)');

  const CoreKind(this.nativeId, this.displayName);

  /// Идентификатор ядра в native (`engine` в MethodChannel).
  final String nativeId;
  final String displayName;

  static CoreKind fromName(String? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => CoreKind.xrayGo);
}
