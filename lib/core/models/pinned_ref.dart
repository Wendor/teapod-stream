import 'vpn_config.dart';

/// A pinned connection. Identified by (subscription, name, endpoint),
/// not the config id: configs are recreated on subscription refresh.
/// Names in subscriptions aren't unique ("VLESS Server" ×N), so the endpoint
/// refines the choice; if it changed, the pin sticks to the config with the same name.
class PinnedRef {
  /// null — a standalone config (group [local]).
  final String? subscriptionId;
  final String name;

  /// `address:port`; null — an old-format pin (name only).
  final String? endpoint;

  const PinnedRef({required this.subscriptionId, required this.name, this.endpoint});

  PinnedRef.of(VpnConfig c) : subscriptionId = c.subscriptionId, name = c.name, endpoint = c.endpoint;

  bool _sameGroupAndName(VpnConfig c) => c.subscriptionId == subscriptionId && c.name == name;

  /// Exact match, otherwise the first one with the same name.
  VpnConfig? resolve(Iterable<VpnConfig> configs) {
    final named = configs.where(_sameGroupAndName);
    return named.where((c) => c.endpoint == endpoint).firstOrNull ?? named.firstOrNull;
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
      other is PinnedRef && other.subscriptionId == subscriptionId && other.name == name && other.endpoint == endpoint;

  @override
  int get hashCode => Object.hash(subscriptionId, name, endpoint);
}
