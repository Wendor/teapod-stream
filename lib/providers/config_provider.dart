import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/vpn_config.dart';
import '../core/models/pinned_ref.dart';
import '../core/models/connections_bundle.dart';
import '../core/services/config_storage_service.dart';
import '../core/services/subscription_service.dart' show SubscriptionService, SubscriptionFetchResult, HwidDeviceInfo;
import '../core/services/device_service.dart';
import '../core/services/log_service.dart';
import 'settings_provider.dart';

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

  VpnConfig? get activeConfig => activeConfigId == null
      ? null
      : configs.where((c) => c.id == activeConfigId).firstOrNull;

  late final List<VpnConfig> standaloneConfigs =
      configs.where((c) => c.subscriptionId == null).toList();

  late final Map<String, List<VpnConfig>> configsBySubscription = () {
    final result = <String, List<VpnConfig>>{};
    for (final config in configs.where((c) => c.subscriptionId != null)) {
      result.putIfAbsent(config.subscriptionId!, () => []).add(config);
    }
    return result;
  }();

  /// Пины в порядке закрепления; null — конфиг с таким именем
  /// в подписке отсутствует (пин «потерян», но не удаляется).
  late final List<(PinnedRef, VpnConfig?)> resolvedPins =
      pins.map((p) => (p, p.resolve(configs))).toList();

  late final Set<String> pinnedIds =
      {for (final (_, c) in resolvedPins) if (c != null) c.id};

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

  /// Мутации выполняются строго по очереди: каждая читает state, ждёт
  /// load-modify-save хранилища и пишет state. Параллельно (пинг посреди
  /// обновления подписки) они перетирали друг друга — на диске оставались
  /// старые конфиги, в памяти новые.
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
    return ConfigState(configs: configs, activeConfigId: activeId, activeSubscriptionId: activeSubId, subscriptions: subs, pins: pins);
  }

  // ─── Pins ───

  Future<void> togglePin(VpnConfig c) => _serial(() async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null);
    if (current == null) return;
    // Снимаем пин, который резолвится в этот конфиг (в т.ч. старого формата).
    final pins = current.isPinned(c)
        ? [for (final (p, r) in current.resolvedPins) if (r?.id != c.id) p]
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

  Future<void> updateConfig(VpnConfig updated) => _serial(() async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? ConfigState();
    final configs = current.configs
        .map((c) => c.id == updated.id ? updated : c)
        .toList();
    await storage.updateConfig(updated);
    state = AsyncData(current.copyWith(configs: configs));
  });

  // ─── Subscription methods ───

  /// [replaceId] — обновить подписку с этим id новым [url] (смена URL):
  /// при ошибке загрузки старая подписка остаётся нетронутой.
  Future<void> addSubscriptionFromUrl(String url,
      {String? name, bool allowSelfSigned = false, String? replaceId}) async {
    bool isTarget(Subscription s) => replaceId != null ? s.id == replaceId : s.url == url;
    final before = state.value ?? ConfigState();
    final target = before.subscriptions.where(isTarget).firstOrNull;
    final subId = target?.id ?? 'sub_${DateTime.now().millisecondsSinceEpoch}';

    final settings = ref.read(settingsProvider).value;
    final hwid = (settings?.hwidEnabled ?? false) ? await DeviceService.getHwidInfo() : null;
    // Сеть — вне очереди мутаций, чтобы выбор конфига не ждал загрузку.
    final (tagged, fetchResult) = await _fetchAndTagConfigs(url, subId,
        allowSelfSigned: allowSelfSigned, pinnedCertDer: target?.pinnedCertDer,
        hwid: hwid, userAgent: settings?.subUserAgent ?? '');
    if (tagged.isEmpty) {
      throw Exception('Subscription returned no valid configurations');
    }

    final newActiveId = await _serial(() async {
      // Состояние перечитывается под очередью: за время загрузки его могли изменить.
      final current = state.value ?? ConfigState();
      final existing = current.subscriptions.where((s) => s.id == subId).firstOrNull;
      final oldConfigs = current.configs.where((c) => c.subscriptionId == subId).toList();

      // Пинг и закреплённое ядро переносим по address:port
      final oldByEndpoint = {for (final c in oldConfigs) '${c.address}:${c.port}': c};
      final newConfigs = tagged.map((c) {
        final old = oldByEndpoint['${c.address}:${c.port}'];
        return old == null ? c : c.copyWith(latencyMs: old.latencyMs, lastPingedAt: old.lastPingedAt, core: old.core);
      }).toList();

      // Парсер выдаёт новые id — переносим выбор: имя+endpoint, затем endpoint,
      // затем имя (имена в подписке не уникальны, напр. «VLESS Server»).
      String? activeId = current.activeConfigId;
      final oldActive = current.activeConfig;
      if (oldActive != null && oldActive.subscriptionId == subId) {
        bool sameEndpoint(VpnConfig c) =>
            c.address == oldActive.address && c.port == oldActive.port;
        activeId = (newConfigs.where((c) => sameEndpoint(c) && c.name == oldActive.name).firstOrNull ??
                newConfigs.where(sameEndpoint).firstOrNull ??
                newConfigs.where((c) => c.name == oldActive.name).firstOrNull)
            ?.id;
      }

      final sub = Subscription(
        id: subId,
        // Пользовательское имя не затирается profile-title при обновлении
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

      state = AsyncData(current.copyWith(
        configs: [...current.configs.where((c) => c.subscriptionId != subId), ...newConfigs],
        subscriptions: existing != null
            ? current.subscriptions.map((s) => s.id == subId ? sub : s).toList()
            : [...current.subscriptions, sub],
        activeConfigId: activeId,
        clearActive: activeId == null,
      ));
      return activeId ?? newConfigs.first.id;
    });

    // Set first new config as active if none active
    if (state.value?.activeConfigId == null) await setActiveConfig(newActiveId);
  }

  Future<(List<VpnConfig>, SubscriptionFetchResult)> _fetchAndTagConfigs(String url, String subId, {bool allowSelfSigned = false, String? pinnedCertDer, HwidDeviceInfo? hwid, String? userAgent}) async {
    final svc = SubscriptionService();
    final result = await svc.fetchSubscription(url,
        allowSelfSigned: allowSelfSigned, pinnedCertDer: pinnedCertDer, hwid: hwid, userAgent: userAgent);
    final tagged = result.configs.map((c) => c.copyWith(subscriptionId: subId)).toList();
    return (tagged, result);
  }

  Future<void> renameSubscription(String id, String newName) => _serial(() async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? ConfigState();
    final sub = current.subscriptions.firstWhere((s) => s.id == id);
    final renamed = sub.copyWith(name: newName);
    await storage.updateSubscription(renamed);
    state = AsyncData(current.copyWith(
      subscriptions: current.subscriptions.map((s) => s.id == id ? renamed : s).toList(),
    ));
  });

  Future<void> removeSubscription(String subId) => _serial(() async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? ConfigState();
    await storage.removeSubscription(subId);
    final clearActiveSub = current.activeSubscriptionId == subId;
    if (clearActiveSub) await storage.saveActiveSubscriptionId(null);
    state = AsyncData(current.copyWith(
      configs: current.configs.where((c) => c.subscriptionId != subId).toList(),
      subscriptions: current.subscriptions.where((s) => s.id != subId).toList(),
      clearActive: current.activeConfigId != null &&
          current.configs.any((c) => c.id == current.activeConfigId && c.subscriptionId == subId),
      clearActiveSub: clearActiveSub,
    ));
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
        // Битая подписка не блокирует остальные и не дёргается на каждом resume.
        final failedAt = _subFailedAt[sub.id];
        if (failedAt != null &&
            DateTime.now().difference(failedAt) < const Duration(hours: 1)) {
          continue;
        }
        try {
          await addSubscriptionFromUrl(sub.url);
          _subFailedAt.remove(sub.id);
        } catch (e) {
          _subFailedAt[sub.id] = DateTime.now();
          ref.read(logServiceProvider.notifier).addError('Автообновление подписки «${sub.name}»: $e');
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

      return c.copyWith(
        id: newId,
        createdAt: DateTime.now(),
        subscriptionId: newSubId,
      );
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

    state = AsyncData(current.copyWith(
      configs: [...current.configs, ...newConfigs],
      subscriptions: updatedSubs,
    ));

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
      // null — сервер не ответил: старое значение стираем, иначе мёртвый
      // сервер со «свежим» пингом выигрывает автовыбор в режиме подписки.
      final ms = latencyByEndpoint[key];
      return c.copyWith(latencyMs: ms, clearLatency: ms == null, lastPingedAt: pingedAt);
    }).toList();
    if (!anyChanged) return;
    await storage.saveConfigs(updated);
    state = AsyncData(current.copyWith(configs: updated));
  });

  // ─── Reorder ───

  Future<void> reorderSubscriptions(int oldIndex, int newIndex) => _serial(() async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null);
    if (current == null) return;
    final subs = List<Subscription>.from(current.subscriptions);
    if (oldIndex < newIndex) newIndex -= 1;
    final item = subs.removeAt(oldIndex);
    subs.insert(newIndex, item);
    await storage.saveSubscriptions(subs);
    state = AsyncData(current.copyWith(subscriptions: subs));
  });

  Future<void> reorderGroupConfigs(String? subId, int oldIndex, int newIndex) => _serial(() async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null);
    if (current == null) return;
    final groupConfigs = List<VpnConfig>.from(
      subId == null
          ? current.standaloneConfigs
          : (current.configsBySubscription[subId] ?? []),
    );
    if (oldIndex < newIndex) newIndex -= 1;
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

final configProvider =
    AsyncNotifierProvider<ConfigNotifier, ConfigState>(ConfigNotifier.new);

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
