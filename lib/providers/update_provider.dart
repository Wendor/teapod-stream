import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../core/services/update_service.dart';
import '../core/constants/app_constants.dart';
import 'vpn_provider.dart';

sealed class UpdateState {}

class UpdateIdle extends UpdateState {}

class UpdateChecking extends UpdateState {}

class UpdateUpToDate extends UpdateState {}

class UpdateAvailable extends UpdateState {
  final UpdateInfo info;
  final int resumableBytes;
  UpdateAvailable(this.info, {this.resumableBytes = 0});
}

class UpdateDownloading extends UpdateState {
  final UpdateInfo info;
  final int downloaded;
  final int total;
  UpdateDownloading(this.info, {required this.downloaded, required this.total});
}

class UpdateDownloaded extends UpdateState {
  final UpdateInfo info;
  final String filePath;
  UpdateDownloaded(this.info, this.filePath);
}

class UpdateError extends UpdateState {
  final String message;
  final UpdateInfo? retryInfo;
  UpdateError(this.message, {this.retryInfo});
}

class UpdateNotifier extends Notifier<UpdateState> {
  final _service = UpdateService();
  StreamSubscription<DownloadProgress>? _dlSub;
  String? _currentApkPath;

  static const _channel = MethodChannel(AppConstants.methodChannel);

  @override
  UpdateState build() {
    ref.onDispose(() => _dlSub?.cancel());
    return UpdateIdle();
  }

  Future<void> checkForUpdate() async {
    state = UpdateChecking();
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;
      final abi =
          await _channel.invokeMethod<String>('getAbi') ?? 'arm64-v8a';
      final vpn = ref.read(vpnProvider);
      final update = await _service.checkForUpdate(
        currentVersion,
        abi,
        socksPort: vpn.isConnected ? vpn.activeSocksPort : null,
        socksUser: vpn.activeSocksUser,
        socksPassword: vpn.activeSocksPassword,
      );
      if (update == null) {
        state = UpdateUpToDate();
        Future.delayed(const Duration(seconds: 3), () {
          if (state is UpdateUpToDate) state = UpdateIdle();
        });
      } else {
        final path = await _apkPath(update.version, abi);
        final resumable = File(path).existsSync() ? File(path).lengthSync() : 0;
        state = UpdateAvailable(update, resumableBytes: resumable);
      }
    } catch (e) {
      state = UpdateError('Ошибка проверки: $e');
    }
  }

  Future<void> startDownload(UpdateInfo info) async {
    final abi = await _channel.invokeMethod<String>('getAbi') ?? 'arm64-v8a';
    final path = await _apkPath(info.version, abi);
    _currentApkPath = path;

    state = UpdateDownloading(info,
        downloaded: File(path).existsSync() ? File(path).lengthSync() : 0,
        total: info.totalBytes ?? -1);

    final vpn = ref.read(vpnProvider);
    _dlSub = _service.downloadApk(
      info.downloadUrl,
      path,
      socksPort: vpn.isConnected ? vpn.activeSocksPort : null,
      socksUser: vpn.activeSocksUser,
      socksPassword: vpn.activeSocksPassword,
    ).listen(
      (progress) {
        if (progress.done) {
          state = UpdateDownloaded(info, path);
          _dlSub = null;
        } else {
          state = UpdateDownloading(info,
              downloaded: progress.downloaded, total: progress.total);
        }
      },
      onError: (e) {
        state = UpdateError('Ошибка загрузки: $e', retryInfo: info);
        _dlSub = null;
      },
    );
  }

  Future<void> cancelDownload() async {
    await _dlSub?.cancel();
    _dlSub = null;
    final cur = state;
    if (cur is UpdateDownloading) {
      final path = _currentApkPath;
      final resumable =
          path != null && File(path).existsSync() ? File(path).lengthSync() : 0;
      state = UpdateAvailable(cur.info, resumableBytes: resumable);
    }
  }

  Future<void> installApk(String filePath) async {
    try {
      await _channel.invokeMethod<void>('installApk', {'filePath': filePath});
    } on PlatformException catch (e) {
      state = UpdateError(e.message ?? 'Ошибка установки');
    }
  }

  Future<String> _apkPath(String version, String abi) async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/teapod-update-$abi-$version.apk';
  }
}

final updateProvider =
    NotifierProvider<UpdateNotifier, UpdateState>(UpdateNotifier.new);
