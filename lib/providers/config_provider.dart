import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/vpn_config.dart';
import '../core/services/config_storage_service.dart';
import '../core/services/subscription_service.dart' show SubscriptionService, SubscriptionFetchResult, HwidDeviceInfo;
import '../core/services/device_service.dart';
import 'settings_provider.dart';

class ConfigState {
  final List<VpnConfig> configs;
  final String? activeConfigId;
  final List<Subscription> subscriptions;

  const ConfigState({
    this.configs = const [],
    this.activeConfigId,
    this.subscriptions = const [],
  });

  VpnConfig? get activeConfig => activeConfigId == null
      ? null
      : configs.where((c) => c.id == activeConfigId).firstOrNull;

  List<VpnConfig> get standaloneConfigs =>
      configs.where((c) => c.subscriptionId == null).toList();

  Map<String, List<VpnConfig>> get configsBySubscription {
    final result = <String, List<VpnConfig>>{};
    for (final config in configs.where((c) => c.subscriptionId != null)) {
      result.putIfAbsent(config.subscriptionId!, () => []).add(config);
    }
    return result;
  }

  ConfigState copyWith({
    List<VpnConfig>? configs,
    String? activeConfigId,
    bool clearActive = false,
    List<Subscription>? subscriptions,
  }) {
    return ConfigState(
      configs: configs ?? this.configs,
      activeConfigId: clearActive ? null : (activeConfigId ?? this.activeConfigId),
      subscriptions: subscriptions ?? this.subscriptions,
    );
  }
}

class ConfigNotifier extends AsyncNotifier<ConfigState> {
  static final storage = ConfigStorageService();

  @override
  Future<ConfigState> build() async {
    final configs = await storage.loadConfigs();
    final activeId = await storage.loadActiveConfigId();
    final subs = await storage.loadSubscriptions();
    return ConfigState(configs: configs, activeConfigId: activeId, subscriptions: subs);
  }

  Future<void> addConfig(VpnConfig config) async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? const ConfigState();
    final configs = [...current.configs, config];
    await storage.addConfig(config);
    state = AsyncData(current.copyWith(configs: configs));
  }

  Future<void> addConfigs(List<VpnConfig> newConfigs) async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? const ConfigState();
    final configs = [...current.configs, ...newConfigs];
    await storage.addConfigsBatch(newConfigs);
    state = AsyncData(current.copyWith(configs: configs));
  }

  Future<void> removeConfig(String id) async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? const ConfigState();
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
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? const ConfigState();
    // Update in-memory state immediately so connect() reads the right config
    if (id == null) {
      state = AsyncData(current.copyWith(clearActive: true));
    } else {
      state = AsyncData(current.copyWith(activeConfigId: id));
    }
    await storage.saveActiveConfigId(id);
  }

  Future<void> updateConfig(VpnConfig updated) async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? const ConfigState();
    final configs = current.configs
        .map((c) => c.id == updated.id ? updated : c)
        .toList();
    await storage.updateConfig(updated);
    state = AsyncData(current.copyWith(configs: configs));
  }

  // ─── Subscription methods ───

  Future<void> addSubscriptionFromUrl(String url, {String? name, bool allowSelfSigned = false}) async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? const ConfigState();
    final existing = current.subscriptions.where((s) => s.url == url).toList();

    final settingsAsync = ref.read(settingsProvider);
    final settings = settingsAsync.maybeWhen(data: (d) => d, orElse: () => null);
    final hwidEnabled = settings?.hwidEnabled ?? false;
    final hwid = hwidEnabled ? await DeviceService.getHwidInfo() : null;

    String subId;
    List<VpnConfig> newConfigs;

    if (existing.isNotEmpty) {
      // Update existing: remove old configs, add new ones
      subId = existing.first.id;
      final oldConfigs = current.configs.where((c) => c.subscriptionId == subId).toList();
      // Preserve ping results by matching address:port
      final latencyMap = <String, int>{};
      for (final old in oldConfigs) {
        if (old.latencyMs != null) latencyMap['${old.address}:${old.port}'] = old.latencyMs!;
      }
      await storage.removeConfigsBatch(oldConfigs.map((c) => c.id).toList());
      final (tagged, fetchResult) = await _fetchAndTagConfigs(url, subId, allowSelfSigned: allowSelfSigned, hwid: hwid);
      newConfigs = tagged.map((c) {
        final ms = latencyMap['${c.address}:${c.port}'];
        return ms != null ? c.copyWith(latencyMs: ms) : c;
      }).toList();

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

      state = AsyncData(current.copyWith(
        configs: newConfigsList,
        subscriptions: newSubs,
        clearActive: current.activeConfigId != null &&
            !newConfigsList.any((c) => c.id == current.activeConfigId),
      ));
    } else {
      // New subscription
      subId = 'sub_${DateTime.now().millisecondsSinceEpoch}';
      final (tagged, fetchResult) = await _fetchAndTagConfigs(url, subId, allowSelfSigned: allowSelfSigned, hwid: hwid);
      newConfigs = tagged;

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

    // Set first new config as active if none active
    if (state.value?.activeConfigId == null && newConfigs.isNotEmpty) {
      await setActiveConfig(newConfigs.first.id);
    }
  }

  Future<(List<VpnConfig>, SubscriptionFetchResult)> _fetchAndTagConfigs(String url, String subId, {bool allowSelfSigned = false, HwidDeviceInfo? hwid}) async {
    final svc = SubscriptionService();
    final result = await svc.fetchSubscription(url, allowSelfSigned: allowSelfSigned, hwid: hwid);
    final tagged = result.configs.map((c) => c.copyWith(subscriptionId: subId)).toList();
    await storage.addConfigsBatch(tagged);
    return (tagged, result);
  }

  Future<void> renameSubscription(String id, String newName) async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? const ConfigState();
    final sub = current.subscriptions.firstWhere((s) => s.id == id);
    final renamed = sub.copyWith(name: newName);
    await storage.updateSubscription(renamed);
    state = AsyncData(current.copyWith(
      subscriptions: current.subscriptions.map((s) => s.id == id ? renamed : s).toList(),
    ));
  }

  Future<void> removeSubscription(String subId) async {
    final current = state.maybeWhen(data: (d) => d, orElse: () => null) ?? const ConfigState();
    await storage.removeSubscription(subId);
    state = AsyncData(current.copyWith(
      configs: current.configs.where((c) => c.subscriptionId != subId).toList(),
      subscriptions: current.subscriptions.where((s) => s.id != subId).toList(),
      clearActive: current.activeConfigId != null &&
          current.configs.any((c) => c.id == current.activeConfigId && c.subscriptionId == subId),
    ));
  }
}

final configProvider =
    AsyncNotifierProvider<ConfigNotifier, ConfigState>(ConfigNotifier.new);
