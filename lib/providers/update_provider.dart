import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../core/models/app_settings.dart' show UpdateChannel;
import '../core/services/update_service.dart';
import '../core/constants/app_constants.dart';
import 'vpn_provider.dart';
import 'settings_provider.dart';
import '../core/models/app_message.dart';
import '../core/services/platform_service.dart';

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
  final AppMessage message;
  final UpdateInfo? retryInfo;
  UpdateError(this.message, {this.retryInfo});
}

class UpdateNotifier extends Notifier<UpdateState> {
  UpdateService get _service => ref.read(updateServiceProvider);
  StreamSubscription<DownloadProgress>? _dlSub;
  String? _currentApkPath;

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
      final abi = await ref.read(platformServiceProvider).abi() ?? 'arm64-v8a';
      if (!AppConstants.supportedAbis.contains(abi)) {
        state = UpdateError(AppMessage(MessageCode.updateUnsupportedDevice, abi));
        return;
      }
      final settings = ref.read(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null);
      final channel = settings?.updateChannel ?? UpdateChannel.stable;
      final update = await _service.checkForUpdate(
        currentVersion,
        abi,
        channel: channel,
        socks: ref.read(vpnProvider).tunnelSocks,
        force: true,
      );
      if (update == null) {
        state = UpdateError(const AppMessage(MessageCode.updateNoReleaseInfo));
        return;
      }
      final path = await _service.apkPath(update.version, abi);
      await _service.cleanOldApks(keepPath: path);
      if (_isNewer(update.version, currentVersion)) {
        state = UpdateAvailable(update, resumableBytes: _service.downloadedBytes(path));
      } else {
        state = UpdateUpToDate(update);
      }
    } catch (e) {
      state = UpdateError(AppMessage(MessageCode.updateCheckError, '$e'));
    }
  }

  Future<void> reinstall(UpdateInfo info) async {
    final abi = await ref.read(platformServiceProvider).abi() ?? 'arm64-v8a';
    await _service.deleteApk(await _service.apkPath(info.version, abi));
    await startDownload(info);
  }

  Future<void> startDownload(UpdateInfo info) async {
    final abi = await ref.read(platformServiceProvider).abi() ?? 'arm64-v8a';
    final path = await _service.apkPath(info.version, abi);
    _currentApkPath = path;

    state = UpdateDownloading(info, downloaded: _service.downloadedBytes(path), total: info.totalBytes ?? -1);

    // Like the release check — through the tunnel if it is up (#150).
    final socks = ref.read(vpnProvider).tunnelSocks;
    _dlSub = _service
        .downloadApk(info.downloadUrl, path, socks: socks)
        .listen(
          (progress) {
            if (progress.done) {
              state = UpdateDownloaded(info, path);
              _dlSub = null;
            } else {
              state = UpdateDownloading(info, downloaded: progress.downloaded, total: progress.total);
            }
          },
          onError: (Object e) {
            state = UpdateError(AppMessage(MessageCode.updateDownloadError, '$e'), retryInfo: info);
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
      state = UpdateAvailable(cur.info, resumableBytes: path == null ? 0 : _service.downloadedBytes(path));
    }
  }

  Future<void> installApk(String filePath) async {
    try {
      await ref.read(platformServiceProvider).installApk(filePath);
      await _service.cleanOldApks(keepPath: filePath);
      state = UpdateIdle();
    } on PlatformException catch (e) {
      state = UpdateError(
        e.message != null ? AppMessage.text(e.message!) : const AppMessage(MessageCode.updateInstallError),
      );
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
}

final updateProvider = NotifierProvider<UpdateNotifier, UpdateState>(UpdateNotifier.new);
