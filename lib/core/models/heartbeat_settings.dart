/// Что делать, когда нативный heartbeat исчерпал попытки достучаться через туннель.
enum HeartbeatAction {
  /// Переподключиться к тому же серверу (историческое поведение).
  reconnect,

  /// Перебрать кандидатов, замерить latency и переключиться на лучший живой.
  urltest,
}

/// Откуда брать кандидатов для urltest-переключения.
enum UrltestSource {
  /// Только конфиги подписки, которой принадлежит активный сервер.
  subscription,

  /// Только закреплённые (pinned) конфиги.
  pinned,

  /// Все сохранённые конфиги.
  all,
}

class HeartbeatSettings {
  final HeartbeatAction action;

  /// Сколько провалов подряд до срабатывания действия, 1–10.
  final int failureThreshold;

  final UrltestSource source;

  const HeartbeatSettings({
    this.action = HeartbeatAction.reconnect,
    this.failureThreshold = 3,
    this.source = UrltestSource.subscription,
  });

  HeartbeatSettings copyWith({
    HeartbeatAction? action,
    int? failureThreshold,
    UrltestSource? source,
  }) =>
      HeartbeatSettings(
        action: action ?? this.action,
        failureThreshold: failureThreshold ?? this.failureThreshold,
        source: source ?? this.source,
      );

  Map<String, dynamic> toJson() => {
        'action': action.name,
        'failureThreshold': failureThreshold,
        'source': source.name,
      };

  static HeartbeatSettings fromJson(Map<String, dynamic> json) => HeartbeatSettings(
        action: HeartbeatAction.values.firstWhere(
          (e) => e.name == json['action'],
          orElse: () => HeartbeatAction.reconnect,
        ),
        failureThreshold: json['failureThreshold'] as int? ?? 3,
        source: UrltestSource.values.firstWhere(
          (e) => e.name == json['source'],
          orElse: () => UrltestSource.subscription,
        ),
      );
}
