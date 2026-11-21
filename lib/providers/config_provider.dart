import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/vpn_config.dart';
import '../core/models/pinned_ref.dart';
import '../core/models/config_selection.dart';
import '../core/models/connections_bundle.dart';
import '../core/services/config_storage_service.dart';
import '../core/models/subscription.dart';
import '../core/services/subscription_service.dart' show SubscriptionService, SubscriptionFetchResult, HwidDeviceInfo;
import '../core/services/device_service.dart';
import '../core/services/log_service.dart';
import 'settings_provider.dart';
import 'vpn_provider.dart';
import '../l10n/l10n.dart';

class ConfigState {
  final List<VpnConfig> configs;
  final String? activeConfigId;
  final String? activeSubscriptionId;
  final List<Subscription> subscriptions;
  final List<PinnedRef> pins;

  ConfigState({
    this.configs = const [],
    this.activeConfigId,
    this.activeSubscriptionId,
    this.subscriptions = const [],
    this.pins = const [],
  });

  VpnConfig? get activeConfig =>
      activeConfigId == null ? null : configs.where((c) => c.id == activeConfigId).firstOrNull;

  ConfigSelection get selection {
    final active = activeConfig;
    return ConfigSelection(
      configId: active?.id,
      config: active == null ? null : PinnedRef.of(active),
      subscriptionId: activeSubscriptionId,
    );
  }

  late final List<VpnConfig> standaloneConfigs = configs.where((c) => c.subscriptionId == null).toList();

  late final Map<String, List<VpnConfig>> configsBySubscription = () {
    final result = <String, List<VpnConfig>>{};
    for (final config in configs.where((c) => c.subscriptionId != null)) {
      result.putIfAbsent(config.subscriptionId!, () => []).add(config);
    }
    return result;
  }();

  /// Pins in pinning order; null — a config with that name
  /// is missing from the subscription (the pin is "lost" but not removed).
  late final List<(PinnedRef, VpnConfig?)> resolvedPins = pins.map((p) => (p, p.resolve(configs))).toList();

  late final Set<String> pinnedIds = {
    for (final (_, c) in resolvedPins)
      if (c != null) c.id,
  };

  bool isPinned(VpnConfig c) => pinnedIds.contains(c.id);

  ConfigState copyWith({
    List<VpnConfig>? configs,
    String? activeConfigId,
    bool clearActive = false,
    String? activeSubscriptionId,
    bool clearActiveSub = false,
    List<Subscription>? subscriptions,
    List<PinnedRef>? pins,
  }) {
    return ConfigState(
      configs: configs ?? this.configs,
      activeConfigId: clearActive ? null : (activeConfigId ?? this.activeConfigId),
      activeSubscriptionId: clearActiveSub ? null : (activeSubscriptionId ?? this.activeSubscriptionId),
      subscriptions: subscriptions ?? this.subscriptions,
      pins: pins ?? this.pins,
    );
  }
}

class ConfigNotifier extends AsyncNotifier<ConfigState> {
  static final storage = ConfigStorageService();

  /// Mutations run strictly in order: each reads state, waits for
  /// the storage load-modify-save and writes state. Run in parallel (a ping in the middle
  /// of a subscription refresh) they overwrote each other — disk kept
  /// the old configs, memory the new ones.
  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<ConfigState> build() async {
    final configs = await storage.loadConfigs();
    final activeId = await storage.loadActiveConfigId();
    final activeSubId = await storage.loadActiveSubscriptionId();
    final subs = await storage.loadSubscriptions();
    final pins = await storage.loadPins();
    return ConfigState(
      configs: configs,
      activeConfigId: activeId,
      activeSubscriptionId: activeSubId,
      subscriptions: subs,
      pins: pins,
    );
  }

  // ─── Pins ───

  Future<void> togglePin(VpnConfig c) => _serial(() async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null);
    if (current == null) return;
    // Remove the pin that resolves to this config (including the old format).
    final pins = current.isPinned(c)
        ? [
            for (final (p, r) in current.resolvedPins)
              if (r?.id != c.id) p,
          ]
        : [...current.pins, PinnedRef.of(c)];
    await storage.savePins(pins);
    state = AsyncData(current.copyWith(pins: pins));
  });

  Future<void> unpin(PinnedRef pin) => _serial(() async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null);
    if (current == null) return;
    final pins = current.pins.where((p) => p != pin).toList();
    await storage.savePins(pins);
    state = AsyncData(current.copyWith(pins: pins));
  });

  Future<void> addConfig(VpnConfig config) => _serial(() async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? ConfigState();
    final configs = [...current.configs, config];
    await storage.addConfig(config);
    state = AsyncData(current.copyWith(configs: configs));
  });

  Future<void> addConfigs(List<VpnConfig> newConfigs) => _serial(() async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? ConfigState();
    final configs = [...current.configs, ...newConfigs];
    await storage.addConfigsBatch(newConfigs);
    state = AsyncData(current.copyWith(configs: configs));
  });

  Future<void> removeConfig(String id) => _serial(() async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? ConfigState();
    final configs = current.configs.where((c) => c.id != id).toList();
    await storage.removeConfig(id);
    final newState = current.activeConfigId == id
        ? current.copyWith(configs: configs, clearActive: true)
        : current.copyWith(configs: configs);
    if (current.activeConfigId == id) {
      await storage.saveActiveConfigId(null);
    }
    state = AsyncData(newState);
  });

  Future<void> setActiveConfig(String? id) => _serial(() => _setActiveConfig(id));

  Future<void> _setActiveConfig(String? id) async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? ConfigState();
    // Selecting a specific config clears subscription mode
    if (id == null) {
      state = AsyncData(current.copyWith(clearActive: true, clearActiveSub: true));
    } else {
      state = AsyncData(current.copyWith(activeConfigId: id, clearActiveSub: true));
    }
    await storage.saveActiveConfigId(id);
    await storage.saveActiveSubscriptionId(null);
  }

  Future<void> setActiveSubscription(String? id) => _serial(() async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? ConfigState();
    state = AsyncData(current.copyWith(activeSubscriptionId: id, clearActiveSub: id == null));
    await storage.saveActiveSubscriptionId(id);
  });

  /// The selection after every mutation queued so far.
  Future<ConfigSelection> currentSelection() => _serial(() async => (await future).selection);

  /// Restores a selection remembered by a profile. Whatever no longer exists is skipped;
  /// when nothing of it is left, the current selection stays.
  Future<void> applySelection(ConfigSelection selection) => _serial(() async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null);
    if (current == null) return;
    final config = selection.resolve(current.configs);
    final subId = current.subscriptions.any((s) => s.id == selection.subscriptionId) ? selection.subscriptionId : null;
    if (config == null && subId == null) return;
    final activeId = config?.id ?? current.activeConfigId;
    state = AsyncData(
      current.copyWith(activeConfigId: activeId, activeSubscriptionId: subId, clearActiveSub: subId == null),
    );
    await storage.saveActiveConfigId(activeId);
    await storage.saveActiveSubscriptionId(subId);
  });

  Future<void> updateConfig(VpnConfig updated) => _serial(() async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? ConfigState();
    final configs = current.configs.map((c) => c.id == updated.id ? updated : c).toList();
    await storage.updateConfig(updated);
    state = AsyncData(current.copyWith(configs: configs));
  });

  // ─── Subscription methods ───

  /// [replaceId] — update the subscription with this id to the new [url] (URL change):
  /// on a load error the old subscription stays untouched.
  Future<void> addSubscriptionFromUrl(
    String url, {
    String? name,
    bool allowSelfSigned = false,
    String? replaceId,
  }) async {
    bool isTarget(Subscription s) => replaceId != null ? s.id == replaceId : s.url == url;
    final before = state.value ?? ConfigState();
    final target = before.subscriptions.where(isTarget).firstOrNull;
    final subId = target?.id ?? 'sub_${DateTime.now().millisecondsSinceEpoch}';

    final settings = ref.read(settingsProvider).value;
    final hwid = (settings?.hwidEnabled ?? false) ? await DeviceService.getHwidInfo() : null;
    // Network — outside the mutation queue so config selection doesn't wait for the download.
    final (tagged, fetchResult) = await _fetchAndTagConfigs(
      url,
      subId,
      allowSelfSigned: allowSelfSigned,
      pinnedCertDer: target?.pinnedCertDer,
      hwid: hwid,
      userAgent: settings?.subUserAgent ?? '',
    );
    if (tagged.isEmpty) {
      // The provider usually explains an empty response: HWID device limit or announce.
      throw Exception(
        fetchResult.hwidStatus?.maxDevicesReached == true
            ? L10n.current.subHwidLimit
            : fetchResult.announce ?? L10n.current.subEmpty,
      );
    }

    await _serial(() async {
      // State is re-read under the queue: it could have changed during the download.
      final current = state.value ?? ConfigState();
      final existing = current.subscriptions.where((s) => s.id == subId).firstOrNull;
      final oldConfigs = current.configs.where((c) => c.subscriptionId == subId).toList();

      // Ping (TCP to address:port) is carried over by endpoint. The pinned core —
      // by name+endpoint, or by endpoint if it is unique in the subscription.
      final oldByEndpoint = <String, List<VpnConfig>>{};
      for (final c in oldConfigs) {
        (oldByEndpoint['${c.address}:${c.port}'] ??= []).add(c);
      }
      final newConfigs = tagged.map((c) {
        final olds = oldByEndpoint['${c.address}:${c.port}'];
        if (olds == null) return c;
        final same = olds.where((o) => o.name == c.name).firstOrNull ?? (olds.length == 1 ? olds.first : null);
        final ping = same ?? olds.last;
        return c.copyWith(latencyMs: ping.latencyMs, lastPingedAt: ping.lastPingedAt, core: same?.core);
      }).toList();

      // The parser issues new ids — carry the selection over: name+endpoint, then endpoint,
      // then name (names in a subscription aren't unique, e.g. "VLESS Server").
      String? activeId = current.activeConfigId;
      final oldActive = current.activeConfig;
      if (oldActive != null && oldActive.subscriptionId == subId) {
        bool sameEndpoint(VpnConfig c) => c.address == oldActive.address && c.port == oldActive.port;
        activeId =
            (newConfigs.where((c) => sameEndpoint(c) && c.name == oldActive.name).firstOrNull ??
                    newConfigs.where(sameEndpoint).firstOrNull ??
                    newConfigs.where((c) => c.name == oldActive.name).firstOrNull)
                ?.id;
      }
      // No active one (or it vanished from the subscription) — the first new one. The subscription
      // auto-select mode (activeSubscriptionId) is not reset by this.
      activeId ??= newConfigs.first.id;

      final sub = Subscription(
        id: subId,
        // A user-given name isn't overwritten by profile-title on refresh
        name: name ?? existing?.name ?? fetchResult.profileTitle ?? Uri.parse(url).host,
        url: url,
        createdAt: existing?.createdAt ?? DateTime.now(),
        lastFetchedAt: DateTime.now(),
        expireAt: fetchResult.expireAt,
        uploadBytes: fetchResult.uploadBytes,
        downloadBytes: fetchResult.downloadBytes,
        totalBytes: fetchResult.totalBytes,
        announce: fetchResult.announce,
        announceUrl: fetchResult.announceUrl,
        pinnedCertDer: fetchResult.acceptedCertDer ?? existing?.pinnedCertDer,
      );

      // Remove old first, then add new — prevents duplicates if interrupted mid-update
      await storage.removeConfigsBatch(oldConfigs.map((c) => c.id).toList());
      await storage.addConfigsBatch(newConfigs);
      if (existing != null) {
        await storage.updateSubscription(sub);
      } else {
        await storage.addSubscription(sub);
      }
      if (activeId != current.activeConfigId) await storage.saveActiveConfigId(activeId);

      state = AsyncData(
        current.copyWith(
          configs: [...current.configs.where((c) => c.subscriptionId != subId), ...newConfigs],
          subscriptions: existing != null
              ? current.subscriptions.map((s) => s.id == subId ? sub : s).toList()
              : [...current.subscriptions, sub],
          activeConfigId: activeId,
        ),
      );
    });
  }

  Future<(List<VpnConfig>, SubscriptionFetchResult)> _fetchAndTagConfigs(
    String url,
    String subId, {
    bool allowSelfSigned = false,
    String? pinnedCertDer,
    HwidDeviceInfo? hwid,
    String? userAgent,
  }) async {
    final svc = SubscriptionService();
    final result = await svc.fetchSubscription(
      url,
      allowSelfSigned: allowSelfSigned,
      pinnedCertDer: pinnedCertDer,
      hwid: hwid,
      userAgent: userAgent,
      socks: ref.read(tunnelSocksProvider),
    );
    final tagged = result.configs.map((c) => c.copyWith(subscriptionId: subId)).toList();
    return (tagged, result);
  }

  Future<void> renameSubscription(String id, String newName) => _serial(() async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? ConfigState();
    final sub = current.subscriptions.firstWhere((s) => s.id == id);
    final renamed = sub.copyWith(name: newName);
    await storage.updateSubscription(renamed);
    state = AsyncData(
      current.copyWith(subscriptions: current.subscriptions.map((s) => s.id == id ? renamed : s).toList()),
    );
  });

  Future<void> removeSubscription(String subId) => _serial(() async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? ConfigState();
    await storage.removeSubscription(subId);
    final clearActiveSub = current.activeSubscriptionId == subId;
    if (clearActiveSub) await storage.saveActiveSubscriptionId(null);
    final pins = current.pins.where((p) => p.subscriptionId != subId).toList();
    if (pins.length != current.pins.length) await storage.savePins(pins);
    state = AsyncData(
      current.copyWith(
        pins: pins,
        configs: current.configs.where((c) => c.subscriptionId != subId).toList(),
        subscriptions: current.subscriptions.where((s) => s.id != subId).toList(),
        clearActive:
            current.activeConfigId != null &&
            current.configs.any((c) => c.id == current.activeConfigId && c.subscriptionId == subId),
        clearActiveSub: clearActiveSub,
      ),
    );
  });

  Future<void> refreshStaleSubscriptions({int intervalHours = 6}) async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null);
    if (current == null || current.subscriptions.isEmpty) return;
    final threshold = Duration(hours: intervalHours);
    final stale = current.subscriptions.where((s) {
      if (s.lastFetchedAt == null) return true;
      return DateTime.now().difference(s.lastFetchedAt!) > threshold;
    }).toList();
    if (_refreshingSubs) return;
    _refreshingSubs = true;
    try {
      for (final sub in stale) {
        // A broken subscription doesn't block the others and isn't retried on every resume.
        final failedAt = _subFailedAt[sub.id];
        if (failedAt != null && DateTime.now().difference(failedAt) < const Duration(hours: 1)) {
          continue;
        }
        try {
          await addSubscriptionFromUrl(sub.url);
          _subFailedAt.remove(sub.id);
        } catch (e) {
          _subFailedAt[sub.id] = DateTime.now();
          ref.read(logServiceProvider.notifier).addError('Subscription auto-refresh "${sub.name}": $e');
        }
      }
    } finally {
      _refreshingSubs = false;
    }
  }

  bool _refreshingSubs = false;
  final _subFailedAt = <String, DateTime>{};

  // ─── Import from ConnectionsBundle ───

  Future<ImportConnectionsResult> importBundle(ConnectionsBundle bundle) => _serial(() async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? ConfigState();

    // Build a map of old subscription ID -> new subscription ID
    final subIdMap = <String, String>{};
    var addedConfigs = 0;
    var addedSubscriptions = 0;
    final newSubscriptions = <Subscription>[];

    // Import subscriptions first, creating new IDs
    for (final sub in bundle.subscriptions) {
      final existingSub = current.subscriptions.where((s) => s.url == sub.url).firstOrNull;

      if (existingSub != null) {
        subIdMap[sub.id] = existingSub.id;
        continue;
      }

      final newId = 'sub_import_${DateTime.now().millisecondsSinceEpoch}_$addedSubscriptions';
      subIdMap[sub.id] = newId;

      final newSub = Subscription(
        id: newId,
        name: sub.name,
        url: sub.url,
        createdAt: DateTime.now(),
        lastFetchedAt: sub.lastFetchedAt,
        expireAt: sub.expireAt,
        uploadBytes: sub.uploadBytes,
        downloadBytes: sub.downloadBytes,
        totalBytes: sub.totalBytes,
        announce: sub.announce,
        announceUrl: sub.announceUrl,
      );
      newSubscriptions.add(newSub);
      await storage.addSubscription(newSub);
      addedSubscriptions++;
    }

    // Remap subscription IDs in configs and generate new IDs
    final newTs = DateTime.now().millisecondsSinceEpoch;
    final remappedConfigs = bundle.configs.asMap().entries.map((entry) {
      final idx = entry.key;
      final c = entry.value;
      final newId = 'cfg_import_${newTs}_${idx}_${c.id.hashCode}';
      final newSubId = c.subscriptionId != null && subIdMap.containsKey(c.subscriptionId)
          ? subIdMap[c.subscriptionId]
          : c.subscriptionId;

      return c.copyWith(id: newId, createdAt: DateTime.now(), subscriptionId: newSubId);
    }).toList();

    // Import configs that don't already exist (by rawUri or address:port match)
    final existingKeys = current.configs.map((c) => c.rawUri ?? '${c.address}:${c.port}').toSet();
    final newConfigs = <VpnConfig>[];
    for (final config in remappedConfigs) {
      final key = config.rawUri ?? '${config.address}:${config.port}';
      if (!existingKeys.contains(key)) {
        newConfigs.add(config);
      }
    }

    if (newConfigs.isNotEmpty) {
      await storage.addConfigsBatch(newConfigs);
      addedConfigs = newConfigs.length;
    }

    // Update in-memory state
    final updatedSubs = [...current.subscriptions, ...newSubscriptions];

    state = AsyncData(current.copyWith(configs: [...current.configs, ...newConfigs], subscriptions: updatedSubs));

    if (state.value?.activeConfigId == null && newConfigs.isNotEmpty) {
      await _setActiveConfig(newConfigs.first.id);
    }

    return ImportConnectionsResult(
      addedConfigs: addedConfigs,
      addedSubscriptions: addedSubscriptions,
      skippedConfigs: remappedConfigs.length - newConfigs.length,
    );
  });

  Future<void> batchUpdatePingResults(Map<String, int?> latencyByEndpoint, DateTime pingedAt) => _serial(() async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null);
    if (current == null) return;
    var anyChanged = false;
    final updated = current.configs.map((c) {
      final key = '${c.address}:${c.port}';
      if (!latencyByEndpoint.containsKey(key)) return c;
      anyChanged = true;
      // null — the server didn't answer: clear the old value, otherwise a dead
      // server with a "fresh" ping wins auto-select in subscription mode.
      final ms = latencyByEndpoint[key];
      return c.copyWith(latencyMs: ms, clearLatency: ms == null, lastPingedAt: pingedAt);
    }).toList();
    if (!anyChanged) return;
    await storage.saveConfigs(updated);
    state = AsyncData(current.copyWith(configs: updated));
  });

  // ─── Reorder ───
  // `newIndex` is the item's index after the move, as `ReorderableListView.onReorderItem` reports it.

  Future<void> reorderSubscriptions(int oldIndex, int newIndex) => _serial(() async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null);
    if (current == null) return;
    final subs = List<Subscription>.from(current.subscriptions);
    final item = subs.removeAt(oldIndex);
    subs.insert(newIndex, item);
    await storage.saveSubscriptions(subs);
    state = AsyncData(current.copyWith(subscriptions: subs));
  });

  Future<void> reorderGroupConfigs(String? subId, int oldIndex, int newIndex) => _serial(() async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null);
    if (current == null) return;
    final groupConfigs = List<VpnConfig>.from(
      subId == null ? current.standaloneConfigs : (current.configsBySubscription[subId] ?? []),
    );
    final item = groupConfigs.removeAt(oldIndex);
    groupConfigs.insert(newIndex.clamp(0, groupConfigs.length), item);
    final allConfigs = List<VpnConfig>.from(current.configs);
    final firstIdx = allConfigs.indexWhere((c) => c.subscriptionId == subId);
    allConfigs.removeWhere((c) => c.subscriptionId == subId);
    if (firstIdx >= 0) {
      allConfigs.insertAll(firstIdx, groupConfigs);
    } else {
      allConfigs.addAll(groupConfigs);
    }
    await storage.saveConfigs(allConfigs);
    state = AsyncData(current.copyWith(configs: allConfigs));
  });
}

class ImportConnectionsResult {
  final int addedConfigs;
  final int addedSubscriptions;
  final int skippedConfigs;

  const ImportConnectionsResult({
    required this.addedConfigs,
    required this.addedSubscriptions,
    required this.skippedConfigs,
  });
}

final configProvider = AsyncNotifierProvider<ConfigNotifier, ConfigState>(ConfigNotifier.new);

/// The config that will actually be used on connect:
/// best-latency config from the active subscription, or the manually selected config.
final effectiveConfigProvider = Provider<VpnConfig?>((ref) {
  final cs = ref.watch(configProvider).maybeWhen(data: (d) => d, orElse: () => null);
  if (cs == null) return null;
  final subId = cs.activeSubscriptionId;
  if (subId != null) {
    final subConfigs = cs.configs.where((c) => c.subscriptionId == subId).toList();
    if (subConfigs.isNotEmpty) {
      subConfigs.sort((a, b) {
        if (a.latencyMs == null && b.latencyMs == null) return 0;
        if (a.latencyMs == null) return 1;
        if (b.latencyMs == null) return -1;
        return a.latencyMs!.compareTo(b.latencyMs!);
      });
      return subConfigs.first;
    }
  }
  return cs.activeConfig;
});
