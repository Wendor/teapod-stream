import 'dart:convert';
import 'vpn_config.dart';
import '../services/config_storage_service.dart' show Subscription;

class ConnectionsBundle {
  static const int currentVersion = 1;

  final int version;
  final DateTime exportedAt;
  final String? label;
  final List<VpnConfig> configs;
  final List<Subscription> subscriptions;
  // Populated when deserializing compact format (rawUri strings instead of full VpnConfig objects)
  final List<String> rawUris;
  // Populated when deserializing compact format (subscription URLs instead of full Subscription objects)
  final List<String> subscriptionUrls;

  const ConnectionsBundle({
    this.version = currentVersion,
    required this.exportedAt,
    this.label,
    this.configs = const [],
    this.subscriptions = const [],
    this.rawUris = const [],
    this.subscriptionUrls = const [],
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'exportedAt': exportedAt.toIso8601String(),
    if (label != null) 'label': label,
    'configs': configs.map((c) => c.toJson()).toList(),
    'subscriptions': subscriptions.map((s) => s.toJson()).toList(),
  };

  Map<String, dynamic> toCompactJson() => {
    'version': version,
    'exportedAt': exportedAt.toIso8601String(),
    if (label != null) 'label': label,
    'configs': configs.where((c) => c.rawUri != null).map((c) => c.rawUri!).toList(),
    'subscriptions': subscriptions.map((s) => s.url).toList(),
  };

  factory ConnectionsBundle.fromJson(Map<String, dynamic> json) {
    final rawUris = <String>[];
    final fullConfigs = <VpnConfig>[];
    for (final e in (json['configs'] as List<dynamic>? ?? [])) {
      if (e is String) {
        rawUris.add(e);
      } else if (e is Map<String, dynamic>) {
        fullConfigs.add(VpnConfig.fromJson(e));
      }
    }

    final subUrls = <String>[];
    final fullSubs = <Subscription>[];
    for (final e in (json['subscriptions'] as List<dynamic>? ?? [])) {
      if (e is String) {
        subUrls.add(e);
      } else if (e is Map<String, dynamic>) {
        fullSubs.add(Subscription.fromJson(e));
      }
    }

    return ConnectionsBundle(
      version: json['version'] as int? ?? 1,
      exportedAt: DateTime.parse(json['exportedAt'] as String),
      label: json['label'] as String?,
      configs: fullConfigs,
      subscriptions: fullSubs,
      rawUris: rawUris,
      subscriptionUrls: subUrls,
    );
  }

  bool get isCompact => rawUris.isNotEmpty || subscriptionUrls.isNotEmpty;

  String toBase64() {
    final bytes = utf8.encode(jsonEncode(toJson()));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String toCompactBase64() {
    final bytes = utf8.encode(jsonEncode(toCompactJson()));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static ConnectionsBundle fromBase64(String b64) {
    final padded = b64.padRight((b64.length + 3) ~/ 4 * 4, '=');
    final json = utf8.decode(base64Url.decode(padded));
    return ConnectionsBundle.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  String toDeeplink() => 'teapod://import/connections?data=${toBase64()}';
  String toCompactDeeplink() => 'teapod://import/connections?data=${toCompactBase64()}';
}
