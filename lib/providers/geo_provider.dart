import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/geodata_download.dart';
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
      final dir = await _channel.invokeMethod<String>('getGeodataDir') ?? '';
      if (dir.isEmpty) return;
      final geoip = File('$dir/geoip.dat');
      final geosite = File('$dir/geosite.dat');
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
    } catch (e) {
      state = GeoError(
        e is PlatformException ? (e.message ?? 'Ошибка геобаз') : e.toString(),
      );
    }
  }

  Future<void> download() async {
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
