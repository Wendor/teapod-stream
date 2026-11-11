import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../core/services/tunnel_socks.dart';
import 'settings_provider.dart';
import 'vpn_provider.dart';

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
      final dir = await _channel.invokeMethod<String>('getFilesDir') ?? '';
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
          lastUpdated: ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : null,
        );
      } else {
        state = GeoMissing();
      }
    } catch (_) {
      state = GeoMissing();
    }
  }

  Future<void> download() async {
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

    // GitHub CDN часто блокируют — при подключённом VPN качаем через туннель (#150).
    Future<void> run(TunnelSocks? socks) async {
      int totalDownloaded = 0;
      int grandTotal = -1;
      try {
        final lenGeoip = await _contentLength(settings.geoipUrl, socks);
        final lenGeosite = await _contentLength(settings.geositeUrl, socks);
        if (lenGeoip > 0 && lenGeosite > 0) grandTotal = lenGeoip + lenGeosite;
      } catch (_) {}
      state = GeoDownloading(downloaded: 0, total: grandTotal);
      for (final (url, name) in [
        (settings.geoipUrl, 'geoip.dat'),
        (settings.geositeUrl, 'geosite.dat'),
      ]) {
        await _downloadFile(
          url: url,
          destPath: '$dir/$name',
          socks: socks,
          onProgress: (bytes) {
            totalDownloaded += bytes;
            state = GeoDownloading(downloaded: totalDownloaded, total: grandTotal);
          },
        );
      }
    }

    try {
      await TunnelSocks.orDirect(ref.read(tunnelSocksProvider), run);
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kLastUpdated, now.millisecondsSinceEpoch);
      state = GeoReady(lastUpdated: now);
    } catch (e) {
      state = GeoError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  static http.Client _client(TunnelSocks? socks) {
    if (socks == null) return http.Client();
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    socks.apply(c);
    return IOClient(c);
  }

  Future<int> _contentLength(String url, TunnelSocks? socks) async {
    final client = _client(socks);
    try {
      final resp = await client.head(Uri.parse(url)).timeout(const Duration(seconds: 15));
      return int.tryParse(resp.headers['content-length'] ?? '') ?? -1;
    } finally {
      client.close();
    }
  }

  Future<void> _downloadFile({
    required String url,
    required String destPath,
    required TunnelSocks? socks,
    required void Function(int bytes) onProgress,
  }) async {
    final tmpPath = '$destPath.tmp';
    final tmpFile = File(tmpPath);
    final destFile = File(destPath);

    final client = _client(socks);
    try {
      final resp = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }

      final sink = tmpFile.openWrite();
      try {
        // Тайм-аут простоя: зависший туннель не должен держать загрузку вечно.
        await for (final chunk in resp.stream.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          onProgress(chunk.length);
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }

    if (destFile.existsSync()) await destFile.delete();
    await tmpFile.rename(destPath);
  }
}

final geoProvider = NotifierProvider<GeoNotifier, GeoState>(GeoNotifier.new);
