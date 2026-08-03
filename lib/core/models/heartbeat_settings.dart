/// Чем проверяется живость туннеля.
enum HeartbeatProbe {
  /// Локальный сокет → SOCKS5 → xray → HTTP-запрос к [HeartbeatSettings.url].
  socks,

  /// `Teapodcore.measureXrayDelay()` — запрос внутри ядра, без локального сокета;
  /// сразу возвращает задержку в мс.
  xrayDelay,

  /// Без активных проб: только метрики tun2socks (последний rx, число соединений).
  /// Экономит батарею, но обрыв виден лишь при попытке реального трафика.
  passive,
}

/// Что делать, когда проверки перестали проходить.
enum HeartbeatFailAction {
  /// Переподключиться к тому же серверу (историческое поведение).
  reconnect,

  /// Перебрать кандидатов, замерить задержку и уйти на лучший живой.
  switchConfig,
}

/// Откуда брать кандидатов при [HeartbeatFailAction.switchConfig].
enum SwitchSource {
  /// Конфиги подписки, которой принадлежит активный сервер.
  subscription,

  /// Закреплённые (pinned) конфиги.
  pinned,

  /// Все сохранённые конфиги.
  all,
}

/// Куда стучится проба. Все пресеты — плоский HTTP, чтобы один и тот же URL
/// годился и для SOCKS-пробы, и для замера внутри ядра.
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

  /// Сколько провалов подряд до срабатывания [failAction], 1–10.
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

  /// Итоговый URL пробы; при пустом кастомном значении — пресет Cloudflare.
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
  }) =>
      HeartbeatSettings(
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
        probe: HeartbeatProbe.values.firstWhere(
          (e) => e.name == json['probe'],
          orElse: () => HeartbeatProbe.socks,
        ),
        failureThreshold: json['failureThreshold'] as int? ?? 3,
        failAction: HeartbeatFailAction.values.firstWhere(
          (e) => e.name == json['failAction'],
          orElse: () => HeartbeatFailAction.reconnect,
        ),
        switchSource: SwitchSource.values.firstWhere(
          (e) => e.name == json['switchSource'],
          orElse: () => SwitchSource.subscription,
        ),
        target: HeartbeatTarget.values.firstWhere(
          (e) => e.name == json['target'],
          orElse: () => HeartbeatTarget.cloudflare,
        ),
        customUrl: json['customUrl'] as String? ?? '',
      );
}
