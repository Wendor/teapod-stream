import 'package:shared_preferences/shared_preferences.dart';
import 'storage_secure_service.dart';

/// One-time migration from plaintext SharedPreferences to EncryptedSharedPreferences.
/// Safe to call on every launch — skips immediately after the first successful run.
class StorageMigrationService {
  static const _flagKey = 'storage_migrated_v2';
  static const _hwidDefaultFlagKey = 'hwid_default_migrated_v1';
  static bool _ranThisSession = false;

  static Future<void> runIfNeeded() async {
    if (_ranThisSession) return;
    _ranThisSession = true;

    final prefs = await SharedPreferences.getInstance();

    // HWID is now on by default: some panels return an HTML redirect instead of
    // the config list when X-Hwid is missing. Drop the stored value once so the
    // new default applies to existing installs.
    if (prefs.getBool(_hwidDefaultFlagKey) != true) {
      await prefs.remove('hwid_enabled');
      await prefs.setBool(_hwidDefaultFlagKey, true);
    }

    if (prefs.getBool(_flagKey) == true) return;

    final secure = StorageSecureService();

    try {
      // VPN configs: List<String> (each element is a JSON object) → single JSON array
      final rawConfigs = prefs.getStringList('vpn_configs') ?? [];
      if (rawConfigs.isNotEmpty) {
        await secure.writeConfigsRaw('[${rawConfigs.join(',')}]');
      }

      // Active config ID
      final activeId = prefs.getString('active_config_id');
      if (activeId != null) {
        await secure.writeActiveConfigId(activeId);
      }

      // Subscriptions: same format as configs
      final rawSubs = prefs.getStringList('subscriptions') ?? [];
      if (rawSubs.isNotEmpty) {
        await secure.writeSubscriptionsRaw('[${rawSubs.join(',')}]');
      }

      // SOCKS credentials
      final socksUser = prefs.getString('socks_user') ?? '';
      final socksPass = prefs.getString('socks_password') ?? '';
      if (socksUser.isNotEmpty || socksPass.isNotEmpty) {
        await secure.writeSocksCredentials(socksUser, socksPass);
      }

      // Mark complete and remove plaintext keys
      await prefs.setBool(_flagKey, true);
      for (final key in ['vpn_configs', 'active_config_id', 'subscriptions',
                          'socks_user', 'socks_password']) {
        await prefs.remove(key);
      }
    } catch (_) {
      // On Keystore failure — do NOT set the flag so migration retries next launch.
      // Old plaintext data remains intact as fallback.
    }
  }
}
