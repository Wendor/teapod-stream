import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../crypto/sha256.dart';
import '../models/app_message.dart';
import 'app_http.dart';
import 'tunnel_socks.dart';

/// A source without published checksums (a custom URL) served files the user hasn't trusted: the first download from
/// it, or a file that differs from the one trusted before ([changed]). Nothing was installed. [sha256ByUrl] — the
/// SHA-256 of each such file; a download with them as `trusted` installs exactly these files.
class GeodataNeedsTrust implements Exception {
  final Map<String, String> sha256ByUrl;
  final bool changed;

  const GeodataNeedsTrust(this.sha256ByUrl, {required this.changed});

  @override
  String toString() => 'GeodataNeedsTrust(${sha256ByUrl.keys.join(', ')}, changed: $changed)';
}

/// `geoip.dat` / `geosite.dat` in the app's files directory: whether they are there, when they were last downloaded,
/// and the download itself. Both files go to `.tmp` files first and replace the old ones only when both arrived and
/// each is verified: it matches the SHA-256 its source publishes next to it (`<url>.sha256sum`, as the default sources
/// do), or — for a source that publishes none — the SHA-256 the user trusted for that URL (the pin, kept per URL).
/// A failed, mismatched or untrusted download, or a failed rename, keeps both old files.
class GeodataService {
  const GeodataService();

  static const files = ['geoip.dat', 'geosite.dat'];
  static const _kLastUpdated = 'geo_last_updated';
  static const _kPins = 'geo_pins';
  static const _maxFileBytes = 200 * 1024 * 1024;

  /// Both files are in [dir].
  bool present(String dir) => files.every((name) => File('$dir/$name').existsSync());

  /// When [download] last finished; null — never (the bundled copy).
  Future<DateTime?> lastUpdated() async {
    final ts = (await SharedPreferences.getInstance()).getInt(_kLastUpdated);
    return ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts);
  }

  /// The SHA-256 the user trusted per URL of a source without published checksums.
  Future<Map<String, String>> pins() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kPins);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as String));
    } on Object {
      return {};
    }
  }

  /// Downloads [geoipUrl] and [geositeUrl] into [dir] through [socks] (direct when null). [onProgress] gets the bytes
  /// so far and the total from the HEAD sizes (-1 — unknown). A file without a published checksum is installed when
  /// it matches the pin of its URL or its hash in [trusted] (which then becomes the pin). Returns the time it
  /// finished, which [lastUpdated] reports from then on. Throws on a failed request, a [ReasonException] on an HTTP
  /// status other than 200 or a file that doesn't match its published checksum, or [GeodataNeedsTrust].
  Future<DateTime> download({
    required String dir,
    required String geoipUrl,
    required String geositeUrl,
    required TunnelSocks? socks,
    required void Function(int downloaded, int total) onProgress,
    Map<String, String> trusted = const {},
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
    final pins = await this.pins();
    final newPins = <String, String>{};
    final untrusted = <String, String>{};
    final shown = <String, String>{};
    try {
      for (final (i, url) in [geoipUrl, geositeUrl].indexed) {
        final hash = _hex(await _downloadFile(url, tmps[i], socks, (bytes) => onProgress(downloaded += bytes, total)));
        final published = await _publishedSha256(url, socks);
        if (published != null) {
          if (published != hash) throw ReasonException(AppMessage.l10n((l) => l.geoChecksumMismatch(files[i])));
        } else if (pins[url] == hash) {
          newPins[url] = hash;
        } else if (trusted[url] == hash) {
          newPins[url] = hash;
          shown[url] = hash;
        } else {
          untrusted[url] = hash;
        }
      }
      // A file trusted just now but not installed (the other one changed) is asked about again with it: trusting only
      // the changed one would leave this one without a pin, and the two would be asked about in turn forever.
      if (untrusted.isNotEmpty) {
        throw GeodataNeedsTrust({...shown, ...untrusted}, changed: untrusted.keys.any(pins.containsKey));
      }
      await _install(dir, tmps);
    } finally {
      for (final tmp in tmps) {
        if (tmp.existsSync()) await tmp.delete();
      }
    }
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastUpdated, now.millisecondsSinceEpoch);
    if (newPins.isNotEmpty) await prefs.setString(_kPins, jsonEncode({...pins, ...newPins}));
    return now;
  }

  /// Renames [tmps] over [files] in [dir]: both or neither. The old files are copied to `.bak` first (a copy, not a
  /// move: the files stay in place for a core starting meanwhile) and put back when a rename fails.
  static Future<void> _install(String dir, List<File> tmps) async {
    final backups = <String, File>{};
    try {
      for (final name in files) {
        final old = File('$dir/$name');
        if (old.existsSync()) backups['$dir/$name'] = await old.copy('$dir/$name.bak');
      }
      for (final (i, name) in files.indexed) {
        await tmps[i].rename('$dir/$name');
      }
    } catch (_) {
      // A backup that can't be put back stays as `.bak` rather than being lost; the next install overwrites it.
      for (final MapEntry(key: path, value: backup) in backups.entries) {
        try {
          await backup.rename(path);
        } catch (_) {}
      }
      rethrow;
    }
    // Installed: a backup left behind is only a stray file, overwritten by the next install.
    for (final backup in backups.values) {
      try {
        await backup.delete();
      } catch (_) {}
    }
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
  /// publishes none (404, whatever the size of its error page) or the file doesn't start that way (only its first
  /// bytes are read, as ASCII). Any other HTTP status is an error: the check must not be skipped because the request
  /// failed.
  Future<String?> _publishedSha256(String url, TunnelSocks? socks) async {
    final uri = Uri.parse(url);
    final resp = await AppHttp.open(
      uri.replace(path: '${uri.path}.sha256sum'),
      socks: socks,
      timeout: const Duration(seconds: 30),
      idleTimeout: const Duration(seconds: 30),
      // No size limit before the status: a 404 page of any declared size means "no sum". Of a 200 body only
      // [_sumPrefix] bytes are ever read.
      maxBytes: 1 << 62,
    );
    try {
      final status = resp.statusCode;
      if (status == 404) return null;
      if (status != 200) throw ReasonException(AppMessage.l10n((l) => l.geoHttpStatus(status)));
      final head = <int>[];
      await for (final chunk in resp.body) {
        head.addAll(chunk);
        if (head.length >= _sumPrefix) break;
      }
      final text = String.fromCharCodes(head.take(_sumPrefix));
      return RegExp(r'^\s*([0-9a-fA-F]{64})(\s|$)').firstMatch(text)?.group(1)!.toLowerCase();
    } finally {
      resp.close();
    }
  }

  /// Enough of a `.sha256sum` file for the hash and the separator after it.
  static const _sumPrefix = 256;

  static String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

final geodataServiceProvider = Provider<GeodataService>((ref) => const GeodataService());
