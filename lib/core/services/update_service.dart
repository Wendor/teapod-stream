import 'dart:io';
import 'dart:convert';
import 'package:socks5_proxy/socks.dart';

enum UpdateChannel { stable, beta }

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final int? totalBytes;
  final String? changelog;

  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    this.totalBytes,
    this.changelog,
  });
}

class DownloadProgress {
  final int downloaded;
  final int total; // -1 if unknown
  final bool done;

  const DownloadProgress({
    required this.downloaded,
    required this.total,
    required this.done,
  });
}

class UpdateService {
  static const _githubApiLatest =
      'https://api.github.com/repos/Wendor/teapod-stream/releases/latest';
  static const _githubApiList =
      'https://api.github.com/repos/Wendor/teapod-stream/releases?per_page=10';

  HttpClient _makeClient({int? socksPort, String? user, String? password}) {
    final client = HttpClient();
    if (socksPort != null && socksPort > 0) {
      SocksTCPClient.assignToHttpClient(client, [
        ProxySettings(
          InternetAddress.loopbackIPv4,
          socksPort,
          username: (user != null && user.isNotEmpty) ? user : null,
          password: (user != null && user.isNotEmpty) ? password : null,
        ),
      ]);
    }
    return client;
  }

  /// Returns null if already up to date or no matching APK asset found.
  /// Pass [socksPort] to route through the active VPN SOCKS5 proxy.
  /// Pass [force] to skip version comparison (for reinstall).
  Future<UpdateInfo?> checkForUpdate(
    String currentVersion,
    String abi, {
    UpdateChannel channel = UpdateChannel.stable,
    int? socksPort,
    String? socksUser,
    String? socksPassword,
    bool force = false,
  }) async {
    final client = _makeClient(
        socksPort: socksPort, user: socksUser, password: socksPassword);
    try {
      final releaseJson = await _fetchRelease(client, channel);
      if (releaseJson == null) return null;
      final tagName = (releaseJson['tag_name'] as String? ?? '')
          .replaceFirst(RegExp(r'^v'), '');
      if (tagName.isEmpty) return null;
      if (!force && _compareVersions(tagName, currentVersion) <= 0) return null;
      final changelog = releaseJson['body'] as String?;
      final assets = releaseJson['assets'] as List<dynamic>? ?? [];
      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        if (name.contains(abi) && name.endsWith('.apk')) {
          final url = asset['browser_download_url'] as String?;
          final size = asset['size'] as int?;
          if (url != null) {
            return UpdateInfo(
              version: tagName,
              downloadUrl: url,
              totalBytes: size,
              changelog: (changelog != null && changelog.trim().isNotEmpty)
                  ? changelog.trim()
                  : null,
            );
          }
        }
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>?> _fetchRelease(
      HttpClient client, UpdateChannel channel) async {
    if (channel == UpdateChannel.stable) {
      final req = await client
          .getUrl(Uri.parse(_githubApiLatest))
          .timeout(const Duration(seconds: 15));
      req.headers.set('User-Agent', 'TeapodStream');
      req.headers.set('Accept', 'application/vnd.github+json');
      final resp = await req.close().timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } else {
      // beta: pick newest non-draft release (prerelease or stable)
      final req = await client
          .getUrl(Uri.parse(_githubApiList))
          .timeout(const Duration(seconds: 15));
      req.headers.set('User-Agent', 'TeapodStream');
      req.headers.set('Accept', 'application/vnd.github+json');
      final resp = await req.close().timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      final releases = jsonDecode(body) as List<dynamic>;
      // GitHub returns releases sorted newest-first; take first non-draft
      for (final r in releases) {
        final release = r as Map<String, dynamic>;
        if (release['draft'] != true) return release;
      }
      return null;
    }
  }

  /// Resumable download. Sends Range header if destPath already has bytes.
  /// Pass [socksPort] to route through the active VPN SOCKS5 proxy.
  Stream<DownloadProgress> downloadApk(
    String url,
    String destPath, {
    int? socksPort,
    String? socksUser,
    String? socksPassword,
  }) async* {
    final file = File(destPath);
    final existing = file.existsSync() ? file.lengthSync() : 0;
    final client = _makeClient(
        socksPort: socksPort, user: socksUser, password: socksPassword);
    IOSink? sink;
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'TeapodStream');
      if (existing > 0) req.headers.set('Range', 'bytes=$existing-');
      final resp = await req.close();
      if (resp.statusCode == 416) {
        yield DownloadProgress(downloaded: existing, total: existing, done: true);
        return;
      }
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final isResume = resp.statusCode == 206;
      if (!isResume && existing > 0) await file.delete();
      final contentLength = resp.headers.contentLength;
      final total = contentLength > 0
          ? (isResume ? existing + contentLength : contentLength)
          : -1;
      sink = file.openWrite(mode: isResume ? FileMode.append : FileMode.write);
      int downloaded = isResume ? existing : 0;
      await for (final chunk in resp) {
        sink.add(chunk);
        downloaded += chunk.length;
        yield DownloadProgress(downloaded: downloaded, total: total, done: false);
      }
      await sink.close();
      sink = null;
      yield DownloadProgress(downloaded: downloaded, total: total, done: true);
    } finally {
      await sink?.close();
      client.close(force: true);
    }
  }

  /// Returns positive if a > b, negative if a < b, 0 if equal.
  int _compareVersions(String a, String b) {
    final ap = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final bp = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final av = i < ap.length ? ap[i] : 0;
      final bv = i < bp.length ? bp[i] : 0;
      if (av != bv) return av - bv;
    }
    return 0;
  }
}
