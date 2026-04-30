import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/profile.dart';
import '../core/models/profile_bundle.dart';
import '../core/services/profile_storage_service.dart';
import '../core/services/settings_service.dart';
import '../core/services/config_storage_service.dart' show ConfigStorageService;
import 'settings_provider.dart';
import 'config_provider.dart';

class ProfileState {
  final List<Profile> profiles;
  final String activeProfileId;

  const ProfileState({
    required this.profiles,
    required this.activeProfileId,
  });

  Profile? get activeProfile =>
      profiles.where((p) => p.id == activeProfileId).firstOrNull;

  bool get isReadonly => activeProfile?.readonly ?? false;

  ProfileState copyWith({List<Profile>? profiles, String? activeProfileId}) =>
      ProfileState(
        profiles: profiles ?? this.profiles,
        activeProfileId: activeProfileId ?? this.activeProfileId,
      );
}

class ProfileNotifier extends AsyncNotifier<ProfileState> {
  final _storage = ProfileStorageService();

  ProfileState? get _current =>
      state.maybeWhen(data: (d) => d, orElse: () => null);

  @override
  Future<ProfileState> build() async {
    var profiles = await _storage.loadProfiles();
    var activeId = await _storage.loadActiveProfileId();

    if (profiles.isEmpty) {
      final settings = await SettingsService().load();
      final configId = await ConfigStorageService().loadActiveConfigId();
      final defaultProfile = Profile(
        id: 'default',
        name: 'По умолчанию',
        isDefault: true,
        settings: settings,
        activeConfigId: configId,
        createdAt: DateTime.now(),
      );
      profiles = [defaultProfile];
      await _storage.saveProfiles(profiles);
      await _storage.saveActiveProfileId('default');
      activeId = 'default';
    }

    if (!profiles.any((p) => p.id == activeId)) {
      activeId = profiles.first.id;
      await _storage.saveActiveProfileId(activeId);
    }

    return ProfileState(profiles: profiles, activeProfileId: activeId);
  }

  Future<void> switchProfile(String id) async {
    final current = _current;
    if (current == null || current.activeProfileId == id) return;
    final profile = current.profiles.firstWhere((p) => p.id == id);

    await SettingsService().save(profile.settings);
    await ConfigStorageService().saveActiveConfigId(profile.activeConfigId);
    await _storage.saveActiveProfileId(id);

    state = AsyncData(current.copyWith(activeProfileId: id));
    ref.invalidate(settingsProvider);
    ref.invalidate(configProvider);
  }

  Future<void> createProfile(String name, {bool copyFromCurrent = true}) async {
    final current = _current;
    if (current == null) return;

    final settings = copyFromCurrent
        ? (ref.read(settingsProvider).maybeWhen(
            data: (d) => d, orElse: () => null) ?? const AppSettings())
        : const AppSettings();
    final activeConfigId = copyFromCurrent
        ? ref.read(configProvider).maybeWhen(
            data: (d) => d.activeConfigId, orElse: () => null)
        : null;

    final id = 'profile_${DateTime.now().millisecondsSinceEpoch}';
    final profile = Profile(
      id: id,
      name: name,
      settings: settings,
      activeConfigId: activeConfigId,
      createdAt: DateTime.now(),
    );

    final profiles = [...current.profiles, profile];
    await _storage.saveProfiles(profiles);
    state = AsyncData(current.copyWith(profiles: profiles));
  }

  Future<void> renameProfile(String id, String newName) async {
    final current = _current;
    if (current == null) return;
    final profiles = current.profiles
        .map((p) => p.id == id ? p.copyWith(name: newName) : p)
        .toList();
    await _storage.saveProfiles(profiles);
    state = AsyncData(current.copyWith(profiles: profiles));
  }

  Future<void> deleteProfile(String id) async {
    final current = _current;
    if (current == null) return;
    final target = current.profiles.firstWhere((p) => p.id == id);
    if (target.isDefault || current.activeProfileId == id) return;

    final profiles = current.profiles.where((p) => p.id != id).toList();
    await _storage.saveProfiles(profiles);
    state = AsyncData(current.copyWith(profiles: profiles));
  }

  Future<void> toggleReadonly(String id) async {
    final current = _current;
    if (current == null) return;
    final profiles = current.profiles
        .map((p) => p.id == id ? p.copyWith(readonly: !p.readonly) : p)
        .toList();
    await _storage.saveProfiles(profiles);
    state = AsyncData(current.copyWith(profiles: profiles));
  }

  Future<void> syncActiveSettings(AppSettings settings) async {
    final current = _current;
    if (current == null) return;
    final id = current.activeProfileId;
    await _storage.updateProfileSettings(id, settings);
    final profiles = current.profiles
        .map((p) => p.id == id ? p.copyWith(settings: settings) : p)
        .toList();
    state = AsyncData(current.copyWith(profiles: profiles));
  }

  ProfileBundle exportBundle(String profileId, {bool includeConnections = false}) {
    final current = _current!;
    final profile = current.profiles.firstWhere((p) => p.id == profileId);
    if (!includeConnections) {
      return ProfileBundle(exportedAt: DateTime.now(), profile: profile);
    }
    final configState = ref.read(configProvider)
        .maybeWhen(data: (d) => d, orElse: () => null);
    return ProfileBundle(
      exportedAt: DateTime.now(),
      profile: profile,
      configs: configState?.configs.toList(),
      subscriptions: configState?.subscriptions.toList(),
    );
  }

  Future<String?> importBundle(
    ProfileBundle bundle, {
    bool switchToProfile = true,
    bool makeReadonly = false,
  }) async {
    final current = _current;
    if (current == null) return null;

    final newId = 'profile_${DateTime.now().millisecondsSinceEpoch}';
    final profile = Profile(
      id: newId,
      name: bundle.profile.name,
      isDefault: false,
      readonly: makeReadonly,
      settings: bundle.profile.settings,
      activeConfigId: bundle.profile.activeConfigId,
      createdAt: DateTime.now(),
    );

    final profiles = [...current.profiles, profile];
    await _storage.saveProfiles(profiles);
    state = AsyncData(current.copyWith(profiles: profiles));

    if (switchToProfile) await switchProfile(newId);
    return newId;
  }

  static ProfileBundle? tryParseBundle(String input) {
    try {
      final trimmed = input.trim();
      if (trimmed.startsWith('teapod://import?data=')) {
        final data = Uri.parse(trimmed).queryParameters['data']!;
        return ProfileBundle.fromBase64(data);
      }
      return ProfileBundle.fromJson(
          jsonDecode(trimmed) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

final profileProvider =
    AsyncNotifierProvider<ProfileNotifier, ProfileState>(ProfileNotifier.new);
