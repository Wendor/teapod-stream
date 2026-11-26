import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/models/app_message.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/protocols/xray/rust_config_builder.dart';
import 'package:teapodstream/protocols/xray/vless_parser.dart';
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

  test('reasons of builders, parsers and models are localized where shown', () {
    final ss = VlessParser.parseUri('ss://aes-256-gcm:pw@h.example:8388/?plugin=obfs-local#n')!;
    expect(RustConfigBuilder.unsupportedReason(ss)!.localize(ru), ru.rustSsMethod('aes-256-gcm'));
    expect(VpnConfig.fromJson({...ss.toJson(), 'address': ''}).validate()!.localize(ru), ru.validateEmptyAddress);
    try {
      VlessParser.parseUri('vless://u@h.example:443?security=xtls#n');
      fail('an unknown security must be refused');
    } on ReasonException catch (e) {
      expect(e.reason.localize(ru), ru.linkUnknownSecurity('xtls'));
      expect(e.message, en.linkUnknownSecurity('xtls'));
    }
  });

  test('ReasonException.of keeps an app string and wraps other text', () {
    final m = AppMessage.l10n((l) => l.rustEch);
    expect(ReasonException.of(ReasonException(m)), m);
    expect(ReasonException.of(const FormatException('bad')), const AppMessage.text('bad'));
  });
}
