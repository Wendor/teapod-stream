import 'dart:convert';
import '../models/vpn_config.dart';
import 'storage_secure_service.dart';
import 'storage_migration_service.dart';

class Subscription {
  final String id;
  final String name;
  final String url;
  final DateTime createdAt;
  final DateTime? lastFetchedAt;
  final DateTime? expireAt;
  final int? uploadBytes;
  final int? downloadBytes;
  final int? totalBytes;
  final String? announce;
  final String? announceUrl;

  const Subscription({
    required this.id,
    required this.name,
    required this.url,
    required this.createdAt,
    this.lastFetchedAt,
    this.expireAt,
    this.uploadBytes,
    this.downloadBytes,
    this.totalBytes,
    this.announce,
    this.announceUrl,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'createdAt': createdAt.toIso8601String(),
        'lastFetchedAt': lastFetchedAt?.toIso8601String(),
        'expireAt': expireAt?.toIso8601String(),
        'uploadBytes': uploadBytes,
        'downloadBytes': downloadBytes,
        'totalBytes': totalBytes,
        'announce': announce,
        'announceUrl': announceUrl,
      };

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
        id: json['id'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        lastFetchedAt: json['lastFetchedAt'] != null
            ? DateTime.parse(json['lastFetchedAt'] as String)
            : null,
        expireAt: json['expireAt'] != null
            ? DateTime.parse(json['expireAt'] as String)
            : null,
        uploadBytes: json['uploadBytes'] as int?,
        downloadBytes: json['downloadBytes'] as int?,
        totalBytes: json['totalBytes'] as int?,
        announce: json['announce'] as String?,
        announceUrl: json['announceUrl'] as String?,
      );

  Subscription copyWith({
    String? name,
    DateTime? lastFetchedAt,
    DateTime? expireAt,
    int? uploadBytes,
    int? downloadBytes,
    int? totalBytes,
    String? announce,
    String? announceUrl,
  }) {
    return Subscription(
      id: id,
      name: name ?? this.name,
      url: url,
      createdAt: createdAt,
      lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
      expireAt: expireAt ?? this.expireAt,
      uploadBytes: uploadBytes ?? this.uploadBytes,
      downloadBytes: downloadBytes ?? this.downloadBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      announce: announce ?? this.announce,
      announceUrl: announceUrl ?? this.announceUrl,
    );
  }
}

class ConfigStorageService {
  final _secure = StorageSecureService();

  // ─── Configs ───

  Future<List<VpnConfig>> loadConfigs() async {
    await StorageMigrationService.runIfNeeded();
    final raw = await _secure.readConfigsRaw();
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => VpnConfig.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveConfigs(List<VpnConfig> configs) async {
    await _secure.writeConfigsRaw(
        jsonEncode(configs.map((c) => c.toJson()).toList()));
  }

  Future<void> addConfig(VpnConfig config) async {
    final configs = await loadConfigs();
    configs.add(config);
    await saveConfigs(configs);
  }

  Future<void> removeConfig(String id) async {
    final configs = await loadConfigs();
    configs.removeWhere((c) => c.id == id);
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

  // ─── Subscriptions ───

  Future<List<Subscription>> loadSubscriptions() async {
    await StorageMigrationService.runIfNeeded();
    final raw = await _secure.readSubscriptionsRaw();
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Subscription.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveSubscriptions(List<Subscription> subs) async {
    await _secure.writeSubscriptionsRaw(
        jsonEncode(subs.map((s) => s.toJson()).toList()));
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
  Future<List<VpnConfig>> getConfigsForSubscription(
      String subscriptionId) async {
    final configs = await loadConfigs();
    return configs.where((c) => c.subscriptionId == subscriptionId).toList();
  }

  /// Get configs that are NOT from any subscription
  Future<List<VpnConfig>> getStandaloneConfigs() async {
    final configs = await loadConfigs();
    return configs.where((c) => c.subscriptionId == null).toList();
  }
}
