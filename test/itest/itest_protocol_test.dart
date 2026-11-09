import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/cores/core_resolver.dart';
import 'package:teapodstream/core/models/core_kind.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/itest/itest_protocol.dart';
import 'package:teapodstream/providers/core_provider.dart';

CoreResolution chosen(CoreKind kind, {required bool pinned}) => CoreResolution(
      coreBackendFor(kind),
      [(kind: kind, reason: null)],
      pinned: pinned,
    );

void main() {
  test('deepMerge merges nested maps and replaces lists', () {
    final r = deepMerge({
      'routing': {'sites': ['a'], 'bypassLocal': true},
      'mtu': 1500,
    }, {
      'routing': {'sites': ['b']},
    });
    expect(r, {
      'routing': {'sites': ['b'], 'bypassLocal': true},
      'mtu': 1500,
    });
  });

  test('settings patch round-trips through AppSettings', () {
    final s = AppSettings.fromJson(deepMerge(const AppSettings().toJson(), {
      'routing': {'sitesEnabled': true, 'sites': ['checkip.amazonaws.com']},
    }));
    expect(s.routing.sitesEnabled, isTrue);
    expect(s.routing.sites, ['checkip.amazonaws.com']);
  });

  test('pickCoreError rejects silent fallback to another core', () {
    expect(pickCoreError(chosen(CoreKind.xrayGo, pinned: false), CoreKind.singBox), isNotNull);
    expect(pickCoreError(chosen(CoreKind.singBox, pinned: true), CoreKind.singBox), isNull);
  });

  test('pickCoreError reports the verdict reason of the wanted core', () {
    const r = CoreResolution(null, [(kind: CoreKind.xrayGo, reason: 'SSH не поддерживается')]);
    expect(pickCoreError(r, CoreKind.xrayGo), 'SSH не поддерживается');
  });

  test('marker is a single line with prefix', () {
    final m = itestMarker({'id': '1', 'ok': false, 'error': 'a\nb'});
    expect(m, startsWith('TEAPOD_ITEST {'));
    expect(m.contains('\n'), isFalse);
  });
}
