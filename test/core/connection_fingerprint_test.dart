import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/models/connection_fingerprint.dart';
import 'package:teapodstream/core/services/settings_service.dart';

void main() {
  group('connectionFingerprint', () {
    test('identical for identical settings', () {
      expect(connectionFingerprint(const AppSettings()), connectionFingerprint(const AppSettings()));
    });

    test('changes when connection fields change', () {
      const base = AppSettings();
      expect(connectionFingerprint(base.copyWith(mtu: 1400)), isNot(connectionFingerprint(base)));
      expect(connectionFingerprint(base.copyWith(killSwitchEnabled: true)), isNot(connectionFingerprint(base)));
      expect(connectionFingerprint(base.copyWith(splitTunnelingEnabled: true)), isNot(connectionFingerprint(base)));
    });

    test('does not change from cosmetic fields', () {
      const base = AppSettings();
      expect(connectionFingerprint(base.copyWith(fontScale: FontScale.large)), connectionFingerprint(base));
      expect(connectionFingerprint(base.copyWith(autoConnect: true)), connectionFingerprint(base));
      expect(connectionFingerprint(base.copyWith(subUserAgent: 'x')), connectionFingerprint(base));
    });

    test('restoring a value restores the fingerprint', () {
      const base = AppSettings();
      final changed = base.copyWith(enableUdp: !base.enableUdp);
      final reverted = changed.copyWith(enableUdp: base.enableUdp);
      expect(connectionFingerprint(reverted), connectionFingerprint(base));
    });

    test('set fields do not depend on order', () {
      final a = const AppSettings().copyWith(excludedPackages: {'b', 'a'});
      final b = const AppSettings().copyWith(excludedPackages: {'a', 'b'});
      expect(connectionFingerprint(a), connectionFingerprint(b));
    });
  });
}
