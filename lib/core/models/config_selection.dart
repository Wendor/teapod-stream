import 'pinned_ref.dart';

/// The selection on the configs screen in a form that outlives a subscription refresh (the parser
/// issues new config ids every time): the chosen config as a [PinnedRef] and the subscription in
/// auto-select mode. Stored in a profile so switching profiles switches the server too.
class ConfigSelection {
  final PinnedRef? config;
  final String? subscriptionId;

  const ConfigSelection({this.config, this.subscriptionId});

  Map<String, dynamic> toJson() => {
    if (config != null) 'config': config!.toJson(),
    if (subscriptionId != null) 'subscriptionId': subscriptionId,
  };

  factory ConfigSelection.fromJson(Map<String, dynamic> json) => ConfigSelection(
    config: json['config'] is Map<String, dynamic> ? PinnedRef.fromJson(json['config'] as Map<String, dynamic>) : null,
    subscriptionId: json['subscriptionId'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is ConfigSelection && other.config == config && other.subscriptionId == subscriptionId;

  @override
  int get hashCode => Object.hash(config, subscriptionId);
}
