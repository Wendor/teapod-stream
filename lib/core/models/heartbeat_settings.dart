/// What checks that the tunnel is alive.
enum HeartbeatProbe {
  /// Local socket → SOCKS5 → xray → HTTP request to [HeartbeatSettings.url].
  socks,

  /// `Teapodcore.measureXrayDelay()` — a request inside the core, without a local socket;
  /// returns the latency in ms directly.
  xrayDelay,

  /// No active probes: only tun2socks metrics (last rx, connection count).
  /// Saves battery, but a drop is noticed only when real traffic is attempted.
  passive,
}

/// What to do when checks stop passing.
enum HeartbeatFailAction {
  /// Reconnect to the same server (historical behavior).
  reconnect,

  /// Go through candidates, measure latency and move to the best live one.
  switchConfig,
}

/// Where to take candidates from for [HeartbeatFailAction.switchConfig].
enum SwitchSource {
  /// Configs of the subscription the active server belongs to.
  subscription,

  /// Pinned configs.
  pinned,

  /// All saved configs.
  all,
}

/// Where the probe goes. All presets are plain HTTP so the same URL
/// works both for the SOCKS probe and for the in-core measurement.
enum HeartbeatTarget {
  cloudflare,
  google,
  apple,
  custom;

  String get url => switch (this) {
    cloudflare => 'http://cp.cloudflare.com/generate_204',
    google => 'http://connectivitycheck.gstatic.com/generate_204',
    apple => 'http://captive.apple.com/generate_204',
    custom => '',
  };
}

class HeartbeatSettings {
  final HeartbeatProbe probe;

  /// How many consecutive failures before [failAction] fires, 1–10.
  final int failureThreshold;

  final HeartbeatFailAction failAction;
  final SwitchSource switchSource;
  final HeartbeatTarget target;
  final String customUrl;

  const HeartbeatSettings({
    this.probe = HeartbeatProbe.socks,
    this.failureThreshold = 3,
    this.failAction = HeartbeatFailAction.reconnect,
    this.switchSource = SwitchSource.subscription,
    this.target = HeartbeatTarget.cloudflare,
    this.customUrl = '',
  });

  /// The final probe URL; with an empty custom value — the Cloudflare preset.
  String get url {
    if (target != HeartbeatTarget.custom) return target.url;
    final u = customUrl.trim();
    return u.isEmpty ? HeartbeatTarget.cloudflare.url : u;
  }

  HeartbeatSettings copyWith({
    HeartbeatProbe? probe,
    int? failureThreshold,
    HeartbeatFailAction? failAction,
    SwitchSource? switchSource,
    HeartbeatTarget? target,
    String? customUrl,
  }) => HeartbeatSettings(
    probe: probe ?? this.probe,
    failureThreshold: failureThreshold ?? this.failureThreshold,
    failAction: failAction ?? this.failAction,
    switchSource: switchSource ?? this.switchSource,
    target: target ?? this.target,
    customUrl: customUrl ?? this.customUrl,
  );

  Map<String, dynamic> toJson() => {
    'probe': probe.name,
    'failureThreshold': failureThreshold,
    'failAction': failAction.name,
    'switchSource': switchSource.name,
    'target': target.name,
    'customUrl': customUrl,
  };

  static HeartbeatSettings fromJson(Map<String, dynamic> json) => HeartbeatSettings(
    probe: HeartbeatProbe.values.firstWhere((e) => e.name == json['probe'], orElse: () => HeartbeatProbe.socks),
    failureThreshold: json['failureThreshold'] as int? ?? 3,
    // Before 1.6.4: action = reconnect | urltest, source = subscription | pinned | all.
    failAction: HeartbeatFailAction.values.firstWhere(
      (e) => e.name == json['failAction'],
      orElse: () => json['action'] == 'urltest' ? HeartbeatFailAction.switchConfig : HeartbeatFailAction.reconnect,
    ),
    switchSource: SwitchSource.values.firstWhere(
      (e) => e.name == (json['switchSource'] ?? json['source']),
      orElse: () => SwitchSource.subscription,
    ),
    target: HeartbeatTarget.values.firstWhere(
      (e) => e.name == json['target'],
      orElse: () => HeartbeatTarget.cloudflare,
    ),
    customUrl: json['customUrl'] as String? ?? '',
  );
}
