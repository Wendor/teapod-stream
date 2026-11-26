import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/profile.dart';
import '../core/models/profile_bundle.dart';
import '../core/models/connections_bundle.dart';
import '../core/models/app_message.dart';
import '../core/models/import_review.dart';
import '../core/services/bundle_loader.dart';
import '../core/services/deeplink_router.dart';
import '../core/services/profile_storage_service.dart';
import '../core/services/settings_service.dart';
import '../core/models/app_settings.dart';
import 'config_provider.dart';
import 'vpn_provider.dart';

/// Bundle downloads go through the tunnel when it is up.
final bundleLoaderProvider = Provider<BundleLoader>((ref) => BundleLoader(() => ref.read(tunnelSocksProvider)));

/// How [ProfileNotifier.refreshProfile] ended.
sealed class ProfileRefresh {
  const ProfileRefresh();
}

final class ProfileRefreshed extends ProfileRefresh {
  const ProfileRefreshed();
}

/// The user declined the review: nothing applied.
final class ProfileRefreshDeclined extends ProfileRefresh {
  const ProfileRefreshDeclined();
}

final class ProfileRefreshFailed extends ProfileRefresh {
  const ProfileRefreshFailed(this.reason);

  final AppMessage reason;
}

class ProfileState {
  final List<Profile> profiles;
  final String activeProfileId;

  const ProfileState({required this.profiles, required this.activeProfileId});

  Profile? get activeProfile => profiles.where((p) => p.id == activeProfileId).firstOrNull;

  bool get isReadonly => activeProfile?.readonly ?? false;

  /// The settings in force (`settingsProvider` exposes them; this provider can't read it — it depends on this one).
  AppSettings get activeSettings => activeProfile?.settings ?? const AppSettings();

  ProfileState copyWith({List<Profile>? profiles, String? activeProfileId}) =>
      ProfileState(profiles: profiles ?? this.profiles, activeProfileId: activeProfileId ?? this.activeProfileId);
}

class ProfileNotifier extends AsyncNotifier<ProfileState> {
  ProfileStorageService get _storage => ref.read(profileStorageServiceProvider);
  SettingsService get _legacy => ref.read(settingsServiceProvider);

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

  /// The state once loaded: a mutation queued before [build] finished waits for it.
  Future<ProfileState> _loaded() async => _current ?? await future;

  @override
  Future<ProfileState> build() async {
    var profiles = await _storage.loadProfiles();
    var activeId = await _storage.loadActiveProfileId();
    // Until the migration the per-key settings are the ones in force: they become the active profile's.
    final legacy = await _legacy.migrated() ? null : await _legacy.load();

    if (profiles.isEmpty) {
      profiles = [Profile.initial(legacy ?? const AppSettings())];
      await _storage.saveProfiles(profiles);
      await _storage.saveActiveProfileId('default');
      activeId = 'default';
    }

    if (!profiles.any((p) => p.id == activeId)) {
      activeId = profiles.first.id;
      await _storage.saveActiveProfileId(activeId);
    }

    if (legacy != null) {
      profiles = [for (final p in profiles) p.id == activeId ? p.copyWith(settings: legacy) : p];
      await _storage.saveProfiles(profiles);
      await _legacy.markMigrated();
    }

    final state = ProfileState(profiles: profiles, activeProfileId: activeId);
    // The active profile may have changed above (migrated, or the stored id was gone): native reads its flags.
    await _legacy.mirrorNative(state.activeSettings);
    return state;
  }

  /// The only writer of the settings in force: [change] maps the settings of profile [profileId] (by default the one
  /// active when this runs) to new ones (null — nothing to save). A caller that built the settings from what it saw
  /// passes the profile active then: a switch queued before the write doesn't give them to the next profile. A
  /// readonly profile keeps its settings.
  Future<void> updateActiveSettings(AppSettings? Function(AppSettings current) change, {String? profileId}) =>
      _serial(() async {
        final current = await _loaded();
        final id = profileId ?? current.activeProfileId;
        final target = current.profiles.where((p) => p.id == id).firstOrNull;
        if (target == null || target.readonly) return;
        final next = change(target.settings);
        if (next == null) return;
        final profiles = [for (final p in current.profiles) p.id == id ? p.copyWith(settings: next) : p];
        await _storage.saveProfiles(profiles);
        state = AsyncData(current.copyWith(profiles: profiles));
        if (id == current.activeProfileId) await _legacy.mirrorNative(next);
      });

  /// Applies the profile's settings and its remembered server; false — nothing to switch. The selection is restored
  /// inside the queue: the next switch must see this profile's server, not the previous one's. With the VPN following
  /// — `VpnNotifier.switchProfile` (this provider can't read the VPN one: that one depends on the settings, which
  /// derive from this one).
  Future<bool> switchProfile(String id) => _serial(() async {
    final target = await _switch(id);
    if (target == null) return false;
    final selection = target.selection;
    if (selection != null) await ref.read(configProvider.notifier).applySelection(selection);
    return true;
  });

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
    await _storage.saveActiveProfileId(id);
    state = AsyncData(current.copyWith(profiles: profiles, activeProfileId: id));
    await _legacy.mirrorNative(target.settings);
    return target;
  }

  Future<void> createProfile(String name, {bool copyFromCurrent = true}) {
    final settings = copyFromCurrent ? (_current?.activeSettings ?? const AppSettings()) : const AppSettings();

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

  /// What importing [bundle] changes, shown before [importBundle]: traffic settings against the ones in force now
  /// (local fields already kept) and the hosts of the subscriptions it adds.
  Future<ImportReview> reviewImport(ProfileBundle bundle) async {
    final local = (await _loaded()).activeSettings;
    return _review(bundle, local);
  }

  ImportReview _review(ProfileBundle bundle, AppSettings current) => ImportReview(
    changes: ImportReview.trafficChanges(current, _keepLocalSecurity(bundle.profile.settings, current)),
    subscriptionHosts: ref
        .read(configProvider.notifier)
        .newSubscriptionHosts((bundle.subscriptions ?? const []).map((s) => s.url)),
  );

  /// Adds [bundle]'s profile (and its connections); returns its id. Switching to it is the caller's
  /// (`VpnNotifier.switchProfile`).
  Future<String?> importBundle(ProfileBundle bundle, {bool makeReadonly = false, String? sourceUrl}) async {
    if (_current == null) return null;

    final local = (await _loaded()).activeSettings;
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

    return newId;
  }

  /// A foreign profile doesn't touch fields that expose the tunnel: SOCKS (port,
  /// credentials — an open proxy on localhost), proxy-only (traffic bypassing the VPN), heartbeat
  /// probe URL (sees the server IP), HWID, automation and the geodata sources (routing decisions come from them).
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
    geoipUrl: local.geoipUrl,
    geositeUrl: local.geositeUrl,
  );

  /// Downloads the profile from [url] and applies it. When it changes traffic settings or adds subscriptions,
  /// [confirm] is asked first; declined — nothing is applied.
  Future<ProfileRefresh> refreshProfile(
    String profileId,
    String url, {
    Future<bool> Function(ImportReview review)? confirm,
  }) async {
    const gone = ProfileRefreshFailed(AppMessage(MessageCode.profileUpdateError));
    if (_current == null) return gone;

    final uri = Uri.tryParse(url);
    final load = uri == null
        ? const BundleFailed(AppMessage(MessageCode.bundleFetchFailed))
        : await ref.read(bundleLoaderProvider).fetch(uri, DeeplinkType.profile);
    if (load is! ProfileLoaded) return ProfileRefreshFailed(load is BundleFailed ? load.reason : gone.reason);
    final bundle = load.bundle;

    if (confirm != null) {
      final existing = _current?.profiles.where((p) => p.id == profileId).firstOrNull;
      if (existing == null) return gone;
      final review = _review(bundle, existing.settings);
      if (!review.isEmpty && !await confirm(review)) return const ProfileRefreshDeclined();
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
      if (profileId == current.activeProfileId) await _legacy.mirrorNative(updated.settings);
      return updated;
    });
    if (updated == null) return gone;

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

    return const ProfileRefreshed();
  }
}

final profileProvider = AsyncNotifierProvider<ProfileNotifier, ProfileState>(ProfileNotifier.new);
