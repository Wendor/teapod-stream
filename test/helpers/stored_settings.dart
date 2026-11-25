import 'package:teapodstream/core/models/app_settings.dart';
import 'package:teapodstream/core/services/profile_storage_service.dart';

/// The settings in force as stored: the active profile's.
Future<AppSettings> storedSettings() async {
  final storage = ProfileStorageService();
  final activeId = await storage.loadActiveProfileId();
  return (await storage.loadProfiles()).firstWhere((p) => p.id == activeId).settings;
}
