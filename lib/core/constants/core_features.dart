/// The same TEAPOD_CORE build flag selects native sources in Android Gradle.
enum CoreFeature {
  socksAuthentication,
  proxyOnly,
  udpToggle,
  icmpToggle,
  quicBlocking,
  customMtu,
  fragmentation,
  noise,
  mux,
  directDns,
  adBlocking,
  upstreamUpdates,
  observatory,
  rawConfig,
  geoip,
  geosite,
  appRouting,
}

class CoreFeatures {
  final bool isRust;
  const CoreFeatures({required this.isRust});

  static const rustBuild =
      String.fromEnvironment('TEAPOD_CORE', defaultValue: 'go') == 'rust';
  static const current = CoreFeatures(isRust: rustBuild);
  static const go = CoreFeatures(isRust: false);
  static const rust = CoreFeatures(isRust: true);

  // Flags represent integrated, tested functionality; enabling an unsupported
  // protocol in the UI alone must never bypass the config builder's checks.
  static const rustDisabled = {
    CoreFeature.socksAuthentication,
    CoreFeature.proxyOnly,
    CoreFeature.udpToggle,
    CoreFeature.icmpToggle,
    CoreFeature.quicBlocking,
    CoreFeature.customMtu,
    CoreFeature.fragmentation,
    CoreFeature.noise,
    CoreFeature.mux,
    CoreFeature.directDns,
    CoreFeature.adBlocking,
    CoreFeature.upstreamUpdates,
    CoreFeature.observatory,
    CoreFeature.rawConfig,
  };
  bool supports(CoreFeature feature) =>
      !isRust || !rustDisabled.contains(feature);

  /// Available features have no unavailability reason, in either build.
  String? unavailableReason(CoreFeature feature) {
    if (supports(feature)) return null;
    return switch (feature) {
      CoreFeature.geoip ||
      CoreFeature.geosite ||
      CoreFeature.appRouting => null,
      CoreFeature.socksAuthentication =>
        'Rust: локальный SOCKS работает без логина и пароля.',
      CoreFeature.proxyOnly => 'Rust: доступен режим VPN через TUN.',
      CoreFeature.udpToggle => 'Rust: UDP включён постоянно.',
      CoreFeature.icmpToggle =>
        'Rust: ICMP обрабатывается ядром локально; настройка не применяется.',
      CoreFeature.quicBlocking =>
        'Блокировка QUIC пока недоступна в Rust-сборке.',
      CoreFeature.customMtu => 'Rust: используется MTU 1500.',
      CoreFeature.fragmentation =>
        'Фрагментация пока недоступна в Rust-сборке.',
      CoreFeature.noise => 'Шумы пока недоступны в Rust-сборке.',
      CoreFeature.mux => 'Mux пока недоступен в Rust-сборке.',
      CoreFeature.directDns => 'Rust: DNS должен идти через VPN.',
      CoreFeature.adBlocking =>
        'Блокировка рекламы пока недоступна в Rust-сборке.',
      CoreFeature.upstreamUpdates =>
        'Rust-сборка обновляется вручную из форка.',
      CoreFeature.observatory =>
        'Rust: управляемые JSON-конфиги и Observatory пока недоступны.',
      CoreFeature.rawConfig =>
        'Rust: поддерживается VLESS + xHTTP + Reality; полный JSON пока недоступен.',
    };
  }
}
