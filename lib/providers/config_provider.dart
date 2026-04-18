import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/vpn_config.dart';
import '../core/services/config_storage_service.dart';
import '../core/services/subscription_service.dart' show SubscriptionService, SubscriptionFetchResult;

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
    for (final c in newConfigs) {
      await storage.addConfig(c);
    }
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
    await storage.saveActiveConfigId(id);
    if (id == null) {
      state = AsyncData(current.copyWith(clearActive: true));
    } else {
      state = AsyncData(current.copyWith(activeConfigId: id));
    }
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

    String subId;
    List<VpnConfig> newConfigs;

    if (existing.isNotEmpty) {
      // Update existing: remove old configs, add new ones
      subId = existing.first.id;
      final oldConfigs = current.configs.where((c) => c.subscriptionId == subId).toList();
      for (final old in oldConfigs) {
        await storage.removeConfig(old.id);
      }
      final (tagged, fetchResult) = await _fetchAndTagConfigs(url, subId, allowSelfSigned: allowSelfSigned);
      newConfigs = tagged;

      final updatedSub = existing.first.copyWith(
        name: name ?? existing.first.name,
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
      final (tagged, fetchResult) = await _fetchAndTagConfigs(url, subId, allowSelfSigned: allowSelfSigned);
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

  Future<(List<VpnConfig>, SubscriptionFetchResult)> _fetchAndTagConfigs(String url, String subId, {bool allowSelfSigned = false}) async {
    final svc = SubscriptionService();
    final result = await svc.fetchSubscription(url, allowSelfSigned: allowSelfSigned);
    final tagged = result.configs.map((c) => VpnConfig(
      id: c.id,
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
      createdAt: c.createdAt,
      rawUri: c.rawUri,
      latencyMs: c.latencyMs,
      subscriptionId: subId,
      ssPrefix: c.ssPrefix,
    )).toList();

    for (final c in tagged) {
      await storage.addConfig(c);
    }
    return (tagged, result);
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
