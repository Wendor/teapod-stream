import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/constants/app_constants.dart';
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
    expect(entries.map((e) => e.level),
        [LogLevel.info, LogLevel.warning, LogLevel.error, LogLevel.debug]);
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
}
