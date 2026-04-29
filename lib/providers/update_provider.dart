import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../core/services/update_service.dart';
import '../core/constants/app_constants.dart';
import 'vpn_provider.dart';
import 'settings_provider.dart';

sealed class UpdateState {}

class UpdateIdle extends UpdateState {}

class UpdateChecking extends UpdateState {}

class UpdateUpToDate extends UpdateState {
  final UpdateInfo info;
  UpdateUpToDate(this.info);
}

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
      final pkgInfo = await PackageInfo.fromPlatform();
      final currentVersion = pkgInfo.version;
      final abi = await _channel.invokeMethod<String>('getAbi') ?? 'arm64-v8a';
      final vpn = ref.read(vpnProvider);
      final settings = ref.read(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null);
      final channel = settings?.updateChannel ?? UpdateChannel.stable;
      final update = await _service.checkForUpdate(
        currentVersion,
        abi,
        channel: channel,
        socksPort: vpn.isConnected ? vpn.activeSocksPort : null,
        socksUser: vpn.activeSocksUser,
        socksPassword: vpn.activeSocksPassword,
        force: true,
      );
      if (update == null) {
        state = UpdateError('Не удалось получить данные о релизе');
        return;
      }
      final path = await _apkPath(update.version, abi);
      await _cleanOldApks(keepPath: path);
      if (_isNewer(update.version, currentVersion)) {
        final resumable = File(path).existsSync() ? File(path).lengthSync() : 0;
        state = UpdateAvailable(update, resumableBytes: resumable);
      } else {
        state = UpdateUpToDate(update);
      }
    } catch (e) {
      state = UpdateError('Ошибка проверки: $e');
    }
  }

  Future<void> reinstall(UpdateInfo info) async {
    final abi = await _channel.invokeMethod<String>('getAbi') ?? 'arm64-v8a';
    final path = await _apkPath(info.version, abi);
    if (File(path).existsSync()) await File(path).delete();
    await startDownload(info);
  }

  Future<void> startDownload(UpdateInfo info) async {
    final abi = await _channel.invokeMethod<String>('getAbi') ?? 'arm64-v8a';
    final path = await _apkPath(info.version, abi);
    _currentApkPath = path;

    state = UpdateDownloading(info,
        downloaded: File(path).existsSync() ? File(path).lengthSync() : 0,
        total: info.totalBytes ?? -1);

    _dlSub = _service.downloadApk(
      info.downloadUrl,
      path,
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
      await _cleanOldApks(keepPath: filePath);
      state = UpdateIdle();
    } on PlatformException catch (e) {
      state = UpdateError(e.message ?? 'Ошибка установки');
    }
  }

  bool _isNewer(String a, String b) {
    final ap = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final bp = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final av = i < ap.length ? ap[i] : 0;
      final bv = i < bp.length ? bp[i] : 0;
      if (av != bv) return av > bv;
    }
    return false;
  }

  Future<String> _apkPath(String version, String abi) async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/teapod-update-$abi-$version.apk';
  }

  Future<void> _cleanOldApks({String? keepPath}) async {
    final dir = await getApplicationSupportDirectory();
    for (final f in dir.listSync().whereType<File>()) {
      if (f.path.contains('teapod-update-') && f.path.endsWith('.apk')) {
        if (keepPath == null || f.path != keepPath) {
          await f.delete();
        }
      }
    }
  }
}

final updateProvider =
    NotifierProvider<UpdateNotifier, UpdateState>(UpdateNotifier.new);
