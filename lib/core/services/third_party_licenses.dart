import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Licenses of the native cores in teapod-core.aar (not pub packages — Flutter doesn't know them).
const _licenses = [
  ('sing-box', 'assets/licenses/sing-box.txt'),
  ('amneziawg-go', 'assets/licenses/amneziawg-go.txt'),
];

/// Registers the licenses for `showLicensePage`.
void registerThirdPartyLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (package, asset) in _licenses) {
      yield LicenseEntryWithLineBreaks([package], await rootBundle.loadString(asset));
    }
  });
}
