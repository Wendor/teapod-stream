// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/ui/theme/app_text_scaler.dart';

void main() {
  group('appTextScaler', () {
    test('follows the system scale', () {
      expect(appTextScaler(const TextScaler.linear(1.5), 1.0).scale(10), 15);
    });

    test('the app setting multiplies the system scale', () {
      expect(appTextScaler(const TextScaler.linear(1.5), 1.2).scale(10), closeTo(18, 1e-9));
      expect(appTextScaler(TextScaler.noScaling, 1.2).scale(10), closeTo(12, 1e-9));
    });

    test('is capped at maxTextScale', () {
      expect(appTextScaler(const TextScaler.linear(2.0), 1.2).scale(10), 10 * maxTextScale);
    });
  });
}
