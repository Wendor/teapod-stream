import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/constants/core_features.dart';

void main() {
  test('Go keeps all existing feature flags enabled', () {
    expect(CoreFeature.values.every(CoreFeatures.go.supports), isTrue);
  });

  test('Rust keeps routing and gates only its unsupported features', () {
    for (final feature in [
      CoreFeature.geoip,
      CoreFeature.geosite,
      CoreFeature.appRouting,
    ]) {
      expect(CoreFeatures.rust.supports(feature), isTrue);
    }
    for (final feature in [
      CoreFeature.proxyOnly,
      CoreFeature.mux,
      CoreFeature.directDns,
      CoreFeature.adBlocking,
      CoreFeature.socksAuthentication,
      CoreFeature.customMtu,
    ]) {
      expect(CoreFeatures.rust.supports(feature), isFalse);
      expect(CoreFeatures.rust.unavailableReason(feature), isNotEmpty);
    }
  });

  test('availability and its explanation agree for every feature and core', () {
    for (final features in [CoreFeatures.go, CoreFeatures.rust]) {
      for (final feature in CoreFeature.values) {
        if (features.supports(feature)) {
          expect(
            features.unavailableReason(feature),
            isNull,
            reason: feature.name,
          );
        } else {
          expect(
            features.unavailableReason(feature),
            isNotEmpty,
            reason: feature.name,
          );
        }
      }
    }
  });

  test('the build uses the requested core flag, defaulting to Go', () {
    const expected = String.fromEnvironment('TEAPOD_CORE', defaultValue: 'go');
    expect(CoreFeatures.current.isRust, expected == 'rust');
  });
}
