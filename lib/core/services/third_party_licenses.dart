import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Лицензии нативных ядер в teapod-core.aar (не пакеты pub — Flutter их не знает).
const _licenses = [
  ('sing-box', 'assets/licenses/sing-box.txt'),
  ('amneziawg-go', 'assets/licenses/amneziawg-go.txt'),
];

/// Регистрирует лицензии для `showLicensePage`.
void registerThirdPartyLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (package, asset) in _licenses) {
      yield LicenseEntryWithLineBreaks([package], await rootBundle.loadString(asset));
    }
  });
}
