import 'package:flutter_test/flutter_test.dart';

import 'package:teapodstream/core/services/ip_lookup.dart';

import '../../../tool/itest/src/agent_client.dart';
import '../../../tool/itest/src/device_guard.dart';
import '../../../tool/itest/src/matrix.dart';
import '../../../tool/itest/src/probes.dart';
import 'fake_shell.dart';

AgentConfig cfg(String id, String name, List<String> cores, {String protocol = 'vless'}) =>
    (id: id, name: name, protocol: protocol, host: 'h', port: 1, sub: null, cores: cores);

void main() {
  final configs = [
    cfg('1', 'ssh', ['box'], protocol: 'ssh'),
    cfg('2', 'reality', ['go', 'rust', 'box']),
  ];

  test('base cases follow supported cores only', () {
    final ids = buildMatrix(configs, owned: {'1': true, '2': true}).map((c) => c.id);
    expect(ids, containsAll(['base/sing-box/ssh', 'base/xray-core/reality', 'base/xray-rust/reality']));
    expect(ids, isNot(contains('base/xray-core/ssh')));
  });

  test('core filter takes display names', () {
    final ids = buildMatrix(configs, owned: {}, coreGlob: 'sing-box').map((c) => c.id);
    expect(ids, ['base/sing-box/ssh', 'base/sing-box/reality']);
  });

  test('config filter is a case-insensitive glob over names', () {
    final ids = buildMatrix(configs, owned: {}, configGlob: 'REAL*').map((c) => c.id);
    expect(ids, unorderedEquals(['base/xray-core/reality', 'base/xray-rust/reality', 'base/sing-box/reality']));
  });

  test('option cases only for cores with a reference config', () {
    final cases = buildMatrix(configs, owned: {}, reference: {'box': '2'});
    final opt = cases.where((c) => c.id.startsWith('opt/')).toList();
    expect(opt, isNotEmpty);
    expect(opt.map((c) => c.core).toSet(), {'box'});
    expect(opt.map((c) => c.configId).toSet(), {'2'});
  });

  test('case glob selects split cases', () {
    final ids = buildMatrix(
      configs,
      owned: {},
      reference: {'box': '2', 'go': '2'},
      caseGlob: 'opt/*/split-*',
    ).map((c) => c.id).toList();
    expect(ids, isNotEmpty);
    expect(ids, everyElement(matches(RegExp(r'^opt/[^/]+/split-'))));
  });

  test('proxy-only exists only for xray-core', () {
    final ids = buildMatrix(configs, owned: {}, reference: {'go': '2', 'box': '2'}).map((c) => c.id);
    expect(ids, contains('opt/xray-core/proxy-only'));
    expect(ids, isNot(contains('opt/sing-box/proxy-only')));
  });

  test('owned flag defaults to false for unknown ids', () {
    final c = buildMatrix(configs, owned: {'2': true}).firstWhere((c) => c.configId == '1');
    expect(c.owned, isFalse);
  });

  test('duplicate names get host:port suffix', () {
    final dup = [
      (id: 'a', name: 'XHTTP-TLS', protocol: 'vless', host: 'h', port: 4445, sub: 's', cores: ['go']),
      (id: 'b', name: 'XHTTP-TLS', protocol: 'vless', host: 'h', port: 4043, sub: 's', cores: ['go']),
    ];
    expect(buildMatrix(dup, owned: {}).map((c) => c.id), [
      'base/xray-core/XHTTP-TLS@h:4445',
      'base/xray-core/XHTTP-TLS@h:4043',
    ]);
  });

  test('glob', () {
    expect(globMatch('opt/*/split-*', 'opt/sing-box/split-only-shell'), isTrue);
    expect(globMatch('base/*', 'opt/x'), isFalse);
  });

  test("the routing pair skips the app's own IP lookup services", () {
    expect(appLookupHosts, IpLookupSource.hosts.toSet());
    final shell = FakeShell();
    final direct = {for (final u in echoMain) u: '198.51.100.1'};
    final ctx = CaseCtx(
      AgentClient(shell, const Stream.empty()),
      Probes(shell),
      Baseline(direct, null, null),
      DeviceGuard(shell),
      '203.0.113.5',
    );
    final (a, b) = ctx.pair!;
    expect([a, b].map((u) => Uri.parse(u).host), everyElement(isNot(isIn(appLookupHosts))));
  });
}
