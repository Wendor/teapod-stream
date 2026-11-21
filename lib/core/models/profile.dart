import '../models/app_settings.dart';
import 'config_selection.dart';

class Profile {
  final String id;
  final String name;
  final bool isDefault;
  final bool readonly;
  final AppSettings settings;
  final DateTime createdAt;
  final String? sourceUrl;
  final DateTime? lastFetchedAt;

  /// The server selected under this profile; null — not remembered yet (the current one stays).
  final ConfigSelection? selection;

  const Profile({
    required this.id,
    required this.name,
    this.isDefault = false,
    this.readonly = false,
    required this.settings,
    required this.createdAt,
    this.sourceUrl,
    this.lastFetchedAt,
    this.selection,
  });

  Profile copyWith({
    String? name,
    bool? readonly,
    AppSettings? settings,
    String? sourceUrl,
    DateTime? lastFetchedAt,
    ConfigSelection? selection,
    bool clearSelection = false,
  }) => Profile(
    id: id,
    name: name ?? this.name,
    isDefault: isDefault,
    readonly: readonly ?? this.readonly,
    settings: settings ?? this.settings,
    createdAt: createdAt,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
    selection: clearSelection ? null : (selection ?? this.selection),
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
    if (selection != null) 'selection': selection!.toJson(),
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
    selection: json['selection'] is Map<String, dynamic>
        ? ConfigSelection.fromJson(json['selection'] as Map<String, dynamic>)
        : null,
  );

  bool get isFromUrl => sourceUrl != null;
}
