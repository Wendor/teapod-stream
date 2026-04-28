import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/profile.dart';
import '../services/settings_service.dart';
import 'storage_secure_service.dart';

class ProfileStorageService {
  static const _activeProfileIdKey = 'active_profile_id';
  final _secure = StorageSecureService();

  Future<List<Profile>> loadProfiles() async {
    final raw = await _secure.readProfilesRaw();
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Profile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveProfiles(List<Profile> profiles) async {
    await _secure.writeProfilesRaw(
        jsonEncode(profiles.map((p) => p.toJson()).toList()));
  }

  Future<String> loadActiveProfileId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeProfileIdKey) ?? 'default';
  }

  Future<void> saveActiveProfileId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeProfileIdKey, id);
  }

  Future<void> updateProfileSettings(String id, AppSettings settings) async {
    final profiles = await loadProfiles();
    final idx = profiles.indexWhere((p) => p.id == id);
    if (idx >= 0) {
      profiles[idx] = profiles[idx].copyWith(settings: settings);
      await saveProfiles(profiles);
    }
  }

  Future<void> updateProfileActiveConfig(String profileId, String? configId) async {
    final profiles = await loadProfiles();
    final idx = profiles.indexWhere((p) => p.id == profileId);
    if (idx >= 0) {
      profiles[idx] = configId == null
          ? profiles[idx].copyWith(clearActiveConfig: true)
          : profiles[idx].copyWith(activeConfigId: configId);
      await saveProfiles(profiles);
    }
  }
}
