import 'dart:convert';
import 'profile.dart';
import 'vpn_config.dart';
import '../services/config_storage_service.dart' show Subscription;

class ProfileBundle {
  static const int currentVersion = 1;

  final int version;
  final DateTime exportedAt;
  final Profile profile;
  final List<VpnConfig>? configs;
  final List<Subscription>? subscriptions;

  const ProfileBundle({
    this.version = currentVersion,
    required this.exportedAt,
    required this.profile,
    this.configs,
    this.subscriptions,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'exportedAt': exportedAt.toIso8601String(),
        'profile': profile.toJson(),
        if (configs != null) 'configs': configs!.map((c) => c.toJson()).toList(),
        if (subscriptions != null)
          'subscriptions': subscriptions!.map((s) => s.toJson()).toList(),
      };

  factory ProfileBundle.fromJson(Map<String, dynamic> json) => ProfileBundle(
        version: json['version'] as int? ?? 1,
        exportedAt: DateTime.parse(json['exportedAt'] as String),
        profile: Profile.fromJson(json['profile'] as Map<String, dynamic>),
        configs: (json['configs'] as List<dynamic>?)
            ?.map((e) => VpnConfig.fromJson(e as Map<String, dynamic>))
            .toList(),
        subscriptions: (json['subscriptions'] as List<dynamic>?)
            ?.map((e) => Subscription.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  String toBase64() {
    final bytes = utf8.encode(jsonEncode(toJson()));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static ProfileBundle fromBase64(String b64) {
    final padded = b64.padRight((b64.length + 3) ~/ 4 * 4, '=');
    final json = utf8.decode(base64Url.decode(padded));
    return ProfileBundle.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  String toDeeplink() => 'teapod://import?data=${toBase64()}';

  bool get hasConnections =>
      (configs?.isNotEmpty ?? false) || (subscriptions?.isNotEmpty ?? false);
}
