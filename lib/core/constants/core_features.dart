import '../models/heartbeat_settings.dart';

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
  coreDelayProbe,
  passiveHeartbeat,
  tetheringControl,
  outboundDelayProbe,
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
    CoreFeature.icmpToggle,
    CoreFeature.customMtu,
    CoreFeature.mux,
    CoreFeature.upstreamUpdates,
    CoreFeature.observatory,
    CoreFeature.rawConfig,
  };
  bool supports(CoreFeature feature) =>
      !isRust || !rustDisabled.contains(feature);

  /// Vision outbounds reject UDP/443. Go blocks QUIC for every Vision [flow];
  /// its tun2socks answers UDP/443 with ICMP "port unreachable". The Rust core
  /// sends that ICMP itself for plain `xtls-rprx-vision` (`blocks_udp443`), and
  /// a blackhole rule would replace it with a silent drop, so Rust adds the rule
  /// automatically only for `xtls-rprx-vision-udp443`, as Go blocks it.
  /// Otherwise only the user's toggle blocks QUIC.
  bool effectiveQuicBlock({required bool requested, required String? flow}) {
    final vision = flow ?? '';
    return requested ||
        (isRust
            ? vision == 'xtls-rprx-vision-udp443'
            : vision.contains('vision'));
  }

  /// The feature a heartbeat probe relies on; SOCKS works in both cores.
  static CoreFeature? heartbeatProbeFeature(HeartbeatProbe probe) =>
      switch (probe) {
        HeartbeatProbe.socks => null,
        HeartbeatProbe.xrayDelay => CoreFeature.coreDelayProbe,
        HeartbeatProbe.passive => CoreFeature.passiveHeartbeat,
      };

  bool supportsHeartbeatProbe(HeartbeatProbe probe) {
    final feature = heartbeatProbeFeature(probe);
    return feature == null || supports(feature);
  }

  /// Probes offered by the settings picker, in the upstream order.
  List<HeartbeatProbe> get heartbeatProbes =>
      HeartbeatProbe.values.where(supportsHeartbeatProbe).toList();

  /// The probe the native service receives. An unsupported stored probe is
  /// replaced by SOCKS; the settings screen explains it and offers a reset.
  HeartbeatProbe effectiveHeartbeatProbe(HeartbeatProbe requested) =>
      supportsHeartbeatProbe(requested) ? requested : HeartbeatProbe.socks;

  /// Available features have no unavailability reason, in either build.
  String? unavailableReason(CoreFeature feature) {
    if (supports(feature)) return null;
    return switch (feature) {
      CoreFeature.geoip ||
      CoreFeature.geosite ||
      CoreFeature.appRouting ||
      CoreFeature.directDns ||
      CoreFeature.adBlocking ||
      CoreFeature.passiveHeartbeat ||
      CoreFeature.udpToggle ||
      CoreFeature.quicBlocking ||
      CoreFeature.fragmentation ||
      CoreFeature.noise ||
      CoreFeature.coreDelayProbe ||
      CoreFeature.tetheringControl ||
      CoreFeature.outboundDelayProbe => null,
      CoreFeature.socksAuthentication =>
        'Rust: локальный SOCKS работает без логина и пароля — любое приложение на устройстве, в том числе исключённое, может выйти через него в VPN и узнать IP сервера.',
      CoreFeature.proxyOnly => 'Rust: доступен режим VPN через TUN.',
      CoreFeature.icmpToggle =>
        'Rust: ICMP обрабатывается ядром локально, а при проверке владельца потоков («ТОЛЬКО» или исключения без раздачи) отбрасывается; настройка не применяется.',
      CoreFeature.customMtu => 'Rust: используется MTU 1500.',
      CoreFeature.mux =>
        'Mux пока недоступен в Rust-сборке: ядро не мультиплексирует VLESS, а для xHTTP допускает только UDP-ветку.',
      CoreFeature.upstreamUpdates =>
        'Rust-сборка обновляется вручную из форка.',
      CoreFeature.observatory =>
        'Rust: управляемые JSON-конфиги и Observatory пока недоступны.',
      CoreFeature.rawConfig =>
        'Rust: поддерживаются VLESS, Trojan, VMess AEAD, Shadowsocks 2022 и Hysteria2 из ссылок; полный JSON пока недоступен.',
    };
  }
}
