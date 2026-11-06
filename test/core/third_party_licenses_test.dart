import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/services/third_party_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sing-box (GPL with name term) and amneziawg-go are registered', () async {
    registerThirdPartyLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    String text(String pkg) => entries
        .firstWhere((e) => e.packages.contains(pkg))
        .paragraphs
        .map((p) => p.text)
        .join('\n');
    expect(text('sing-box'), contains('GNU General Public License'));
    expect(text('sing-box'), contains('no derivative work may use the name'));
    expect(text('amneziawg-go'), contains('Permission is hereby granted'));
  });
}
