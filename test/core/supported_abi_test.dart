import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/constants/app_constants.dart';

void main() {
  test('only arm64-v8a and x86_64 are supported', () {
    expect(AppConstants.supportedAbis, {'arm64-v8a', 'x86_64'});
    expect(AppConstants.supportedAbis.contains('armeabi-v7a'), isFalse);
  });
}
