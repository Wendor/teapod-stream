import 'dart:convert';
import '../models/vpn_config.dart';
import '../models/pinned_ref.dart';
import '../models/subscription.dart';
import 'storage_secure_service.dart';

/// Whole-list load / save of the stored configs, subscriptions, pins and the selection; `ConfigNotifier._commit`
/// is its only writer.
class ConfigStorageService {
  final _secure = StorageSecureService();

  // ─── Configs ───

  Future<List<VpnConfig>> loadConfigs() async {
    final raw = await _secure.readConfigsRaw();
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => VpnConfig.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveConfigs(List<VpnConfig> configs) async {
    await _secure.writeConfigsRaw(jsonEncode(configs.map((c) => c.toJson()).toList()));
  }

  Future<String?> loadActiveConfigId() async {
    return _secure.readActiveConfigId();
  }

  Future<void> saveActiveConfigId(String? id) async {
    await _secure.writeActiveConfigId(id);
  }

  Future<String?> loadActiveSubscriptionId() async {
    return _secure.readActiveSubscriptionId();
  }

  Future<void> saveActiveSubscriptionId(String? id) async {
    await _secure.writeActiveSubscriptionId(id);
  }

  // ─── Subscriptions ───

  Future<List<Subscription>> loadSubscriptions() async {
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
}
