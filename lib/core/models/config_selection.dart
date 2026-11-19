import 'pinned_ref.dart';
import 'vpn_config.dart';

/// The selection on the configs screen: the chosen config and the subscription in auto-select mode.
/// Stored in a profile so switching profiles switches the server too. The config is found by
/// [configId] while it exists, then by [config] — a subscription refresh issues new ids.
class ConfigSelection {
  final String? configId;
  final PinnedRef? config;
  final String? subscriptionId;

  const ConfigSelection({this.configId, this.config, this.subscriptionId});

  VpnConfig? resolve(Iterable<VpnConfig> configs) =>
      configs.where((c) => c.id == configId).firstOrNull ?? config?.resolve(configs);

  Map<String, dynamic> toJson() => {
    if (configId != null) 'configId': configId,
    if (config != null) 'config': config!.toJson(),
    if (subscriptionId != null) 'subscriptionId': subscriptionId,
  };

  factory ConfigSelection.fromJson(Map<String, dynamic> json) => ConfigSelection(
    configId: json['configId'] as String?,
    config: json['config'] is Map<String, dynamic> ? PinnedRef.fromJson(json['config'] as Map<String, dynamic>) : null,
    subscriptionId: json['subscriptionId'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is ConfigSelection &&
      other.configId == configId &&
      other.config == config &&
      other.subscriptionId == subscriptionId;

  @override
  int get hashCode => Object.hash(configId, config, subscriptionId);
}
