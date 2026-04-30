import '../services/settings_service.dart';

class Profile {
  final String id;
  final String name;
  final bool isDefault;
  final bool readonly;
  final AppSettings settings;
  final String? activeConfigId;
  final DateTime createdAt;

  const Profile({
    required this.id,
    required this.name,
    this.isDefault = false,
    this.readonly = false,
    required this.settings,
    this.activeConfigId,
    required this.createdAt,
  });

  Profile copyWith({
    String? name,
    bool? readonly,
    AppSettings? settings,
    String? activeConfigId,
    bool clearActiveConfig = false,
  }) =>
      Profile(
        id: id,
        name: name ?? this.name,
        isDefault: isDefault,
        readonly: readonly ?? this.readonly,
        settings: settings ?? this.settings,
        activeConfigId: clearActiveConfig ? null : (activeConfigId ?? this.activeConfigId),
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isDefault': isDefault,
        'readonly': readonly,
        'settings': settings.toJson(),
        'activeConfigId': activeConfigId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        name: json['name'] as String,
        isDefault: json['isDefault'] as bool? ?? false,
        readonly: json['readonly'] as bool? ?? false,
        settings: AppSettings.fromJson(
            json['settings'] as Map<String, dynamic>? ?? {}),
        activeConfigId: json['activeConfigId'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
