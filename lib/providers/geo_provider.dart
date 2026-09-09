import '../core/constants/core_features.dart';
import '../core/services/geodata_download.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import 'settings_provider.dart';

sealed class GeoState {}

class GeoMissing extends GeoState {}

class GeoReady extends GeoState {
  final DateTime? lastUpdated;
  GeoReady({this.lastUpdated});
}

class GeoDownloading extends GeoState {
  final int downloaded;
  final int total;
  GeoDownloading({required this.downloaded, required this.total});
}

class GeoError extends GeoState {
  final String message;
  GeoError(this.message);
}

class GeoNotifier extends Notifier<GeoState> {
  static const _kLastUpdated = 'geo_last_updated';
  static const _channel = MethodChannel(AppConstants.methodChannel);

  @override
  GeoState build() {
    Future.microtask(check);
    return GeoMissing();
  }

  Future<void> check() async {
    try {
      final dir =
          await _channel.invokeMethod<String>(
            CoreFeatures.current.isRust ? 'getGeodataDir' : 'getFilesDir',
          ) ??
          '';
      if (dir.isEmpty) return;
      final geoip = File('$dir/geoip.dat');
      final geosite = File('$dir/geosite.dat');
      if (!geoip.existsSync() || !geosite.existsSync()) {
        // Try to extract bundled fallback from assets
        await _channel.invokeMethod('prepareBinaries');
      }
      if (geoip.existsSync() && geosite.existsSync()) {
        final prefs = await SharedPreferences.getInstance();
        final ts = prefs.getInt(_kLastUpdated);
        state = GeoReady(
          lastUpdated: ts != null
              ? DateTime.fromMillisecondsSinceEpoch(ts)
              : null,
        );
      } else {
        state = GeoMissing();
      }
    } catch (_) {
      state = GeoMissing();
    }
  }

  Future<void> download() async {
    if (CoreFeatures.current.isRust) return _downloadRust();
    final settings = await ref.read(settingsProvider.future);
    final String dir;
    try {
      dir = await _channel.invokeMethod<String>('getFilesDir') ?? '';
    } catch (_) {
      state = GeoError('Не удалось получить путь к файлам');
      return;
    }
    if (dir.isEmpty) {
      state = GeoError('Не удалось получить путь к файлам');
      return;
    }

    state = GeoDownloading(downloaded: 0, total: -1);
    int totalDownloaded = 0;
    int grandTotal = -1;

    try {
      final lenGeoip = await _contentLength(settings.geoipUrl);
      final lenGeosite = await _contentLength(settings.geositeUrl);
      if (lenGeoip > 0 && lenGeosite > 0) grandTotal = lenGeoip + lenGeosite;
      state = GeoDownloading(downloaded: 0, total: grandTotal);
    } catch (_) {}

    try {
      for (final (url, name) in [
        (settings.geoipUrl, 'geoip.dat'),
        (settings.geositeUrl, 'geosite.dat'),
      ]) {
        await _downloadFile(
          url: url,
          destPath: '$dir/$name',
          onProgress: (bytes) {
            totalDownloaded += bytes;
            state = GeoDownloading(
              downloaded: totalDownloaded,
              total: grandTotal,
            );
          },
        );
      }
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kLastUpdated, now.millisecondsSinceEpoch);
      state = GeoReady(lastUpdated: now);
    } catch (e) {
      state = GeoError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<int> _contentLength(String url) async {
    final resp = await http.head(Uri.parse(url));
    return int.tryParse(resp.headers['content-length'] ?? '') ?? -1;
  }

  Future<void> _downloadFile({
    required String url,
    required String destPath,
    required void Function(int bytes) onProgress,
  }) async {
    final tmpPath = '$destPath.tmp';
    final tmpFile = File(tmpPath);
    final destFile = File(destPath);

    final req = http.Request('GET', Uri.parse(url));
    final resp = await http.Client().send(req);
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }

    final sink = tmpFile.openWrite();
    try {
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        onProgress(chunk.length);
      }
    } finally {
      await sink.close();
    }

    if (destFile.existsSync()) await destFile.delete();
    await tmpFile.rename(destPath);
  }

  Future<void> _downloadRust() async {
    if (state is GeoDownloading) return;
    final settings = await ref.read(settingsProvider.future);
    final String dir;
    try {
      dir = await _channel.invokeMethod<String>('getFilesDir') ?? '';
    } catch (_) {
      state = GeoError('Не удалось получить путь к файлам');
      return;
    }
    if (dir.isEmpty) {
      state = GeoError('Не удалось получить путь к файлам');
      return;
    }

    state = GeoDownloading(downloaded: 0, total: -1);
    int totalDownloaded = 0;
    try {
      await GeodataDownload.install(
        filesDir: Directory(dir),
        geoipUrl: settings.geoipUrl,
        geositeUrl: settings.geositeUrl,
        activate: (revision) async {
          await _channel.invokeMethod<String>('activateGeodata', {
            'revision': revision,
          });
        },
        onProgress: (bytes) {
          totalDownloaded += bytes;
          state = GeoDownloading(downloaded: totalDownloaded, total: -1);
        },
      );
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kLastUpdated, now.millisecondsSinceEpoch);
      state = GeoReady(lastUpdated: now);
    } catch (e) {
      state = GeoError(e.toString().replaceFirst('Exception: ', ''));
    }
  }
}

final geoProvider = NotifierProvider<GeoNotifier, GeoState>(GeoNotifier.new);
