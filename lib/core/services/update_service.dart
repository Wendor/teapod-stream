import 'dart:io';
import 'dart:convert';
import 'package:socks5_proxy/socks.dart';

enum UpdateChannel { stable, beta }

/// Release notes languages: code → the language's own name. The name is the H1 of `changelog/<code>.md` and the
/// `### <name>` heading of that language's section in a release body (`./build.sh notes`).
const releaseNotesLanguages = {'en': 'English', 'ru': 'Русский'};

/// The notes of one release as published (every language).
class ReleaseNotes {
  final String version;
  final String body;

  const ReleaseNotes(this.version, this.body);

  /// The section of [body] for [languageCode]; English when it has none; the whole body when it has no
  /// language sections (releases before per-language notes).
  String forLanguage(String languageCode) {
    final sections = <String, List<String>>{};
    List<String>? current;
    for (final line in body.split(RegExp(r'\r?\n'))) {
      final heading = RegExp(r'^###\s+(.+?)\s*$').firstMatch(line)?.group(1);
      // Only a language name starts a section: another `###` inside the notes stays in the current one.
      if (heading != null && releaseNotesLanguages.containsValue(heading)) {
        current = sections.putIfAbsent(heading, () => []);
      } else {
        current?.add(line);
      }
    }
    for (final code in [languageCode, 'en']) {
      final section = sections[releaseNotesLanguages[code]]?.join('\n').trim();
      if (section != null && section.isNotEmpty) return section;
    }
    return body.trim();
  }
}

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final int? totalBytes;

  /// Notes of every release newer than the installed version up to [version], newest first; when nothing is
  /// newer (reinstall), the notes of [version]. Releases with an empty body are left out.
  final List<ReleaseNotes> notes;

  const UpdateInfo({required this.version, required this.downloadUrl, this.totalBytes, this.notes = const []});
}

class DownloadProgress {
  final int downloaded;
  final int total; // -1 if unknown
  final bool done;

  const DownloadProgress({required this.downloaded, required this.total, required this.done});
}

class UpdateService {
  static const _githubApiLatest = 'https://api.github.com/repos/Wendor/teapod-stream/releases/latest';
  // Newest first; 30 covers the versions a user may have skipped.
  static const _githubApiList = 'https://api.github.com/repos/Wendor/teapod-stream/releases?per_page=30';

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
    final client = _makeClient(socksPort: socksPort, user: socksUser, password: socksPassword);
    try {
      final releases = await _fetchReleases(client, channel);
      if (releases.isEmpty) return null;
      final release = releases.first;
      final tagName = _version(release);
      if (tagName.isEmpty) return null;
      if (!force && _compareVersions(tagName, currentVersion) <= 0) return null;
      final assets = release['assets'] as List<dynamic>? ?? [];
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
              notes: _notes(releases, release, currentVersion),
            );
          }
        }
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Non-draft releases of [channel] as GitHub lists them, newest first: stable without prereleases, beta all.
  /// Stable falls back to `/releases/latest` when the page holds prereleases only.
  Future<List<Map<String, dynamic>>> _fetchReleases(HttpClient client, UpdateChannel channel) async {
    final list = await _getJson(client, _githubApiList);
    final releases = [
      if (list is List<dynamic>)
        for (final r in list)
          if (r is Map<String, dynamic> &&
              r['draft'] != true &&
              (channel == UpdateChannel.beta || r['prerelease'] != true))
            r,
    ];
    if (releases.isEmpty && channel == UpdateChannel.stable) {
      final latest = await _getJson(client, _githubApiLatest);
      if (latest is Map<String, dynamic>) releases.add(latest);
    }
    return releases;
  }

  /// Decoded JSON of a GitHub API [url]; null on an error status.
  Future<Object?> _getJson(HttpClient client, String url) async {
    final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 15));
    req.headers.set('User-Agent', 'TeapodStream');
    req.headers.set('Accept', 'application/vnd.github+json');
    final resp = await req.close().timeout(const Duration(seconds: 15));
    // The body of an error is not read: it may never end; the caller closes the client.
    if (resp.statusCode != 200) return null;
    return jsonDecode(await resp.transform(utf8.decoder).join());
  }

  /// Notes of [releases] newer than [currentVersion] and not newer than [target], highest version first;
  /// those of [target] alone when none is newer.
  List<ReleaseNotes> _notes(List<Map<String, dynamic>> releases, Map<String, dynamic> target, String currentVersion) {
    final targetVersion = _version(target);
    final picked = [
      for (final r in releases)
        if (_compareVersions(_version(r), currentVersion) > 0 && _compareVersions(_version(r), targetVersion) <= 0) r,
    ];
    if (picked.isEmpty) picked.add(target);
    picked.sort((a, b) => _compareVersions(_version(b), _version(a)));
    return [
      for (final r in picked)
        if ((r['body'] as String? ?? '').trim() case final body when body.isNotEmpty) ReleaseNotes(_version(r), body),
    ];
  }

  static String _version(Map<String, dynamic> release) =>
      (release['tag_name'] as String? ?? '').replaceFirst(RegExp(r'^v'), '');

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
    final client = _makeClient(socksPort: socksPort, user: socksUser, password: socksPassword);
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
      final total = contentLength > 0 ? (isResume ? existing + contentLength : contentLength) : -1;
      sink = file.openWrite(mode: isResume ? FileMode.append : FileMode.write);
      int downloaded = isResume ? existing : 0;
      // Idle timeout: without it a stuck network holds the download forever, and cancelling
      // the async* subscription waits for the next chunk.
      await for (final chunk in resp.timeout(const Duration(seconds: 30))) {
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
    // The leading digits of each part: "2-beta" is 2.
    List<int> parts(String v) =>
        v.split('.').map((s) => int.tryParse(RegExp(r'^\d+').stringMatch(s) ?? '') ?? 0).toList();
    final ap = parts(a);
    final bp = parts(b);
    for (int i = 0; i < 3; i++) {
      final av = i < ap.length ? ap[i] : 0;
      final bv = i < bp.length ? bp[i] : 0;
      if (av != bv) return av - bv;
    }
    return 0;
  }
}
