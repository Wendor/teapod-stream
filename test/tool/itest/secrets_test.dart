import 'package:flutter_test/flutter_test.dart';

import '../../../tool/itest/src/secrets.dart';

void main() {
  test('exclude defaults to empty and parses host:port globs', () {
    expect(Secrets.fromJson({}).exclude, isEmpty);
    expect(Secrets.fromJson({'exclude': ['oslo.example:443']}).exclude, ['oslo.example:443']);
  });
}
