import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/models/app_message.dart';
import 'package:teapodstream/l10n/l10n.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ru = lookupAppLocalizations(const Locale('ru'));

  test('a code is localized where it is shown, in that language', () {
    const m = AppMessage(MessageCode.updateUnsupportedDevice, 'x86');
    expect(m.localize(en), en.updateUnsupportedDevice('x86'));
    expect(m.localize(ru), ru.updateUnsupportedDevice('x86'));
    expect(m.localize(ru), isNot(m.localize(en)));
  });

  test('every code has text', () {
    for (final c in MessageCode.values) {
      expect(AppMessage(c, 'a').localize(en), isNotEmpty, reason: c.name);
    }
  });

  test('outside text passes as it is; equality by code, argument and text', () {
    expect(const AppMessage.text('port busy').localize(ru), 'port busy');
    expect(const AppMessage.text('a'), const AppMessage.text('a'));
    expect(const AppMessage(MessageCode.subEmpty), isNot(const AppMessage.text('a')));
    expect(
      const AppMessage(MessageCode.updateCheckError, 'a'),
      isNot(const AppMessage(MessageCode.updateCheckError, 'b')),
    );
  });

  test('an app string picked by l10n is localized in the language it is shown in', () {
    final m = AppMessage.l10n((l) => l.rustGeositeTrimmed('ads'));
    expect(m.localize(en), en.rustGeositeTrimmed('ads'));
    expect(m.localize(ru), ru.rustGeositeTrimmed('ads'));
    expect(m, m);
    expect(m, isNot(const AppMessage.text('x')));
  });
}
