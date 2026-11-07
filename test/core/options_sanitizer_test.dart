import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/cores/options_sanitizer.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';

const _base = VpnEngineOptions(socksPort: 10808, httpPort: 0, socksUser: 'u', socksPassword: 'p', mtu: 1400);

void main() {
  test('drop applies fix and records warning only when true', () {
    final s = OptionsSanitizer(_base)
      ..drop(when: false, warning: 'skipped', fix: (o) => o.copyWith(mtu: 1))
      ..drop(when: true, warning: 'mtu reset', fix: (o) => o.copyWith(mtu: 1500));
    expect(s.result.options.mtu, 1500);
    expect(s.result.warnings, ['mtu reset']);
  });

  test('warn records warning without changing options', () {
    final s = OptionsSanitizer(_base)
      ..warn(when: true, warning: 'icmp ignored')
      ..warn(when: false, warning: 'nope');
    expect(s.result.options.mtu, 1400);
    expect(s.result.warnings, ['icmp ignored']);
  });
}
