import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/constants/app_constants.dart';
import 'package:teapodstream/core/models/subscription.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/models/vpn_log_entry.dart';
import 'package:teapodstream/core/services/log_service.dart';

void main() {
  late ProviderContainer c;
  LogService log() => c.read(logServiceProvider.notifier);
  List<String> messages() => c.read(logServiceProvider).map((e) => e.message).toList();

  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  test('helpers add entries with level and source', () {
    log()
      ..addInfo('i', source: 's')
      ..addWarning('w')
      ..addError('e')
      ..addDebug('d');
    final entries = c.read(logServiceProvider);
    expect(entries.map((e) => e.level), [LogLevel.info, LogLevel.warning, LogLevel.error, LogLevel.debug]);
    expect(entries.first.source, 's');
  });

  test('buffer keeps the newest entries in order', () {
    const n = AppConstants.maxLogEntries + 5;
    for (var i = 0; i < n; i++) {
      log().addInfo('$i');
    }
    final m = messages();
    expect(m, hasLength(AppConstants.maxLogEntries));
    expect(m.first, '5');
    expect(m.last, '${n - 1}');
  });

  test('a published list never changes, however many lines come after it', () {
    log().addInfo('first');
    final early = c.read(logServiceProvider);
    for (var i = 0; i < 3 * AppConstants.maxLogEntries; i++) {
      log().addInfo('$i');
    }
    expect(early.map((e) => e.message), ['first']);
    expect(() => early[0] = VpnLogEntry.info('x'), throwsUnsupportedError);
    final m = messages();
    expect(m, hasLength(AppConstants.maxLogEntries));
    expect(m.last, '${3 * AppConstants.maxLogEntries - 1}');
    expect(m.first, '${2 * AppConstants.maxLogEntries}');
  });

  test('loadFromEntries replaces content', () {
    log().addInfo('old');
    log().loadFromEntries([VpnLogEntry.info('a'), VpnLogEntry.info('b')]);
    expect(messages(), ['a', 'b']);
  });

  test('clear empties the log and buffer', () {
    log().addInfo('x');
    log().clear();
    expect(messages(), isEmpty);
    log().addInfo('y');
    expect(messages(), ['y']);
  });

  group('maskLog', () {
    test('masks public IPv4 and keeps loopback and private addresses', () {
      expect(maskLog('dial 203.0.113.7:443 failed'), 'dial <ip>:443 failed');
      expect(maskLog('to 8.8.8.8.'), 'to <ip>.');
      expect(
        maskLog('127.0.0.1:10808 10.0.0.2 192.168.1.5 172.19.0.1 100.64.0.1 0.0.0.0'),
        '127.0.0.1:10808 10.0.0.2 192.168.1.5 172.19.0.1 100.64.0.1 0.0.0.0',
      );
      expect(maskLog('version 1.2.3.4.5 and 999.1.1.1'), 'version 1.2.3.4.5 and 999.1.1.1');
    });

    test('masks public IPv6 and keeps loopback, link-local, times and MACs', () {
      expect(maskLog('to [2001:db8::1]:443'), 'to [<ip>]:443');
      expect(maskLog('2a00:1450:4001:82a::200e up'), '<ip> up');
      expect(maskLog('::1 fe80::1%wlan0 fd00::5 ::'), '::1 fe80::1%wlan0 fd00::5 ::');
      expect(maskLog('2026/11/23 12:34:56 ok'), '2026/11/23 12:34:56 ok');
      expect(maskLog('mac aa:bb:cc:dd:ee:ff std::string'), 'mac aa:bb:cc:dd:ee:ff std::string');
    });

    test('masks UUIDs and password-like values', () {
      expect(maskLog('id 123e4567-e89b-12d3-a456-426614174000 x'), 'id <uuid> x');
      expect(maskLog('url ?user=bob&pass=hunter2&type=tcp'), 'url ?user=<hidden>&pass=<hidden>&type=tcp');
      expect(maskLog('pbk=abcDEF sid=12ab'), 'pbk=<hidden> sid=<hidden>');
      expect(maskLog('{"password": "s3cret", "port": 1}'), '{"password":"<hidden>", "port": 1}');
    });

    test('masks hosts and secrets of saved configs and subscriptions', () {
      final config = VpnConfig(
        id: '1',
        name: 'n',
        protocol: VpnProtocol.vless,
        address: 'edge.example.com',
        port: 443,
        uuid: 'not-a-uuid-token',
        sni: 'front.example.net',
        security: VpnSecurity.tls,
        transport: VpnTransport.tcp,
        createdAt: DateTime(2026),
      );
      final sub = Subscription(id: 's', name: 's', url: 'https://subs.example.org/t/abc', createdAt: DateTime(2026));
      final secrets = logSecrets(configs: [config], subscriptions: [sub], extra: ['socksuser', '']);
      expect(
        maskLog(
          'dial EDGE.example.com:443 sni front.example.net auth not-a-uuid-token '
          'fetch https://subs.example.org/t/abc host subs.example.org api.edge.example.com socksuser',
          secrets: secrets,
        ),
        'dial <hidden>:443 sni <hidden> auth <hidden> '
        'fetch <hidden> host <hidden> api.<hidden> <hidden>',
      );
    });

    test('ignores short values and does not match inside words', () {
      expect(maskLog('a pass p and passport', secrets: ['p', 'pass']), 'a <hidden> p and passport');
      expect(maskLog('21.2.3.45 1.2.3.4', secrets: ['1.2.3.4']), '<ip> <hidden>');
    });
  });
}
