import 'dart:convert';
import '../models/vpn_config.dart';
import '../models/pinned_ref.dart';
import '../models/subscription.dart';
import 'storage_secure_service.dart';
import 'storage_migration_service.dart';

class ConfigStorageService {
  final _secure = StorageSecureService();

  // ─── Configs ───

  Future<List<VpnConfig>> loadConfigs() async {
    await StorageMigrationService.runIfNeeded();
    final raw = await _secure.readConfigsRaw();
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => VpnConfig.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveConfigs(List<VpnConfig> configs) async {
    await _secure.writeConfigsRaw(jsonEncode(configs.map((c) => c.toJson()).toList()));
  }

  Future<void> addConfig(VpnConfig config) async {
    final configs = await loadConfigs();
    configs.add(config);
    await saveConfigs(configs);
  }

  Future<void> addConfigsBatch(List<VpnConfig> newConfigs) async {
    if (newConfigs.isEmpty) return;
    final configs = await loadConfigs();
    configs.addAll(newConfigs);
    await saveConfigs(configs);
  }

  Future<void> removeConfig(String id) async {
    final configs = await loadConfigs();
    configs.removeWhere((c) => c.id == id);
    await saveConfigs(configs);
  }

  Future<void> removeConfigsBatch(List<String> ids) async {
    if (ids.isEmpty) return;
    final idSet = ids.toSet();
    final configs = await loadConfigs();
    configs.removeWhere((c) => idSet.contains(c.id));
    await saveConfigs(configs);
  }

  Future<void> updateConfig(VpnConfig updated) async {
    final configs = await loadConfigs();
    final idx = configs.indexWhere((c) => c.id == updated.id);
    if (idx >= 0) {
      configs[idx] = updated;
      await saveConfigs(configs);
    }
  }

  Future<String?> loadActiveConfigId() async {
    await StorageMigrationService.runIfNeeded();
    return _secure.readActiveConfigId();
  }

  Future<void> saveActiveConfigId(String? id) async {
    await _secure.writeActiveConfigId(id);
  }

  Future<String?> loadActiveSubscriptionId() async {
    await StorageMigrationService.runIfNeeded();
    return _secure.readActiveSubscriptionId();
  }

  Future<void> saveActiveSubscriptionId(String? id) async {
    await _secure.writeActiveSubscriptionId(id);
  }

  // ─── Subscriptions ───

  Future<List<Subscription>> loadSubscriptions() async {
    await StorageMigrationService.runIfNeeded();
    final raw = await _secure.readSubscriptionsRaw();
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => Subscription.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveSubscriptions(List<Subscription> subs) async {
    await _secure.writeSubscriptionsRaw(jsonEncode(subs.map((s) => s.toJson()).toList()));
  }

  // ─── Pinned refs ───

  Future<List<PinnedRef>> loadPins() async {
    final raw = await _secure.readPinsRaw();
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => PinnedRef.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> savePins(List<PinnedRef> pins) async {
    await _secure.writePinsRaw(jsonEncode(pins.map((p) => p.toJson()).toList()));
  }

  Future<void> addSubscription(Subscription sub) async {
    final subs = await loadSubscriptions();
    subs.add(sub);
    await saveSubscriptions(subs);
  }

  Future<void> updateSubscription(Subscription sub) async {
    final subs = await loadSubscriptions();
    final idx = subs.indexWhere((s) => s.id == sub.id);
    if (idx >= 0) {
      subs[idx] = sub;
      await saveSubscriptions(subs);
    }
  }

  Future<void> removeSubscription(String id) async {
    final subs = await loadSubscriptions();
    subs.removeWhere((s) => s.id == id);
    await saveSubscriptions(subs);
    // Also remove configs that belonged to this subscription
    final configs = await loadConfigs();
    configs.removeWhere((c) => c.subscriptionId == id);
    await saveConfigs(configs);
  }

  /// Find subscription by URL
  Future<Subscription?> findSubscriptionByUrl(String url) async {
    final subs = await loadSubscriptions();
    return subs.where((s) => s.url == url).firstOrNull;
  }

  /// Get configs that belong to a subscription
  Future<List<VpnConfig>> getConfigsForSubscription(String subscriptionId) async {
    final configs = await loadConfigs();
    return configs.where((c) => c.subscriptionId == subscriptionId).toList();
  }

  /// Get configs that are NOT from any subscription
  Future<List<VpnConfig>> getStandaloneConfigs() async {
    final configs = await loadConfigs();
    return configs.where((c) => c.subscriptionId == null).toList();
  }
}
