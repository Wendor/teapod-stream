import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/services/update_service.dart';
import 'package:teapodstream/ui/screens/whats_new_screen.dart';

void main() {
  final files = {
    for (final f in Directory('changelog').listSync().whereType<File>().where((f) => f.path.endsWith('.md')))
      f.uri.pathSegments.last.replaceFirst('.md', ''): f.readAsStringSync(),
  };

  test('a changelog file for every language and a language for every file', () {
    expect(files.keys.toSet(), releaseNotesLanguages.keys.toSet());
  });

  test('the H1 of each file is its language name', () {
    for (final MapEntry(key: code, value: text) in files.entries) {
      expect(text.split('\n').first, '# ${releaseNotesLanguages[code]}', reason: 'changelog/$code.md');
    }
  });

  test('every language has the same versions, newest first, none empty', () {
    final en = parseChangelog(files['en']!);
    expect(en, isNotEmpty);
    for (final MapEntry(key: code, value: text) in files.entries) {
      final versions = parseChangelog(text);
      expect([for (final v in versions) v.version], [for (final v in en) v.version], reason: 'changelog/$code.md');
      for (final v in versions) {
        expect(v.items, isNotEmpty, reason: 'changelog/$code.md ${v.version}');
      }
    }
    // A release `X.Y.Z`, or a summary of older versions: `X.Y` or a range `X.Y–X.Y`.
    final heading = RegExp(r'^(\d+)\.(\d+)(?:\.(\d+))?(?:–\d+\.\d+)?$');
    final numbers = [
      for (final v in en)
        if (heading.firstMatch(v.version) case final m?)
          [int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3] ?? '0')]
        else
          fail('changelog/en.md: "## ${v.version}" is not a version'),
    ];
    for (var i = 1; i < numbers.length; i++) {
      final (a, b) = (numbers[i - 1], numbers[i]);
      final newer = a[0] != b[0] ? a[0] > b[0] : (a[1] != b[1] ? a[1] > b[1] : a[2] > b[2]);
      expect(newer, isTrue, reason: '${en[i - 1].version} before ${en[i].version}');
    }
  });

  test('parseChangelog reads versions and bullets', () {
    final v = parseChangelog('# English\r\n\r\n## 1.8.0\r\n\r\n- one\r\n- two\r\n\r\n## 1.7.0\r\n- three\r\n');
    expect([for (final x in v) x.version], ['1.8.0', '1.7.0']);
    expect(v[0].items, ['one', 'two']);
    expect(v[1].items, ['three']);
  });
}
