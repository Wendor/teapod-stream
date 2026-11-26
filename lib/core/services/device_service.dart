import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'platform_service.dart';
import 'storage_secure_service.dart';
import 'subscription_service.dart';

class DeviceService {
  DeviceService(this._platform);

  final PlatformService _platform;
  static const _storage = FlutterSecureStorage(aOptions: StorageSecureService.androidOptions);
  static const _deviceIdKey = 'cached_device_id';
  static const _deviceInfoKey = 'cached_device_info';

  String? _cachedDeviceId;
  Map<String, dynamic>? _cachedDeviceInfo;

  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    final cached = await _storage.read(key: _deviceIdKey);
    if (cached != null) {
      _cachedDeviceId = cached;
      return cached;
    }

    try {
      final deviceId = await _platform.deviceId();
      if (deviceId != null) {
        _cachedDeviceId = deviceId;
        await _storage.write(key: _deviceIdKey, value: deviceId);
        return deviceId;
      }
    } catch (_) {}
    return '';
  }

  Future<Map<String, dynamic>> getDeviceInfo() async {
    if (_cachedDeviceInfo != null) return _cachedDeviceInfo!;

    final cachedJson = await _storage.read(key: _deviceInfoKey);
    if (cachedJson != null) {
      try {
        _cachedDeviceInfo = jsonDecode(cachedJson) as Map<String, dynamic>;
        return _cachedDeviceInfo!;
      } catch (_) {}
    }

    try {
      final result = await _platform.deviceInfo();
      if (result != null) {
        _cachedDeviceInfo = Map<String, dynamic>.from(result);
        await _storage.write(key: _deviceInfoKey, value: jsonEncode(_cachedDeviceInfo));
        return _cachedDeviceInfo!;
      }
    } catch (_) {}
    return {'model': 'Unknown', 'osVersion': 0};
  }

  Future<HwidDeviceInfo?> getHwidInfo() async {
    final deviceId = await getDeviceId();
    if (deviceId.isEmpty) return null;

    final info = await getDeviceInfo();
    return HwidDeviceInfo(
      deviceId: deviceId,
      deviceModel: info['model'] as String? ?? 'Unknown',
      osVersion: info['osVersion'] as int? ?? 0,
    );
  }

  Future<void> clearCache() async {
    _cachedDeviceId = null;
    _cachedDeviceInfo = null;
    await _storage.delete(key: _deviceIdKey);
    await _storage.delete(key: _deviceInfoKey);
  }
}

final deviceServiceProvider = Provider<DeviceService>((ref) => DeviceService(ref.watch(platformServiceProvider)));
