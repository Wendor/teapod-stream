import '../services/settings_service.dart';

class Profile {
  final String id;
  final String name;
  final bool isDefault;
  final bool readonly;
  final AppSettings settings;
  final DateTime createdAt;
  final String? sourceUrl;
  final DateTime? lastFetchedAt;

  const Profile({
    required this.id,
    required this.name,
    this.isDefault = false,
    this.readonly = false,
    required this.settings,
    required this.createdAt,
    this.sourceUrl,
    this.lastFetchedAt,
  });

  Profile copyWith({String? name, bool? readonly, AppSettings? settings, String? sourceUrl, DateTime? lastFetchedAt}) =>
      Profile(
        id: id,
        name: name ?? this.name,
        isDefault: isDefault,
        readonly: readonly ?? this.readonly,
        settings: settings ?? this.settings,
        createdAt: createdAt,
        sourceUrl: sourceUrl ?? this.sourceUrl,
        lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'isDefault': isDefault,
    'readonly': readonly,
    'settings': settings.toJson(),
    'createdAt': createdAt.toIso8601String(),
    if (sourceUrl != null) 'sourceUrl': sourceUrl,
    if (lastFetchedAt != null) 'lastFetchedAt': lastFetchedAt!.toIso8601String(),
  };

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    name: json['name'] as String,
    isDefault: json['isDefault'] as bool? ?? false,
    readonly: json['readonly'] as bool? ?? false,
    settings: AppSettings.fromJson(json['settings'] as Map<String, dynamic>? ?? {}),
    createdAt: DateTime.parse(json['createdAt'] as String),
    sourceUrl: json['sourceUrl'] as String?,
    lastFetchedAt: json['lastFetchedAt'] != null ? DateTime.parse(json['lastFetchedAt'] as String) : null,
  );

  bool get isFromUrl => sourceUrl != null;
}
