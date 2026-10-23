import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/models/heartbeat_settings.dart';
import 'package:teapodstream/core/models/connection_fingerprint.dart';
import 'package:teapodstream/core/services/settings_service.dart';

void main() {
  group('connectionFingerprint', () {
    test('идентичен для одинаковых настроек', () {
      expect(connectionFingerprint(const AppSettings()),
          connectionFingerprint(const AppSettings()));
    });

    test('меняется при изменении connection-полей', () {
      const base = AppSettings();
      expect(connectionFingerprint(base.copyWith(mtu: 1400)),
          isNot(connectionFingerprint(base)));
      expect(connectionFingerprint(base.copyWith(killSwitchEnabled: true)),
          isNot(connectionFingerprint(base)));
      expect(connectionFingerprint(base.copyWith(splitTunnelingEnabled: true)),
          isNot(connectionFingerprint(base)));
    });

    test('не меняется от косметических полей', () {
      const base = AppSettings();
      expect(connectionFingerprint(base.copyWith(fontScale: FontScale.large)),
          connectionFingerprint(base));
      expect(connectionFingerprint(base.copyWith(autoConnect: true)),
          connectionFingerprint(base));
      expect(connectionFingerprint(base.copyWith(subUserAgent: 'x')),
          connectionFingerprint(base));
    });

    test('возврат значения восстанавливает fingerprint', () {
      const base = AppSettings();
      final changed = base.copyWith(enableUdp: !base.enableUdp);
      final reverted = changed.copyWith(enableUdp: base.enableUdp);
      expect(connectionFingerprint(reverted), connectionFingerprint(base));
    });

    test('set-поля не зависят от порядка', () {
      final a = const AppSettings().copyWith(excludedPackages: {'b', 'a'});
      final b = const AppSettings().copyWith(excludedPackages: {'a', 'b'});
      expect(connectionFingerprint(a), connectionFingerprint(b));
    });

    test('учитывает только значения, которые доходят до native', () {
      const base = AppSettings();
      AppSettings withProbe(HeartbeatProbe probe) =>
          base.copyWith(heartbeat: base.heartbeat.copyWith(probe: probe));
      final xrayDelay = withProbe(HeartbeatProbe.xrayDelay);
      final passive = withProbe(HeartbeatProbe.passive);
      final socks = withProbe(HeartbeatProbe.socks);
      final tethering = base.copyWith(allowTethering: true);
      final noTethering = base.copyWith(allowTethering: false);
      // Все три пробы и переключатель раздачи доходят до native в обеих сборках:
      // их смена меняет сессию.
      expect(connectionFingerprint(passive), isNot(connectionFingerprint(socks)));
      expect(connectionFingerprint(xrayDelay), isNot(connectionFingerprint(socks)));
      expect(connectionFingerprint(tethering),
          isNot(connectionFingerprint(noTethering)));
    });
  });
}
