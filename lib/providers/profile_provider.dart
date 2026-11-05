import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/profile.dart';
import '../core/models/profile_bundle.dart';
import '../core/models/connections_bundle.dart';
import '../core/services/profile_storage_service.dart';
import '../core/services/settings_service.dart';
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
      final defaultProfile = Profile(
        id: 'default',
        name: 'По умолчанию',
        isDefault: true,
        settings: settings,
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
    await _storage.saveActiveProfileId(id);

    state = AsyncData(current.copyWith(activeProfileId: id));
    ref.invalidate(settingsProvider);
  }

  Future<void> createProfile(String name, {bool copyFromCurrent = true}) async {
    final current = _current;
    if (current == null) return;

    final settings = copyFromCurrent
        ? (ref.read(settingsProvider).maybeWhen(
            data: (d) => d, orElse: () => null) ?? const AppSettings())
        : const AppSettings();

    final id = 'profile_${DateTime.now().millisecondsSinceEpoch}';
    final profile = Profile(
      id: id,
      name: name,
      settings: settings,
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
    String? sourceUrl,
  }) async {
    final current = _current;
    if (current == null) return null;

    final local = await ref.read(settingsProvider.future);
    final newId = 'profile_${DateTime.now().millisecondsSinceEpoch}';
    final profile = Profile(
      id: newId,
      name: bundle.profile.name,
      isDefault: false,
      readonly: makeReadonly,
      settings: _keepLocalSecurity(bundle.profile.settings, local),
      createdAt: DateTime.now(),
      sourceUrl: sourceUrl ?? bundle.sourceUrl,
      lastFetchedAt: sourceUrl != null ? DateTime.now() : bundle.profile.lastFetchedAt,
    );

    final profiles = [...current.profiles, profile];
    await _storage.saveProfiles(profiles);
    state = AsyncData(current.copyWith(profiles: profiles));

    if (bundle.hasConnections) {
      await ref.read(configProvider.notifier).importBundle(ConnectionsBundle(
        exportedAt: bundle.exportedAt,
        configs: bundle.configs ?? [],
        subscriptions: bundle.subscriptions ?? [],
      ));
    }

    if (switchToProfile) await switchProfile(newId);
    return newId;
  }

  /// Чужой профиль не трогает поля, которыми вскрывается туннель: SOCKS (порт,
  /// креды — открытый прокси на localhost), proxy-only (трафик мимо VPN), URL
  /// пробы heartbeat (видит IP сервера), HWID и автоматизацию.
  static AppSettings _keepLocalSecurity(AppSettings imported, AppSettings local) =>
      imported.copyWith(
        socksPort: local.socksPort,
        randomPort: local.randomPort,
        randomCredentials: local.randomCredentials,
        socksUser: local.socksUser,
        socksPassword: local.socksPassword,
        proxyOnly: local.proxyOnly,
        hwidEnabled: local.hwidEnabled,
        automationEnabled: local.automationEnabled,
        heartbeat: imported.heartbeat.copyWith(
          target: local.heartbeat.target,
          customUrl: local.heartbeat.customUrl,
        ),
      );

  Future<String?> refreshProfile(String profileId, String url) async {
    final current = _current;
    if (current == null) return null;

    ProfileBundle bundle;
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;

      bundle = ProfileBundle.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      return null;
    }

    final existingIdx = current.profiles.indexWhere((p) => p.id == profileId);
    if (existingIdx < 0) return null;

    final existing = current.profiles[existingIdx];
    final updated = existing.copyWith(
      name: bundle.profile.name,
      settings: _keepLocalSecurity(bundle.profile.settings, existing.settings),
      lastFetchedAt: DateTime.now(),
    );

    final profiles = [...current.profiles];
    profiles[existingIdx] = updated;
    await _storage.saveProfiles(profiles);
    state = AsyncData(current.copyWith(profiles: profiles));

    if (bundle.hasConnections) {
      await ref.read(configProvider.notifier).importBundle(ConnectionsBundle(
        exportedAt: bundle.exportedAt,
        configs: bundle.configs ?? [],
        subscriptions: bundle.subscriptions ?? [],
      ));
    }

    // If this is the active profile, apply its settings
    if (profileId == current.activeProfileId) {
      await SettingsService().save(updated.settings);
      ref.invalidate(settingsProvider);
    }

    return profileId;
  }
}

final profileProvider =
    AsyncNotifierProvider<ProfileNotifier, ProfileState>(ProfileNotifier.new);
