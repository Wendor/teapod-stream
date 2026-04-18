import 'dart:io';
import 'dart:convert';
import 'package:socks5_proxy/socks.dart';

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final int? totalBytes;

  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    this.totalBytes,
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
  static const _githubApi =
      'https://api.github.com/repos/Wendor/teapod-stream/releases/latest';

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
  Future<UpdateInfo?> checkForUpdate(
    String currentVersion,
    String abi, {
    int? socksPort,
    String? socksUser,
    String? socksPassword,
  }) async {
    final client = _makeClient(
        socksPort: socksPort, user: socksUser, password: socksPassword);
    try {
      final req = await client
          .getUrl(Uri.parse(_githubApi))
          .timeout(const Duration(seconds: 15));
      req.headers.set('User-Agent', 'TeapodStream');
      req.headers.set('Accept', 'application/vnd.github+json');
      final resp = await req.close().timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tagName =
          (json['tag_name'] as String? ?? '').replaceFirst(RegExp(r'^v'), '');
      if (tagName.isEmpty) return null;
      if (_compareVersions(tagName, currentVersion) <= 0) return null;
      final assets = json['assets'] as List<dynamic>? ?? [];
      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        if (name.contains(abi) && name.endsWith('.apk')) {
          final url = asset['browser_download_url'] as String?;
          final size = asset['size'] as int?;
          if (url != null) {
            return UpdateInfo(
                version: tagName, downloadUrl: url, totalBytes: size);
          }
        }
      }
      return null;
    } finally {
      client.close();
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
      client.close();
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
