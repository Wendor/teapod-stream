import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/l10n.dart';
import '../models/profile_bundle.dart';
import 'log_service.dart';

/// Files the app shares through the system share sheet: they are written to the cache dir first (share_plus needs a
/// shareable location).
class ShareService {
  ShareService({Future<Directory> Function()? cacheDir, Future<void> Function(ShareParams params)? share})
    : _cacheDir = cacheDir ?? getTemporaryDirectory,
      _share = share ?? ((p) => SharePlus.instance.share(p));

  final Future<Directory> Function() _cacheDir;
  final Future<void> Function(ShareParams params) _share;

  static const logExportName = 'teapod_log.txt';

  /// Shares [bundle] as `<name>.json`, the name reduced to letters, digits, `_`, `-` and spaces.
  Future<void> shareProfile(String name, ProfileBundle bundle) async {
    final dir = await _cacheDir();
    final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9а-яА-Я_\- ]'), '_');
    final file = File('${dir.path}/$safeName.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(bundle.toJson()));
    await _share(ShareParams(files: [XFile(file.path)], text: L10n.current.shareProfileText(name)));
  }

  /// Shares the log at [srcPath] with [secrets] masked, as one copy overwritten on every export. False — the log is
  /// missing or empty, nothing shared.
  Future<bool> shareLog(String srcPath, Iterable<String> secrets) async {
    final src = File(srcPath);
    if (!src.existsSync() || src.lengthSync() == 0) return false;
    final dir = await _cacheDir();
    final tmp = File('${dir.path}/$logExportName');
    await tmp.writeAsString(maskLog(utf8.decode(await src.readAsBytes(), allowMalformed: true), secrets: secrets));
    await _deleteOldExports(dir);
    await _share(
      ShareParams(
        files: [XFile(tmp.path, mimeType: 'text/plain')],
        subject: L10n.current.shareLogSubject,
      ),
    );
    return true;
  }

  /// Copies named `teapod_<date>_<time>.txt` were left in the cache by earlier versions.
  static Future<void> _deleteOldExports(Directory dir) async {
    final old = RegExp(r'^teapod_\d{8}_\d{4}\.txt$');
    try {
      await for (final f in dir.list()) {
        if (f is File && old.hasMatch(f.uri.pathSegments.last)) await f.delete();
      }
    } on FileSystemException {
      // Best effort: a copy that can't be deleted must not stop the export.
    }
  }
}

final shareServiceProvider = Provider<ShareService>((ref) => ShareService());
