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
import 'vpn_provider.dart';
import '../l10n/l10n.dart';

class ProfileState {
  final List<Profile> profiles;
  final String activeProfileId;

  const ProfileState({required this.profiles, required this.activeProfileId});

  Profile? get activeProfile => profiles.where((p) => p.id == activeProfileId).firstOrNull;

  bool get isReadonly => activeProfile?.readonly ?? false;

  ProfileState copyWith({List<Profile>? profiles, String? activeProfileId}) =>
      ProfileState(profiles: profiles ?? this.profiles, activeProfileId: activeProfileId ?? this.activeProfileId);
}

class ProfileNotifier extends AsyncNotifier<ProfileState> {
  final _storage = ProfileStorageService();

  ProfileState? get _current => state.maybeWhen(data: (d) => d, orElse: () => null);

  /// Every write of the profile list goes through this queue and re-reads the state inside it:
  /// a write built from an older snapshot (before a switch, a sync or a download) would drop the
  /// other's change.
  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Rewrites the list from the latest state; [change] returns null — nothing to write.
  Future<void> _update(List<Profile>? Function(ProfileState current) change) => _serial(() async {
    final current = _current;
    if (current == null) return;
    final profiles = change(current);
    if (profiles == null) return;
    await _storage.saveProfiles(profiles);
    state = AsyncData(current.copyWith(profiles: profiles));
  });

  @override
  Future<ProfileState> build() async {
    var profiles = await _storage.loadProfiles();
    var activeId = await _storage.loadActiveProfileId();

    if (profiles.isEmpty) {
      final settings = await SettingsService().load();
      final defaultProfile = Profile(
        id: 'default',
        name: L10n.current.profileDefaultName,
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

  /// Applies the profile's settings and its remembered server. A live tunnel is rebuilt when
  /// either of them changes what it runs.
  Future<void> switchProfile(String id) async {
    var switched = false;
    try {
      // The selection is restored inside the queue: the next switch must see this profile's server,
      // not the previous one's.
      await _serial(() async {
        final target = await _switch(id);
        switched = target != null;
        final selection = target?.selection;
        if (selection != null) await ref.read(configProvider.notifier).applySelection(selection);
      });
    } finally {
      // Also when restoring the server failed: the profile is already switched, so its settings and
      // the tunnel follow it (a retry can't — the profile is active).
      if (switched) {
        ref.invalidate(settingsProvider);
        // No VPN notifier — nothing is connected (it lives as long as the app UI).
        if (ref.read(vpnProvider.exists)) {
          await ref.read(settingsProvider.future);
          await ref.read(vpnProvider.notifier).reconnectIfStale();
        }
      }
    }
  }

  /// Saves the switch; returns the incoming profile, null — nothing to switch.
  Future<Profile?> _switch(String id) async {
    // The outgoing profile remembers the server selected under it; a profile that has none yet
    // takes the current one.
    final selection = await ref.read(configProvider.notifier).currentSelection();
    final current = _current;
    if (current == null || current.activeProfileId == id) return null;
    final target = current.profiles.firstWhere((p) => p.id == id);
    final profiles = [
      for (final p in current.profiles)
        if (p.id == current.activeProfileId || (p.id == id && p.selection == null))
          p.copyWith(selection: selection)
        else
          p,
    ];
    await _storage.saveProfiles(profiles);
    await SettingsService().save(target.settings);
    await _storage.saveActiveProfileId(id);
    state = AsyncData(current.copyWith(profiles: profiles, activeProfileId: id));
    return target;
  }

  Future<void> createProfile(String name, {bool copyFromCurrent = true}) {
    final settings = copyFromCurrent
        ? (ref.read(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null) ?? const AppSettings())
        : const AppSettings();

    final id = 'profile_${DateTime.now().millisecondsSinceEpoch}';
    final profile = Profile(id: id, name: name, settings: settings, createdAt: DateTime.now());
    return _update((current) => [...current.profiles, profile]);
  }

  Future<void> renameProfile(String id, String newName) =>
      _update((current) => current.profiles.map((p) => p.id == id ? p.copyWith(name: newName) : p).toList());

  Future<void> deleteProfile(String id) => _update((current) {
    final target = current.profiles.firstWhere((p) => p.id == id);
    if (target.isDefault || current.activeProfileId == id) return null;
    return current.profiles.where((p) => p.id != id).toList();
  });

  Future<void> toggleReadonly(String id) =>
      _update((current) => current.profiles.map((p) => p.id == id ? p.copyWith(readonly: !p.readonly) : p).toList());

  /// Settings go to the profile active when they were saved, even if a switch runs first.
  /// [profileId] — the profile active when the caller started saving; by default the active one now.
  Future<void> syncActiveSettings(AppSettings settings, {String? profileId}) {
    final id = profileId ?? _current?.activeProfileId;
    if (id == null) return Future.value();
    return _update((current) => current.profiles.map((p) => p.id == id ? p.copyWith(settings: settings) : p).toList());
  }

  ProfileBundle exportBundle(String profileId, {bool includeConnections = false}) {
    final current = _current!;
    final stored = current.profiles.firstWhere((p) => p.id == profileId);
    // Local secrets don't go into the file (import ignores them anyway — _keepLocalSecurity).
    // The remembered server is local too: config and subscription references mean nothing elsewhere.
    final profile = stored.copyWith(
      clearSelection: true,
      settings: stored.settings.copyWith(
        socksUser: '',
        socksPassword: '',
        heartbeat: stored.settings.heartbeat.copyWith(customUrl: ''),
      ),
    );
    if (!includeConnections) {
      return ProfileBundle(exportedAt: DateTime.now(), profile: profile);
    }
    final configState = ref.read(configProvider).maybeWhen(data: (d) => d, orElse: () => null);
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
    if (_current == null) return null;

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

    await _update((current) => [...current.profiles, profile]);

    if (bundle.hasConnections) {
      await ref
          .read(configProvider.notifier)
          .importBundle(
            ConnectionsBundle(
              exportedAt: bundle.exportedAt,
              configs: bundle.configs ?? [],
              subscriptions: bundle.subscriptions ?? [],
            ),
          );
    }

    if (switchToProfile) await switchProfile(newId);
    return newId;
  }

  /// A foreign profile doesn't touch fields that expose the tunnel: SOCKS (port,
  /// credentials — an open proxy on localhost), proxy-only (traffic bypassing the VPN), heartbeat
  /// probe URL (sees the server IP), HWID and automation.
  static AppSettings _keepLocalSecurity(AppSettings imported, AppSettings local) => imported.copyWith(
    socksPort: local.socksPort,
    randomPort: local.randomPort,
    randomCredentials: local.randomCredentials,
    socksUser: local.socksUser,
    socksPassword: local.socksPassword,
    proxyOnly: local.proxyOnly,
    hwidEnabled: local.hwidEnabled,
    automationEnabled: local.automationEnabled,
    heartbeat: imported.heartbeat.copyWith(target: local.heartbeat.target, customUrl: local.heartbeat.customUrl),
  );

  Future<String?> refreshProfile(String profileId, String url) async {
    if (_current == null) return null;

    ProfileBundle bundle;
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;

      bundle = ProfileBundle.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (e) {
      return null;
    }

    // The download took a while: merge into the latest state (a switch may have run meanwhile).
    final updated = await _serial(() async {
      final current = _current;
      final existing = current?.profiles.where((p) => p.id == profileId).firstOrNull;
      if (current == null || existing == null) return null;
      final updated = existing.copyWith(
        name: bundle.profile.name,
        settings: _keepLocalSecurity(bundle.profile.settings, existing.settings),
        lastFetchedAt: DateTime.now(),
      );
      final profiles = current.profiles.map((p) => p.id == profileId ? updated : p).toList();
      await _storage.saveProfiles(profiles);
      state = AsyncData(current.copyWith(profiles: profiles));
      if (profileId == current.activeProfileId) await SettingsService().save(updated.settings);
      return updated;
    });
    if (updated == null) return null;
    // The active profile's settings were saved above; reload them before the import, which may fail.
    if (profileId == _current?.activeProfileId) ref.invalidate(settingsProvider);

    if (bundle.hasConnections) {
      await ref
          .read(configProvider.notifier)
          .importBundle(
            ConnectionsBundle(
              exportedAt: bundle.exportedAt,
              configs: bundle.configs ?? [],
              subscriptions: bundle.subscriptions ?? [],
            ),
          );
    }

    return profileId;
  }
}

final profileProvider = AsyncNotifierProvider<ProfileNotifier, ProfileState>(ProfileNotifier.new);
