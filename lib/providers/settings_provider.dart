import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/app_settings.dart';
import '../core/models/core_kind.dart';
import '../core/models/dns_config.dart';
import '../core/models/setting_field.dart';
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

  /// Writes [value] to [field].
  Future<void> set<T>(SettingField<T> field, T value) => edit((c) => field.write(c, value));

  /// Writes [field] from its value current when the write runs (removing one item of a list, for one).
  Future<void> modify<T>(SettingField<T> field, T Function(T current) change) =>
      edit((c) => field.write(c, change(field.read(c))));

  /// A numeric field's commit from a text input: an empty or unparsable value changes nothing; the field clamps.
  Future<void> commitInt(IntSettingField field, String text) async {
    final value = int.tryParse(text.trim());
    if (value != null) await set(field, value);
  }

  /// SOCKS login and password, saved together.
  Future<void> setSocksCredentials(String user, String password) =>
      edit((c) => c.copyWith(socksUser: user, socksPassword: password));

  /// Both geodata sources, saved together.
  Future<void> setGeoSources(String geoipUrl, String geositeUrl) =>
      edit((c) => c.copyWith(geoipUrl: geoipUrl, geositeUrl: geositeUrl));

  /// The DNS screen's fields, saved together; an empty custom address falls back to `1.1.1.1`.
  Future<void> setDns({
    required DnsMode mode,
    required String preset,
    required String customAddress,
    required DnsType customType,
    required DnsQueryStrategy strategy,
  }) {
    final address = customAddress.trim();
    return edit(
      (c) => c.copyWith(
        dnsMode: mode,
        dnsPreset: preset,
        customDnsAddress: address.isEmpty ? '1.1.1.1' : address,
        customDnsType: customType.name,
        dnsQueryStrategy: strategy,
      ),
    );
  }

  /// Toggles [package] in the list the split-tunnel mode uses — both as they are when the write runs, so a tap
  /// before a mode change shows goes to the right list.
  Future<void> togglePackage(String package) => edit((c) {
    Set<String> toggled(Set<String> set) => set.contains(package) ? ({...set}..remove(package)) : {...set, package};
    return c.vpnMode == VpnMode.onlySelected
        ? c.copyWith(includedPackages: toggled(c.includedPackages))
        : c.copyWith(excludedPackages: toggled(c.excludedPackages));
  });

  /// Enables or disables [core]. Disabling is refused when no core of the order that is in [available] would stay
  /// enabled — checked on the settings it writes to, so taps queued before a rebuild can't disable every core.
  Future<void> setCoreEnabled(CoreKind core, bool enabled, {required Set<CoreKind> available}) => edit((c) {
    if (enabled) return c.copyWith(disabledCores: {...c.disabledCores}..remove(core));
    final disabled = {...c.disabledCores, core};
    if (!c.coreOrder.any((o) => available.contains(o) && !disabled.contains(o))) return c;
    return c.copyWith(disabledCores: disabled);
  });

  /// Moves [core] one place up in the order it writes to: taps queued before a rebuild each move from the previous
  /// result.
  Future<void> moveCoreUp(CoreKind core) => edit((c) {
    final j = c.coreOrder.indexOf(core);
    if (j <= 0) return c;
    final next = [...c.coreOrder]..insert(j - 1, core);
    next.removeAt(j + 1);
    return c.copyWith(coreOrder: List.unmodifiable(next));
  });

  Future<void> cleanGhostPackages(Set<String> installedPackages) => _update((current) {
    final newIncluded = current.includedPackages.intersection(installedPackages);
    final newExcluded = current.excludedPackages.intersection(installedPackages);
    if (newIncluded.length == current.includedPackages.length &&
        newExcluded.length == current.excludedPackages.length) {
      return null;
    }
    return current.copyWith(includedPackages: newIncluded, excludedPackages: newExcluded);
  });

  Future<void> _update(AppSettings? Function(AppSettings current) change) =>
      ref.read(profileProvider.notifier).updateActiveSettings(change);
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
