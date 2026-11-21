import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_constants.dart';

/// Native calls on `com.teapodstream/vpn` that aren't about the tunnel: binaries and cores, installed apps, files,
/// updates, device identity. The tunnel itself goes through `XrayEngine`. Errors are the channel's
/// (`PlatformException`, `MissingPluginException`): callers keep their own fallbacks.
class PlatformService {
  const PlatformService();

  static const _channel = MethodChannel(AppConstants.methodChannel);

  /// Versions of the bundled binaries by key (`xray`, `tun2socks`, … — see `CoreKind.versionKey`).
  Future<Map<String, String>> binaryVersions() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>('getBinaryVersions');
    return {for (final e in (result ?? const {}).entries) '${e.key}': '${e.value}'};
  }

  /// Native ids (`CoreKind.nativeId`) of the cores whose libraries load on this device.
  Future<List<String>> availableEngines() async =>
      await _channel.invokeListMethod<String>('getAvailableEngines') ?? const <String>[];

  /// Installed apps as maps: `packageName`, `appName`, `isSystem`.
  Future<List<Map<String, dynamic>>> installedApps() async {
    final result = await _channel.invokeMethod<List<Object?>>('getInstalledApps');
    return [for (final item in result ?? const <Object?>[]) Map<String, dynamic>.from(item! as Map)];
  }

  Future<Uint8List?> appIcon(String packageName) =>
      _channel.invokeMethod<Uint8List>('getAppIcon', {'packageName': packageName});

  /// The app's files directory, where the cores read geodata; '' when unknown.
  Future<String> filesDir() async => await _channel.invokeMethod<String>('getFilesDir') ?? '';

  /// Extracts the bundled binaries and fallback geodata into [filesDir].
  Future<void> prepareBinaries() => _channel.invokeMethod<void>('prepareBinaries');

  Future<String?> abi() => _channel.invokeMethod<String>('getAbi');

  Future<void> installApk(String filePath) => _channel.invokeMethod<void>('installApk', {'filePath': filePath});

  Future<String?> deviceId() => _channel.invokeMethod<String>('getDeviceId');

  Future<Map<Object?, Object?>?> deviceInfo() => _channel.invokeMethod<Map<Object?, Object?>>('getDeviceInfo');
}

final platformServiceProvider = Provider<PlatformService>((ref) => const PlatformService());
