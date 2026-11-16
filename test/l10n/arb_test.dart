import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _arb(String lang) =>
    jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map<String, dynamic>;

/// Placeholder names a message uses; plural/select branch bodies are skipped.
Set<String> _placeholders(String message) => RegExp(r'\{(\w+)(?=[,}])')
    .allMatches(message)
    .map((m) => m.group(1)!)
    .toSet();

void main() {
  final en = _arb('en');
  final ru = _arb('ru');
  Set<String> keys(Map<String, dynamic> arb) => arb.keys.where((k) => !k.startsWith('@')).toSet();

  test('every English message has a Russian translation and vice versa', () {
    expect(keys(ru), keys(en));
  });

  test('translations use the same placeholders', () {
    for (final k in keys(en)) {
      expect(_placeholders(ru[k] as String), _placeholders(en[k] as String), reason: k);
    }
  });
}
