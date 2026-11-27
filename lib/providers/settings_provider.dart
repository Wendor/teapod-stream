import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/app_settings.dart';
import 'profile_provider.dart';

/// The settings in force: the active profile's. Every write goes through [ProfileNotifier.updateActiveSettings],
/// which queues it after the other profile writes and refuses a readonly profile.
class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  FutureOr<AppSettings> build() {
    // One subscription (to the future): a second one would rebuild this provider while it still loads.
    final next = ref.watch(profileProvider.future);
    final profiles = ref.read(profileProvider);
    // Loaded: synchronously, so a reader right after a save sees the saved settings.
    if (profiles.hasValue && !profiles.isLoading) return profiles.requireValue.activeSettings;
    return next.then((s) => s.activeSettings);
  }

  /// Applies [change] to the settings current when the write runs — not to the ones a widget last rendered, so a
  /// write queued in between (another field, [cleanGhostPackages]) survives. The change belongs to the profile
  /// active now: it goes there even if a switch runs first. A readonly profile keeps its settings.
  Future<void> edit(AppSettings Function(AppSettings current) change) => ref
      .read(profileProvider.notifier)
      .updateActiveSettings(change, profileId: ref.read(profileProvider).value?.activeProfileId);

  /// Replaces the settings as a whole (a flow that built all of them); a widget changing fields uses [edit].
  Future<void> save(AppSettings settings) => edit((_) => settings);

  Future<void> cleanGhostPackages(Set<String> installedPackages) => _update((current) {
    final newIncluded = current.includedPackages.intersection(installedPackages);
    final newExcluded = current.excludedPackages.intersection(installedPackages);
    if (newIncluded.length == current.includedPackages.length &&
        newExcluded.length == current.excludedPackages.length) {
      return null;
    }
    return current.copyWith(includedPackages: newIncluded, excludedPackages: newExcluded);
  });

  Future<void> toggleExcludedPackage(String package) => _update((current) {
    final excluded = Set<String>.from(current.excludedPackages);
    if (!excluded.remove(package)) excluded.add(package);
    return current.copyWith(excludedPackages: excluded);
  });

  Future<void> _update(AppSettings? Function(AppSettings current) change) =>
      ref.read(profileProvider.notifier).updateActiveSettings(change);
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
