import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/vpn_config.dart';
import '../core/models/pinned_ref.dart';
import '../core/models/network_rule.dart';
import '../core/models/connections_bundle.dart';
import '../core/services/config_storage_service.dart';
import '../core/services/subscription_service.dart' show SubscriptionService, SubscriptionFetchResult, HwidDeviceInfo;
import '../core/services/device_service.dart';
import 'settings_provider.dart';

class ConfigState {
  final List<VpnConfig> configs;
  final String? activeConfigId;
  final String? activeSubscriptionId;
  final List<Subscription> subscriptions;
  final List<PinnedRef> pins;

  /// Правила «сеть → конфиг»; не более одного на каждый [NetTransport].
  final List<NetworkRule> networkRules;

  ConfigState({
    this.configs = const [],
    this.activeConfigId,
    this.activeSubscriptionId,
    this.subscriptions = const [],
    this.pins = const [],
    this.networkRules = const [],
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
  late final List<(PinnedRef, VpnConfig?)> resolvedPins = pins
      .map((p) => (p, configs.where(p.matches).firstOrNull))
      .toList();

  bool isPinned(VpnConfig c) => pins.any((p) => p.matches(c));

  /// Конфиг, назначенный на [transport]; null — правила нет либо конфиг
  /// с таким именем исчез из подписки.
  VpnConfig? configForTransport(NetTransport transport) {
    final rule =
        networkRules.where((r) => r.transport == transport).firstOrNull;
    if (rule == null) return null;
    return configs.where(rule.matches).firstOrNull;
  }

  /// Транспорты, на которые назначен конфиг (для бейджей в списке).
  Set<NetTransport> transportsFor(VpnConfig c) => networkRules
      .where((r) => r.matches(c))
      .map((r) => r.transport)
      .toSet();

  ConfigState copyWith({
    List<VpnConfig>? configs,
    String? activeConfigId,
    bool clearActive = false,
    String? activeSubscriptionId,
    bool clearActiveSub = false,
    List<Subscription>? subscriptions,
    List<PinnedRef>? pins,
    List<NetworkRule>? networkRules,
  }) {
    return ConfigState(
      configs: configs ?? this.configs,
      activeConfigId: clearActive ? null : (activeConfigId ?? this.activeConfigId),
      activeSubscriptionId: clearActiveSub ? null : (activeSubscriptionId ?? this.activeSubscriptionId),
      subscriptions: subscriptions ?? this.subscriptions,
      pins: pins ?? this.pins,
      networkRules: networkRules ?? this.networkRules,
    );
  }
}

class ConfigNotifier extends AsyncNotifier<ConfigState> {
  static final storage = ConfigStorageService();

  @override
  Future<ConfigState> build() async {
    final configs = await storage.loadConfigs();
    final activeId = await storage.loadActiveConfigId();
    final activeSubId = await storage.loadActiveSubscriptionId();
    final subs = await storage.loadSubscriptions();
    final pins = await storage.loadPins();
    final rules = await storage.loadNetworkRules();
    return ConfigState(configs: configs, activeConfigId: activeId, activeSubscriptionId: activeSubId, subscriptions: subs, pins: pins, networkRules: rules);
  }

  // ─── Network rules ───

  /// Назначает [c] на [transport]; повторный вызов для уже назначенного
  /// конфига снимает правило. Правило на транспорт всегда одно.
  Future<void> toggleNetworkRule(VpnConfig c, NetTransport transport) async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null);
    if (current == null) return;
    final rule = NetworkRule(
      transport: transport,
      subscriptionId: c.subscriptionId,
      name: c.name,
    );
    final rules = current.networkRules
        .where((r) => r.transport != transport)
        .toList();
    if (!current.networkRules.contains(rule)) rules.add(rule);
    await storage.saveNetworkRules(rules);
    state = AsyncData(current.copyWith(networkRules: rules));
  }

  // ─── Pins ───

  Future<void> togglePin(VpnConfig c) async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null);
    if (current == null) return;
    final pin = PinnedRef(subscriptionId: c.subscriptionId, name: c.name);
    final pins = List<PinnedRef>.from(current.pins);
    if (!pins.remove(pin)) pins.add(pin);
    await storage.savePins(pins);
    state = AsyncData(current.copyWith(pins: pins));
  }

  Future<void> unpin(PinnedRef pin) async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null);
    if (current == null) return;
    final pins = current.pins.where((p) => p != pin).toList();
    await storage.savePins(pins);
    state = AsyncData(current.copyWith(pins: pins));
  }

  Future<void> addConfig(VpnConfig config) async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? ConfigState();
    final configs = [...current.configs, config];
    await storage.addConfig(config);
    state = AsyncData(current.copyWith(configs: configs));
  }

  Future<void> addConfigs(List<VpnConfig> newConfigs) async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? ConfigState();
    final configs = [...current.configs, ...newConfigs];
    await storage.addConfigsBatch(newConfigs);
    state = AsyncData(current.copyWith(configs: configs));
  }

  Future<void> removeConfig(String id) async {
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
  }

  Future<void> setActiveConfig(String? id) async {
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

  Future<void> setActiveSubscription(String? id) async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? ConfigState();
    state = AsyncData(current.copyWith(activeSubscriptionId: id, clearActiveSub: id == null));
    await storage.saveActiveSubscriptionId(id);
  }

  Future<void> updateConfig(VpnConfig updated) async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? ConfigState();
    final configs = current.configs
        .map((c) => c.id == updated.id ? updated : c)
        .toList();
    await storage.updateConfig(updated);
    state = AsyncData(current.copyWith(configs: configs));
  }

  // ─── Subscription methods ───

  Future<void> addSubscriptionFromUrl(String url, {String? name, bool allowSelfSigned = false}) async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? ConfigState();
    final existing = current.subscriptions.where((s) => s.url == url).toList();

    final settingsAsync = ref.read(settingsProvider);
    final settings = settingsAsync.maybeWhen(data: (d) => d, orElse: () => null);
    final hwidEnabled = settings?.hwidEnabled ?? false;
    final hwid = hwidEnabled ? await DeviceService.getHwidInfo() : null;
    final userAgent = settings?.subUserAgent ?? '';

    String subId;
    List<VpnConfig> newConfigs;

    if (existing.isNotEmpty) {
      // Update existing: remove old configs, add new ones
      subId = existing.first.id;
      final oldConfigs = current.configs.where((c) => c.subscriptionId == subId).toList();
      // Configs are recreated with fresh ids on every refresh, so the active
      // selection is remembered by name (same idea as PinnedRef) and restored below.
      final activeName = oldConfigs
          .where((c) => c.id == current.activeConfigId)
          .firstOrNull
          ?.name;
      // Preserve ping results by matching address:port
      final latencyMap = <String, int>{};
      final pingTimeMap = <String, DateTime>{};
      for (final old in oldConfigs) {
        final key = '${old.address}:${old.port}';
        if (old.latencyMs != null) latencyMap[key] = old.latencyMs!;
        if (old.lastPingedAt != null) pingTimeMap[key] = old.lastPingedAt!;
      }
      final (tagged, fetchResult) = await _fetchAndTagConfigs(url, subId, allowSelfSigned: allowSelfSigned, hwid: hwid, userAgent: userAgent);
      if (tagged.isEmpty) {
        throw Exception('Subscription returned no valid configurations');
      }
      // Remove old first, then add new — prevents duplicates if interrupted mid-update
      await storage.removeConfigsBatch(oldConfigs.map((c) => c.id).toList());
      newConfigs = tagged.map((c) {
        final key = '${c.address}:${c.port}';
        final ms = latencyMap[key];
        final pingedAt = pingTimeMap[key];
        return (ms != null || pingedAt != null)
            ? c.copyWith(latencyMs: ms, lastPingedAt: pingedAt)
            : c;
      }).toList();
      await storage.addConfigsBatch(newConfigs);

      final updatedSub = Subscription(
        id: subId,
        name: name ?? fetchResult.profileTitle ?? existing.first.name,
        url: existing.first.url,
        createdAt: existing.first.createdAt,
        lastFetchedAt: DateTime.now(),
        expireAt: fetchResult.expireAt,
        uploadBytes: fetchResult.uploadBytes,
        downloadBytes: fetchResult.downloadBytes,
        totalBytes: fetchResult.totalBytes,
        announce: fetchResult.announce,
        announceUrl: fetchResult.announceUrl,
      );
      await storage.updateSubscription(updatedSub);

      final newConfigsList = [
        ...current.configs.where((c) => c.subscriptionId != subId),
        ...newConfigs,
      ];
      final newSubs = current.subscriptions
          .map((s) => s.id == subId ? updatedSub : s)
          .toList();

      final restoredActiveId = activeName == null
          ? null
          : newConfigs.where((c) => c.name == activeName).firstOrNull?.id;
      if (restoredActiveId != null) {
        await storage.saveActiveConfigId(restoredActiveId);
      }

      state = AsyncData(current.copyWith(
        configs: newConfigsList,
        subscriptions: newSubs,
        activeConfigId: restoredActiveId,
        clearActive: restoredActiveId == null &&
            current.activeConfigId != null &&
            !newConfigsList.any((c) => c.id == current.activeConfigId),
      ));
    } else {
      // New subscription
      subId = 'sub_${DateTime.now().millisecondsSinceEpoch}';
      final (tagged, fetchResult) = await _fetchAndTagConfigs(url, subId, allowSelfSigned: allowSelfSigned, hwid: hwid, userAgent: userAgent);
      if (tagged.isEmpty) {
        throw Exception('Subscription returned no valid configurations');
      }
      newConfigs = tagged;
      await storage.addConfigsBatch(newConfigs);

      final sub = Subscription(
        id: subId,
        name: name ?? fetchResult.profileTitle ?? Uri.parse(url).host,
        url: url,
        createdAt: DateTime.now(),
        lastFetchedAt: DateTime.now(),
        expireAt: fetchResult.expireAt,
        uploadBytes: fetchResult.uploadBytes,
        downloadBytes: fetchResult.downloadBytes,
        totalBytes: fetchResult.totalBytes,
        announce: fetchResult.announce,
        announceUrl: fetchResult.announceUrl,
      );
      await storage.addSubscription(sub);

      state = AsyncData(current.copyWith(
        configs: [...current.configs, ...newConfigs],
        subscriptions: [...current.subscriptions, sub],
      ));
    }

    // Set first new config as active if nothing is selected. In subscription
    // mode the config is picked automatically, so don't drop that mode here.
    if (state.value?.activeConfigId == null &&
        state.value?.activeSubscriptionId == null &&
        newConfigs.isNotEmpty) {
      await setActiveConfig(newConfigs.first.id);
    }
  }

  Future<(List<VpnConfig>, SubscriptionFetchResult)> _fetchAndTagConfigs(String url, String subId, {bool allowSelfSigned = false, HwidDeviceInfo? hwid, String? userAgent}) async {
    final svc = SubscriptionService();
    final result = await svc.fetchSubscription(url, allowSelfSigned: allowSelfSigned, hwid: hwid, userAgent: userAgent);
    final tagged = result.configs.map((c) => c.copyWith(subscriptionId: subId)).toList();
    return (tagged, result);
  }

  Future<void> renameSubscription(String id, String newName) async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? ConfigState();
    final sub = current.subscriptions.firstWhere((s) => s.id == id);
    final renamed = sub.copyWith(name: newName);
    await storage.updateSubscription(renamed);
    state = AsyncData(current.copyWith(
      subscriptions: current.subscriptions.map((s) => s.id == id ? renamed : s).toList(),
    ));
  }

  Future<void> removeSubscription(String subId) async {
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
  }

  Future<void> refreshStaleSubscriptions({int intervalHours = 6}) async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null);
    if (current == null || current.subscriptions.isEmpty) return;
    final threshold = Duration(hours: intervalHours);
    final stale = current.subscriptions.where((s) {
      if (s.lastFetchedAt == null) return true;
      return DateTime.now().difference(s.lastFetchedAt!) > threshold;
    }).toList();
    for (final sub in stale) {
      await addSubscriptionFromUrl(sub.url);
    }
  }

  // ─── Import from ConnectionsBundle ───

  Future<ImportConnectionsResult> importBundle(ConnectionsBundle bundle) async {
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

      return VpnConfig(
        id: newId,
        name: c.name,
        protocol: c.protocol,
        address: c.address,
        port: c.port,
        uuid: c.uuid,
        security: c.security,
        transport: c.transport,
        sni: c.sni,
        wsPath: c.wsPath,
        wsHost: c.wsHost,
        grpcServiceName: c.grpcServiceName,
        fingerprint: c.fingerprint,
        publicKey: c.publicKey,
        shortId: c.shortId,
        spiderX: c.spiderX,
        postQuantumKey: c.postQuantumKey,
        flow: c.flow,
        encryption: c.encryption,
        alterId: c.alterId,
        method: c.method,
        password: c.password,
        createdAt: DateTime.now(),
        rawUri: c.rawUri,
        latencyMs: c.latencyMs,
        subscriptionId: newSubId,
        ssPrefix: c.ssPrefix,
        obfsPassword: c.obfsPassword,
        xhttpMode: c.xhttpMode,
        xhttpExtra: c.xhttpExtra,
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
      await setActiveConfig(newConfigs.first.id);
    }

    return ImportConnectionsResult(
      addedConfigs: addedConfigs,
      addedSubscriptions: addedSubscriptions,
      skippedConfigs: remappedConfigs.length - newConfigs.length,
    );
  }

  Future<void> batchUpdatePingResults(Map<String, int?> latencyByEndpoint, DateTime pingedAt) async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null);
    if (current == null) return;
    var anyChanged = false;
    final updated = current.configs.map((c) {
      final key = '${c.address}:${c.port}';
      if (!latencyByEndpoint.containsKey(key)) return c;
      anyChanged = true;
      return c.copyWith(latencyMs: latencyByEndpoint[key], lastPingedAt: pingedAt);
    }).toList();
    if (!anyChanged) return;
    await storage.saveConfigs(updated);
    state = AsyncData(current.copyWith(configs: updated));
  }

  // ─── Reorder ───

  Future<void> reorderSubscriptions(int oldIndex, int newIndex) async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null);
    if (current == null) return;
    final subs = List<Subscription>.from(current.subscriptions);
    if (oldIndex < newIndex) newIndex -= 1;
    final item = subs.removeAt(oldIndex);
    subs.insert(newIndex, item);
    await storage.saveSubscriptions(subs);
    state = AsyncData(current.copyWith(subscriptions: subs));
  }

  Future<void> reorderGroupConfigs(String? subId, int oldIndex, int newIndex) async {
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
  }
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
        if (a.latencyMs == null) return 1;
        if (b.latencyMs == null) return -1;
        return a.latencyMs!.compareTo(b.latencyMs!);
      });
      return subConfigs.first;
    }
  }
  return cs.activeConfig;
});
