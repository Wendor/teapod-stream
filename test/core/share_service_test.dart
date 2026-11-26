import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:teapodstream/core/models/app_settings.dart';
import 'package:teapodstream/core/models/profile.dart';
import 'package:teapodstream/core/models/profile_bundle.dart';
import 'package:teapodstream/core/services/share_service.dart';
import 'package:teapodstream/l10n/l10n.dart';

void main() {
  late Directory cache;
  late ShareService service;
  final shared = <ShareParams>[];

  setUp(() {
    cache = Directory.systemTemp.createTempSync('share');
    shared.clear();
    service = ShareService(cacheDir: () async => cache, share: (p) async => shared.add(p));
  });
  tearDown(() {
    cache.deleteSync(recursive: true);
    L10n.current = lookupAppLocalizations(const Locale('en'));
  });

  test('the share text and subject are in the app language', () async {
    L10n.current = lookupAppLocalizations(const Locale('ru'));
    File('${cache.path}/native.log').writeAsStringSync('x');
    await service.shareLog('${cache.path}/native.log', const []);
    expect(shared.single.subject, 'Лог TeapodStream');
  });

  group('shareLog', () {
    late File log;
    setUp(() => log = File('${cache.path}/native.log'));

    test('shares one masked copy and removes the exports older versions left', () async {
      log.writeAsStringSync('connect to secret-host:443\n');
      final old = File('${cache.path}/teapod_20260101_1200.txt')..writeAsStringSync('old');
      final other = File('${cache.path}/teapod_notes.txt')..writeAsStringSync('keep');
      expect(await service.shareLog(log.path, ['secret-host']), isTrue);
      final copy = File('${cache.path}/${ShareService.logExportName}');
      expect(copy.readAsStringSync(), isNot(contains('secret-host')));
      expect(shared.single.files!.single.path, copy.path);
      expect(shared.single.subject, 'TeapodStream log');
      expect(old.existsSync(), isFalse);
      expect(other.existsSync(), isTrue);
    });

    test('a missing or empty log shares nothing', () async {
      expect(await service.shareLog(log.path, const []), isFalse);
      log.writeAsStringSync('');
      expect(await service.shareLog(log.path, const []), isFalse);
      expect(shared, isEmpty);
    });
  });

  test('shareProfile writes the bundle as JSON named after the profile, unsafe characters replaced', () async {
    final bundle = ProfileBundle(
      exportedAt: DateTime(2026),
      profile: Profile(id: 'p', name: 'My/Профиль', settings: const AppSettings(), createdAt: DateTime(2026)),
    );
    await service.shareProfile('My/Профиль', bundle);
    final path = shared.single.files!.single.path;
    expect(path, '${cache.path}/My_Профиль.json');
    expect(shared.single.text, 'Teapod profile: My/Профиль');
    final json = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    expect(ProfileBundle.fromJson(json).profile.name, 'My/Профиль');
  });
}
