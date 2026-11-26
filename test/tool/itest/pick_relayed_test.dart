import 'package:flutter_test/flutter_test.dart';

import '../../../tool/itest/main.dart' as runner;
import '../../../tool/itest/src/matrix.dart';
import '../../../tool/itest/src/probes.dart';

AgentConfig cfg(String id, String protocol, List<String> cores) =>
    (id: id, name: id, protocol: protocol, host: '$id.example', port: 443, sub: null, cores: cores);

void main() {
  final hy2 = cfg('hy2', 'hysteria2', ['go', 'box']);
  final vless = cfg('vless', 'vless', ['go', 'rust', 'box']);
  final trojan = cfg('trojan', 'trojan', ['go', 'box']);
  final owned = {'hy2': true, 'vless': true, 'trojan': true};
  CaseResult base(String core, String id, Verdict v) =>
      CaseResult('base/$core/$id', v, '', Duration.zero, '', configId: id);

  test('the reference config when it runs over TCP', () {
    expect(runner.pickRelayed([hy2, vless, trojan], owned, 'go', 'trojan', const [])?.id, 'trojan');
  });

  test('a UDP reference falls back to an owned TCP config that passed base', () {
    final results = [base('sing-box', 'vless', Verdict.fail), base('sing-box', 'trojan', Verdict.pass)];
    expect(runner.pickRelayed([hy2, vless, trojan], owned, 'box', 'hy2', results)?.id, 'trojan');
  });

  test('no owned TCP config of the core — none', () {
    expect(runner.pickRelayed([hy2, vless], {...owned, 'vless': false}, 'go', 'hy2', const []), isNull);
    expect(runner.pickRelayed([hy2, trojan], owned, 'rust', 'hy2', const []), isNull);
  });
}
