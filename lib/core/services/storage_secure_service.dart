import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure key-value storage backed by Android Keystore (EncryptedSharedPreferences).
/// Stores raw JSON strings — callers handle parsing.
class StorageSecureService {
  static const _opts = AndroidOptions(encryptedSharedPreferences: true);

  final _storage = const FlutterSecureStorage(aOptions: _opts);

  static const _configsKey = 'vpn_configs_v2';
  static const _activeConfigKey = 'active_config_id_v2';
  static const _subscriptionsKey = 'subscriptions_v2';
  static const _socksUserKey = 'socks_user_v2';
  static const _socksPasswordKey = 'socks_password_v2';
  static const _deviceIdKey = 'device_id_v2';
  static const _deviceInfoKey = 'device_info_v2';

  Future<String?> readConfigsRaw() => _storage.read(key: _configsKey);
  Future<void> writeConfigsRaw(String json) =>
      _storage.write(key: _configsKey, value: json);

  Future<String?> readActiveConfigId() => _storage.read(key: _activeConfigKey);
  Future<void> writeActiveConfigId(String? id) => id == null
      ? _storage.delete(key: _activeConfigKey)
      : _storage.write(key: _activeConfigKey, value: id);

  Future<String?> readSubscriptionsRaw() =>
      _storage.read(key: _subscriptionsKey);
  Future<void> writeSubscriptionsRaw(String json) =>
      _storage.write(key: _subscriptionsKey, value: json);

  Future<({String user, String password})> readSocksCredentials() async {
    final user = await _storage.read(key: _socksUserKey) ?? '';
    final pass = await _storage.read(key: _socksPasswordKey) ?? '';
    return (user: user, password: pass);
  }

  Future<void> writeSocksCredentials(String user, String password) async {
    await _storage.write(key: _socksUserKey, value: user);
    await _storage.write(key: _socksPasswordKey, value: password);
  }

  Future<String?> readDeviceId() => _storage.read(key: _deviceIdKey);
  Future<void> writeDeviceId(String? id) => id == null
      ? _storage.delete(key: _deviceIdKey)
      : _storage.write(key: _deviceIdKey, value: id);

  Future<String?> readDeviceInfoRaw() => _storage.read(key: _deviceInfoKey);
  Future<void> writeDeviceInfoRaw(String json) =>
      _storage.write(key: _deviceInfoKey, value: json);
}
