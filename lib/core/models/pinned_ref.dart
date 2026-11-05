import 'vpn_config.dart';

/// Закреплённое подключение. Идентифицируется (подписка, имя, endpoint),
/// а не id конфига: при обновлении подписки конфиги пересоздаются.
/// Имена в подписках не уникальны («VLESS Server» ×N), поэтому endpoint
/// уточняет выбор; если он сменился — пин держится за одноимённый конфиг.
class PinnedRef {
  /// null — standalone-конфиг (группа [local]).
  final String? subscriptionId;
  final String name;

  /// `address:port`; null — пин старого формата (только имя).
  final String? endpoint;

  const PinnedRef({required this.subscriptionId, required this.name, this.endpoint});

  PinnedRef.of(VpnConfig c)
      : subscriptionId = c.subscriptionId,
        name = c.name,
        endpoint = '${c.address}:${c.port}';

  bool _sameGroupAndName(VpnConfig c) =>
      c.subscriptionId == subscriptionId && c.name == name;

  /// Точное совпадение, иначе первый одноимённый.
  VpnConfig? resolve(Iterable<VpnConfig> configs) {
    final named = configs.where(_sameGroupAndName);
    return named.where((c) => '${c.address}:${c.port}' == endpoint).firstOrNull ??
        named.firstOrNull;
  }

  Map<String, dynamic> toJson() => {
        'subscriptionId': subscriptionId,
        'name': name,
        if (endpoint != null) 'endpoint': endpoint,
      };

  factory PinnedRef.fromJson(Map<String, dynamic> json) => PinnedRef(
        subscriptionId: json['subscriptionId'] as String?,
        name: json['name'] as String? ?? '',
        endpoint: json['endpoint'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is PinnedRef &&
      other.subscriptionId == subscriptionId &&
      other.name == name &&
      other.endpoint == endpoint;

  @override
  int get hashCode => Object.hash(subscriptionId, name, endpoint);
}
