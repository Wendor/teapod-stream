import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/services/app_http.dart';
import '../core/services/tunnel_socks.dart';
import 'settings_provider.dart';
import 'vpn_provider.dart';
import '../l10n/l10n.dart';
import '../core/services/platform_service.dart';

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
  static const _maxFileBytes = 200 * 1024 * 1024;

  @override
  GeoState build() {
    Future.microtask(check);
    return GeoMissing();
  }

  Future<void> check() async {
    try {
      final dir = await ref.read(platformServiceProvider).filesDir();
      if (dir.isEmpty) return;
      final geoip = File('$dir/geoip.dat');
      final geosite = File('$dir/geosite.dat');
      if (!geoip.existsSync() || !geosite.existsSync()) {
        // Try to extract bundled fallback from assets
        await ref.read(platformServiceProvider).prepareBinaries();
      }
      if (geoip.existsSync() && geosite.existsSync()) {
        final prefs = await SharedPreferences.getInstance();
        final ts = prefs.getInt(_kLastUpdated);
        state = GeoReady(lastUpdated: ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : null);
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
      dir = await ref.read(platformServiceProvider).filesDir();
    } catch (_) {
      state = GeoError(L10n.current.geoNoFilesDir);
      return;
    }
    if (dir.isEmpty) {
      state = GeoError(L10n.current.geoNoFilesDir);
      return;
    }

    state = GeoDownloading(downloaded: 0, total: -1);

    // GitHub CDN is often blocked — with the VPN connected we download through the tunnel (#150).
    Future<void> run(TunnelSocks? socks) async {
      int totalDownloaded = 0;
      int grandTotal = -1;
      try {
        final lenGeoip = await _contentLength(settings.geoipUrl, socks);
        final lenGeosite = await _contentLength(settings.geositeUrl, socks);
        if (lenGeoip > 0 && lenGeosite > 0) grandTotal = lenGeoip + lenGeosite;
      } catch (_) {}
      state = GeoDownloading(downloaded: 0, total: grandTotal);
      for (final (url, name) in [(settings.geoipUrl, 'geoip.dat'), (settings.geositeUrl, 'geosite.dat')]) {
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

  Future<int> _contentLength(String url, TunnelSocks? socks) async {
    final resp = await AppHttp.open(Uri.parse(url), method: 'HEAD', socks: socks, maxBytes: _maxFileBytes);
    resp.close();
    return resp.headers.contentLength;
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

    // Idle timeout: a stuck tunnel must not hold the download forever.
    final resp = await AppHttp.open(
      Uri.parse(url),
      socks: socks,
      timeout: const Duration(seconds: 30),
      idleTimeout: const Duration(seconds: 30),
      maxBytes: _maxFileBytes,
    );
    try {
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }

      final sink = tmpFile.openWrite();
      try {
        await for (final chunk in resp.body) {
          sink.add(chunk);
          onProgress(chunk.length);
        }
      } finally {
        await sink.close();
      }
    } finally {
      resp.close();
    }

    if (destFile.existsSync()) await destFile.delete();
    await tmpFile.rename(destPath);
  }
}

final geoProvider = NotifierProvider<GeoNotifier, GeoState>(GeoNotifier.new);
