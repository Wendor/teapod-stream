import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/vpn_config.dart';
import '../core/models/pinned_ref.dart';
import '../core/models/config_selection.dart';
import '../core/models/connections_bundle.dart';
import '../core/models/import_review.dart';
import '../core/services/config_storage_service.dart';
import '../core/models/subscription.dart';
import '../core/services/subscription_service.dart'
    show subscriptionServiceProvider, SubscriptionFetchResult, HwidDeviceInfo;
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

  // ─── Transitions: pure, the notifier commits their result ───

  /// Without config [id]; the selection is cleared when it was the active one.
  ConfigState withoutConfig(String id) =>
      copyWith(configs: configs.where((c) => c.id != id).toList(), clearActive: activeConfigId == id);

  /// Without subscription [subId], its configs and its pins; the selection and the subscription mode are cleared
  /// when they pointed into it. A selection that resolves to nothing is cleared too.
  ConfigState withoutSubscription(String subId) => copyWith(
    configs: configs.where((c) => c.subscriptionId != subId).toList(),
    subscriptions: subscriptions.where((s) => s.id != subId).toList(),
    pins: pins.where((p) => p.subscriptionId != subId).toList(),
    clearActive: activeConfig == null || activeConfig?.subscriptionId == subId,
    clearActiveSub: activeSubscriptionId == subId,
  );

  /// [sub] (added, or replacing the one with its id) with its freshly fetched [fetched] configs in place of the old
  /// ones. Carried over from the old configs: the ping by endpoint (`address:port`), the pinned core by name+endpoint
  /// or by an endpoint unique in the subscription, and the selection by name+endpoint → endpoint → name (the parser
  /// issues new ids; names in a subscription aren't unique). No active config, or it vanished (also an id that
  /// resolves to nothing) — the first fetched one; the subscription mode is left as it is. [fetched] is not empty.
  ConfigState withSubscription(Subscription sub, List<VpnConfig> fetched) {
    final subId = sub.id;
    final oldByEndpoint = <String, List<VpnConfig>>{};
    for (final c in configs.where((c) => c.subscriptionId == subId)) {
      (oldByEndpoint['${c.address}:${c.port}'] ??= []).add(c);
    }
    final merged = [
      for (final c in fetched)
        if (oldByEndpoint['${c.address}:${c.port}'] case final olds?)
          () {
            final same = olds.where((o) => o.name == c.name).firstOrNull ?? (olds.length == 1 ? olds.first : null);
            final ping = same ?? olds.last;
            return c.copyWith(latencyMs: ping.latencyMs, lastPingedAt: ping.lastPingedAt, core: same?.core);
          }()
        else
          c,
    ];

    final oldActive = activeConfig;
    // An id that resolves to no config (a commit that failed before saving the selection) counts as none.
    var activeId = oldActive?.id;
    if (oldActive != null && oldActive.subscriptionId == subId) {
      bool sameEndpoint(VpnConfig c) => c.address == oldActive.address && c.port == oldActive.port;
      activeId =
          (merged.where((c) => sameEndpoint(c) && c.name == oldActive.name).firstOrNull ??
                  merged.where(sameEndpoint).firstOrNull ??
                  merged.where((c) => c.name == oldActive.name).firstOrNull)
              ?.id;
    }
    activeId ??= merged.first.id;

    final known = subscriptions.any((s) => s.id == subId);
    return copyWith(
      configs: [...configs.where((c) => c.subscriptionId != subId), ...merged],
      subscriptions: known ? [for (final s in subscriptions) s.id == subId ? sub : s] : [...subscriptions, sub],
      activeConfigId: activeId,
    );
  }
}

class ConfigNotifier extends AsyncNotifier<ConfigState> {
  ConfigStorageService get _storage => ref.read(configStorageServiceProvider);

  /// Mutations run strictly in order: each reads the state, computes the next one and commits it. Run in parallel (a
  /// ping in the middle of a subscription refresh) they overwrote each other.
  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// The state once [build] has finished: a mutation never starts from a state the finishing [build] would
  /// overwrite. A failed load throws here (also while Riverpod retries it), so nothing is written over stored data
  /// that couldn't be read.
  Future<ConfigState> _loaded() async {
    final s = state;
    if (s.hasValue) return s.requireValue;
    if (s.hasError) Error.throwWithStackTrace(s.error!, s.stackTrace ?? StackTrace.current);
    return future;
  }

  /// Persists what differs between [from] and [next] — whole lists, one write per changed list or id — and publishes
  /// what was written: all of [next], or after a failed write the parts saved before it, so the next mutation starts
  /// from what storage holds. The only writer of the stored state.
  Future<void> _commit(ConfigState from, ConfigState next) async {
    var saved = from;
    Future<void> saveSubscriptions() async {
      if (identical(next.subscriptions, from.subscriptions)) return;
      await _storage.saveSubscriptions(next.subscriptions);
      saved = saved.copyWith(subscriptions: next.subscriptions);
    }

    Future<void> saveConfigs() async {
      if (identical(next.configs, from.configs)) return;
      await _storage.saveConfigs(next.configs);
      saved = saved.copyWith(configs: next.configs);
    }

    try {
      // A failure between the two writes must not leave configs pointing to a subscription that isn't stored, nor a
      // refresh time without the refreshed configs: a new subscription is saved before its configs, otherwise the
      // configs go first (a removed subscription's configs before it, a refresh's configs before its fetch time).
      final addsSubscription = next.subscriptions.any((s) => !from.subscriptions.any((o) => o.id == s.id));
      if (addsSubscription) {
        await saveSubscriptions();
        await saveConfigs();
      } else {
        await saveConfigs();
        await saveSubscriptions();
      }
      if (!identical(next.pins, from.pins)) {
        await _storage.savePins(next.pins);
        saved = saved.copyWith(pins: next.pins);
      }
      if (next.activeConfigId != from.activeConfigId) {
        await _storage.saveActiveConfigId(next.activeConfigId);
        saved = saved.copyWith(activeConfigId: next.activeConfigId, clearActive: next.activeConfigId == null);
      }
      if (next.activeSubscriptionId != from.activeSubscriptionId) {
        await _storage.saveActiveSubscriptionId(next.activeSubscriptionId);
      }
      saved = next;
    } finally {
      state = AsyncData(saved);
    }
  }

  /// Queues a mutation: [next] maps the current state to the next one (null — nothing to change).
  Future<void> _mutate(ConfigState? Function(ConfigState current) next) => _serial(() async {
    final current = await _loaded();
    final updated = next(current);
    if (updated != null) await _commit(current, updated);
  });

  @override
  Future<ConfigState> build() async {
    final configs = await _storage.loadConfigs();
    final activeId = await _storage.loadActiveConfigId();
    final activeSubId = await _storage.loadActiveSubscriptionId();
    final subs = await _storage.loadSubscriptions();
    final pins = await _storage.loadPins();
    return ConfigState(
      configs: configs,
      activeConfigId: activeId,
      activeSubscriptionId: activeSubId,
      subscriptions: subs,
      pins: pins,
    );
  }

  // ─── Pins ───

  /// Pins [c], or removes the pin that resolves to it (including the old format).
  Future<void> togglePin(VpnConfig c) => _mutate(
    (s) => s.copyWith(
      pins: s.isPinned(c)
          ? [
              for (final (p, r) in s.resolvedPins)
                if (r?.id != c.id) p,
            ]
          : [...s.pins, PinnedRef.of(c)],
    ),
  );

  Future<void> unpin(PinnedRef pin) => _mutate((s) => s.copyWith(pins: s.pins.where((p) => p != pin).toList()));

  // ─── Configs ───

  Future<void> addConfig(VpnConfig config) => addConfigs([config]);

  Future<void> addConfigs(List<VpnConfig> newConfigs) =>
      _mutate((s) => newConfigs.isEmpty ? null : s.copyWith(configs: [...s.configs, ...newConfigs]));

  Future<void> removeConfig(String id) => _mutate((s) => s.withoutConfig(id));

  Future<void> updateConfig(VpnConfig updated) =>
      _mutate((s) => s.copyWith(configs: [for (final c in s.configs) c.id == updated.id ? updated : c]));

  /// Selecting a specific config (or none) leaves the subscription mode.
  Future<void> setActiveConfig(String? id) =>
      _mutate((s) => s.copyWith(activeConfigId: id, clearActive: id == null, clearActiveSub: true));

  Future<void> setActiveSubscription(String? id) =>
      _mutate((s) => s.copyWith(activeSubscriptionId: id, clearActiveSub: id == null));

  /// The selection after every mutation queued so far.
  Future<ConfigSelection> currentSelection() => _serial(() async => (await _loaded()).selection);

  /// Restores a selection remembered by a profile. Whatever no longer exists is skipped;
  /// when nothing of it is left, the current selection stays.
  Future<void> applySelection(ConfigSelection selection) => _mutate((s) {
    final config = selection.resolve(s.configs);
    final subId = s.subscriptions.any((sub) => sub.id == selection.subscriptionId) ? selection.subscriptionId : null;
    if (config == null && subId == null) return null;
    return s.copyWith(activeConfigId: config?.id, activeSubscriptionId: subId, clearActiveSub: subId == null);
  });

  // ─── Subscription methods ───

  /// [replaceId] — update the subscription with this id to the new [url] (URL change):
  /// on a load error the old subscription stays untouched. [pinnedCertDer] — the certificate the user has just
  /// accepted (`UntrustedCertificateException.der`); otherwise the subscription's stored pin applies.
  Future<void> addSubscriptionFromUrl(String url, {String? name, String? pinnedCertDer, String? replaceId}) async {
    bool isTarget(Subscription s) => replaceId != null ? s.id == replaceId : s.url == url;
    final before = await _loaded();
    final target = before.subscriptions.where(isTarget).firstOrNull;
    // The subscription to replace is gone already: nothing to update, and the URL must not match another one.
    if (replaceId != null && target == null) return;
    final subId = target?.id ?? 'sub_${DateTime.now().millisecondsSinceEpoch}';

    final settings = ref.read(settingsProvider).value;
    final host = Uri.parse(url).host;
    // A subscription that registered the raw id keeps it while its host stays the same.
    final rawHwid = target != null && target.rawHwid && Uri.parse(target.url).host == host;
    final device = (settings?.hwidEnabled ?? false) ? await ref.read(deviceServiceProvider).getHwidInfo() : null;
    final hwid = rawHwid ? device : device?.forHost(host);
    // Network — outside the mutation queue so config selection doesn't wait for the download.
    final (tagged, fetchResult) = await _fetchAndTagConfigs(
      url,
      subId,
      pinnedCertDer: pinnedCertDer ?? target?.pinnedCertDer,
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

    // The state is read again in the queue: it could have changed during the download. A subscription removed
    // meanwhile stays removed; a new URL added meanwhile (another add, an import) is updated, not duplicated.
    await _mutate((s) {
      final existing = target != null
          ? s.subscriptions.where((sub) => sub.id == subId).firstOrNull
          : s.subscriptions.where((sub) => sub.url == url).firstOrNull;
      if (target != null && existing == null) return null;
      // A subscription that registered the raw id got this URL meanwhile: it is fetched with that id, not this one.
      if (target == null && existing != null && existing.rawHwid != rawHwid) return null;
      final id = existing?.id ?? subId;
      final now = DateTime.now();
      final sub = Subscription(
        id: id,
        // A user-given name isn't overwritten by profile-title on refresh
        name: name ?? existing?.name ?? fetchResult.profileTitle ?? host,
        url: url,
        createdAt: existing?.createdAt ?? now,
        lastFetchedAt: now,
        expireAt: fetchResult.expireAt,
        uploadBytes: fetchResult.uploadBytes,
        downloadBytes: fetchResult.downloadBytes,
        totalBytes: fetchResult.totalBytes,
        announce: fetchResult.announce,
        announceUrl: fetchResult.announceUrl,
        pinnedCertDer: fetchResult.acceptedCertDer ?? existing?.pinnedCertDer,
        rawHwid: rawHwid,
      );
      return s.withSubscription(sub, id == subId ? tagged : [for (final c in tagged) c.copyWith(subscriptionId: id)]);
    });
  }

  Future<(List<VpnConfig>, SubscriptionFetchResult)> _fetchAndTagConfigs(
    String url,
    String subId, {
    String? pinnedCertDer,
    HwidDeviceInfo? hwid,
    String? userAgent,
  }) async {
    final svc = ref.read(subscriptionServiceProvider);
    final result = await svc.fetchSubscription(
      url,
      pinnedCertDer: pinnedCertDer,
      hwid: hwid,
      userAgent: userAgent,
      socks: ref.read(tunnelSocksProvider),
    );
    final tagged = result.configs.map((c) => c.copyWith(subscriptionId: subId)).toList();
    return (tagged, result);
  }

  Future<void> renameSubscription(String id, String newName) => _mutate(
    (s) => s.copyWith(
      subscriptions: [for (final sub in s.subscriptions) sub.id == id ? sub.copyWith(name: newName) : sub],
    ),
  );

  Future<void> removeSubscription(String subId) => _mutate((s) => s.withoutSubscription(subId));

  /// Refreshes the stale subscriptions when auto-refresh is on: at startup and on resume, after the VPN state sync —
  /// before it a VPN started from the tile isn't known yet, and the download would bypass the tunnel.
  /// The settings and the configs may still be loading at startup: it waits for both.
  Future<void> refreshStaleIfDue() async {
    final settings = await ref.read(settingsProvider.future);
    if (!ref.mounted || !settings.subAutoRefresh) return;
    await future;
    if (!ref.mounted) return;
    await refreshStaleSubscriptions(intervalHours: settings.subAutoRefreshHours);
  }

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

  /// Hosts of the subscriptions among [urls] that an import would add (one already present is skipped).
  List<String> newSubscriptionHosts(Iterable<String> urls) =>
      ImportReview.newHosts(urls, (state.value?.subscriptions ?? const <Subscription>[]).map((s) => s.url));

  /// What importing [bundle] adds that the user sees before it is applied: the subscription hosts.
  ImportReview reviewBundle(ConnectionsBundle bundle) => ImportReview(
    subscriptionHosts: newSubscriptionHosts([...bundle.subscriptions.map((s) => s.url), ...bundle.subscriptionUrls]),
  );

  /// Imports [bundle]: subscriptions not present yet (by URL) get new ids, configs not present yet (by share link,
  /// else `address:port`) get new ids and their subscription remapped; with no active config the first imported one
  /// is selected. One commit.
  Future<ImportConnectionsResult> importBundle(ConnectionsBundle bundle) => _serial(() async {
    final current = await _loaded();
    final now = DateTime.now();
    final ts = now.millisecondsSinceEpoch;

    final subIdMap = <String, String>{};
    final newSubscriptions = <Subscription>[];
    for (final sub in bundle.subscriptions) {
      final existing = current.subscriptions.where((s) => s.url == sub.url).firstOrNull;
      if (existing != null) {
        subIdMap[sub.id] = existing.id;
        continue;
      }
      final newSub = Subscription(
        id: 'sub_import_${ts}_${newSubscriptions.length}',
        name: sub.name,
        url: sub.url,
        createdAt: now,
        lastFetchedAt: sub.lastFetchedAt,
        expireAt: sub.expireAt,
        uploadBytes: sub.uploadBytes,
        downloadBytes: sub.downloadBytes,
        totalBytes: sub.totalBytes,
        announce: sub.announce,
        announceUrl: sub.announceUrl,
      );
      subIdMap[sub.id] = newSub.id;
      newSubscriptions.add(newSub);
    }

    String key(VpnConfig c) => c.rawUri ?? '${c.address}:${c.port}';
    final existingKeys = current.configs.map(key).toSet();
    final remapped = [
      for (final (i, c) in bundle.configs.indexed)
        c.copyWith(
          id: 'cfg_import_${ts}_${i}_${c.id.hashCode}',
          createdAt: now,
          subscriptionId: subIdMap[c.subscriptionId] ?? c.subscriptionId,
        ),
    ];
    final newConfigs = remapped.where((c) => !existingKeys.contains(key(c))).toList();

    var next = current;
    if (newSubscriptions.isNotEmpty) next = next.copyWith(subscriptions: [...next.subscriptions, ...newSubscriptions]);
    if (newConfigs.isNotEmpty) {
      next = next.copyWith(configs: [...next.configs, ...newConfigs]);
      // Selecting a config leaves the subscription mode, as setActiveConfig does.
      // An id that resolves to nothing counts as no selection.
      if (next.activeConfig == null) next = next.copyWith(activeConfigId: newConfigs.first.id, clearActiveSub: true);
    }
    if (!identical(next, current)) await _commit(current, next);

    return ImportConnectionsResult(
      addedConfigs: newConfigs.length,
      addedSubscriptions: newSubscriptions.length,
      skippedConfigs: remapped.length - newConfigs.length,
    );
  });

  /// Ping results by `address:port`; null — the server didn't answer: the old value is cleared, otherwise a dead
  /// server with a "fresh" ping wins auto-select in subscription mode.
  Future<void> batchUpdatePingResults(Map<String, int?> latencyByEndpoint, DateTime pingedAt) => _mutate((s) {
    if (!s.configs.any((c) => latencyByEndpoint.containsKey('${c.address}:${c.port}'))) return null;
    return s.copyWith(
      configs: [
        for (final c in s.configs)
          if (latencyByEndpoint.containsKey('${c.address}:${c.port}'))
            c.copyWith(
              latencyMs: latencyByEndpoint['${c.address}:${c.port}'],
              clearLatency: latencyByEndpoint['${c.address}:${c.port}'] == null,
              lastPingedAt: pingedAt,
            )
          else
            c,
      ],
    );
  });

  // ─── Reorder ───
  // `newIndex` is the item's index after the move, as `ReorderableListView.onReorderItem` reports it.

  Future<void> reorderSubscriptions(int oldIndex, int newIndex) => _mutate((s) {
    final subs = List<Subscription>.from(s.subscriptions);
    subs.insert(newIndex, subs.removeAt(oldIndex));
    return s.copyWith(subscriptions: subs);
  });

  Future<void> reorderGroupConfigs(String? subId, int oldIndex, int newIndex) => _mutate((s) {
    final groupConfigs = List<VpnConfig>.from(
      subId == null ? s.standaloneConfigs : (s.configsBySubscription[subId] ?? []),
    );
    final item = groupConfigs.removeAt(oldIndex);
    groupConfigs.insert(newIndex.clamp(0, groupConfigs.length), item);
    final allConfigs = List<VpnConfig>.from(s.configs);
    final firstIdx = allConfigs.indexWhere((c) => c.subscriptionId == subId);
    allConfigs.removeWhere((c) => c.subscriptionId == subId);
    if (firstIdx >= 0) {
      allConfigs.insertAll(firstIdx, groupConfigs);
    } else {
      allConfigs.addAll(groupConfigs);
    }
    return s.copyWith(configs: allConfigs);
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
