import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_http.dart';
import 'tunnel_socks.dart';

/// `geoip.dat` / `geosite.dat` in the app's files directory: whether they are there, when they were last downloaded,
/// and the download itself (to a `.tmp` file, then renamed over the old one, so a failed download keeps it).
class GeodataService {
  const GeodataService();

  static const files = ['geoip.dat', 'geosite.dat'];
  static const _kLastUpdated = 'geo_last_updated';
  static const _maxFileBytes = 200 * 1024 * 1024;

  /// Both files are in [dir].
  bool present(String dir) => files.every((name) => File('$dir/$name').existsSync());

  /// When [download] last finished; null — never (the bundled copy).
  Future<DateTime?> lastUpdated() async {
    final ts = (await SharedPreferences.getInstance()).getInt(_kLastUpdated);
    return ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts);
  }

  /// Downloads [geoipUrl] and [geositeUrl] into [dir] through [socks] (direct when null). [onProgress] gets the bytes
  /// so far and the total from the HEAD sizes (-1 — unknown). Returns the time it finished, which [lastUpdated]
  /// reports from then on. Throws on a failed request or an HTTP status other than 200.
  Future<DateTime> download({
    required String dir,
    required String geoipUrl,
    required String geositeUrl,
    required TunnelSocks? socks,
    required void Function(int downloaded, int total) onProgress,
  }) async {
    var total = -1;
    try {
      final lenGeoip = await _contentLength(geoipUrl, socks);
      final lenGeosite = await _contentLength(geositeUrl, socks);
      if (lenGeoip > 0 && lenGeosite > 0) total = lenGeoip + lenGeosite;
    } catch (_) {}
    var downloaded = 0;
    onProgress(0, total);
    for (final (url, name) in [(geoipUrl, files[0]), (geositeUrl, files[1])]) {
      await _downloadFile(url, '$dir/$name', socks, (bytes) => onProgress(downloaded += bytes, total));
    }
    final now = DateTime.now();
    await (await SharedPreferences.getInstance()).setInt(_kLastUpdated, now.millisecondsSinceEpoch);
    return now;
  }

  Future<int> _contentLength(String url, TunnelSocks? socks) async {
    final resp = await AppHttp.open(Uri.parse(url), method: 'HEAD', socks: socks, maxBytes: _maxFileBytes);
    resp.close();
    return resp.headers.contentLength;
  }

  Future<void> _downloadFile(String url, String destPath, TunnelSocks? socks, void Function(int bytes) onBytes) async {
    final tmpFile = File('$destPath.tmp');
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
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      final sink = tmpFile.openWrite();
      try {
        await for (final chunk in resp.body) {
          sink.add(chunk);
          onBytes(chunk.length);
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

final geodataServiceProvider = Provider<GeodataService>((ref) => const GeodataService());
