import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../crypto/sha256.dart';
import '../models/app_message.dart';
import 'app_http.dart';
import 'tunnel_socks.dart';

/// `geoip.dat` / `geosite.dat` in the app's files directory: whether they are there, when they were last downloaded,
/// and the download itself. Both files go to `.tmp` files first and replace the old ones only when both arrived and
/// match the SHA-256 their source publishes next to them (`<url>.sha256sum`, as the default sources do): a failed or
/// mismatched download keeps both old files.
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
  /// reports from then on. Throws on a failed request, or a [ReasonException] on an HTTP status other than 200 or
  /// a file that doesn't match its published checksum.
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
    final tmps = [for (final name in files) File('$dir/$name.tmp')];
    try {
      for (final (i, url) in [geoipUrl, geositeUrl].indexed) {
        final hash = await _downloadFile(url, tmps[i], socks, (bytes) => onProgress(downloaded += bytes, total));
        final published = await _publishedSha256(url, socks);
        if (published != null && published != _hex(hash)) {
          throw ReasonException(AppMessage.l10n((l) => l.geoChecksumMismatch(files[i])));
        }
      }
      for (final (i, name) in files.indexed) {
        await tmps[i].rename('$dir/$name');
      }
    } finally {
      for (final tmp in tmps) {
        if (tmp.existsSync()) await tmp.delete();
      }
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

  /// Writes [url] to [tmp] and returns its SHA-256, hashed as it arrives.
  Future<List<int>> _downloadFile(String url, File tmp, TunnelSocks? socks, void Function(int bytes) onBytes) async {
    // Idle timeout: a stuck tunnel must not hold the download forever.
    final resp = await AppHttp.open(
      Uri.parse(url),
      socks: socks,
      timeout: const Duration(seconds: 30),
      idleTimeout: const Duration(seconds: 30),
      maxBytes: _maxFileBytes,
    );
    final hash = Sha256();
    try {
      final status = resp.statusCode;
      if (status != 200) throw ReasonException(AppMessage.l10n((l) => l.geoHttpStatus(status)));
      final sink = tmp.openWrite();
      try {
        await for (final chunk in resp.body) {
          sink.add(chunk);
          hash.add(chunk);
          onBytes(chunk.length);
        }
      } finally {
        await sink.close();
      }
    } finally {
      resp.close();
    }
    return hash.close();
  }

  /// The SHA-256 (lower-case hex) in `<url>.sha256sum` — `sha256sum` output, the hash first; null when the source
  /// publishes none (404) or the file isn't in that form. Any other HTTP status is an error: the check must not be
  /// skipped because the request failed.
  Future<String?> _publishedSha256(String url, TunnelSocks? socks) async {
    final uri = Uri.parse(url);
    final resp = await AppHttp.open(
      uri.replace(path: '${uri.path}.sha256sum'),
      socks: socks,
      timeout: const Duration(seconds: 30),
      idleTimeout: const Duration(seconds: 30),
      maxBytes: 4096,
    );
    try {
      final status = resp.statusCode;
      if (status == 404) return null;
      if (status != 200) throw ReasonException(AppMessage.l10n((l) => l.geoHttpStatus(status)));
      final text = await utf8.decoder.bind(resp.body).join();
      return RegExp(r'^\s*([0-9a-fA-F]{64})(\s|$)').firstMatch(text)?.group(1)!.toLowerCase();
    } finally {
      resp.close();
    }
  }

  static String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

final geodataServiceProvider = Provider<GeodataService>((ref) => const GeodataService());
