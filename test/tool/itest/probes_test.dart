import 'package:flutter_test/flutter_test.dart';

import '../../../tool/itest/src/probes.dart';
import 'fake_shell.dart';

void main() {
  const a = 'https://a/ip', b = 'https://b/ip';
  // Сеть: сервис a без VPN видит прямой IP 77.x, b роутер уже заворачивает на 144.x.
  const base = {a: '77.0.0.1', b: '144.0.0.1'};

  group('classifyTunnel', () {
    test('no baseline at all → skip(echo)', () {
      final r = classifyTunnel(baseline: {a: null}, observed: {a: '1.2.3.4'});
      expect(r.v, Verdict.skip);
      expect(r.note, 'echo');
    });
    test('only the network-routed service answered → skip, not a pass', () {
      final r = classifyTunnel(baseline: base, observed: {a: null, b: '144.0.0.1'}, egress: '144.0.0.1');
      expect(r.v, Verdict.skip);
    });
    test('nothing observed → fail', () {
      expect(classifyTunnel(baseline: base, observed: {a: null, b: null}).v, Verdict.fail);
    });
    test('informative service still sees direct IP → leak', () {
      final r = classifyTunnel(baseline: base, observed: {a: '77.0.0.1', b: '144.0.0.1'}, egress: '144.0.0.1');
      expect(r.v, Verdict.fail);
      expect(r.note, contains('leak'));
    });
    test('service already routed to the egress by the network is ignored', () {
      expect(classifyTunnel(baseline: base, observed: {a: '144.0.0.1', b: '144.0.0.1'}, egress: '144.0.0.1').v,
          Verdict.pass);
    });
    test('egress equals direct IP → pass, leak undetectable', () {
      final r = classifyTunnel(baseline: {a: '77.0.0.1'}, observed: {a: '77.0.0.1'}, egress: '77.0.0.1');
      expect(r.v, Verdict.pass);
      expect(r.note, contains('undetectable'));
    });
    test('server in the device network (egress = ISP IP) → pass, leak undetectable', () {
      // Домашний сервер: его выход — тот же IP провайдера, а роутер заворачивает b на 144.x.
      final r = classifyTunnel(
          baseline: base, observed: {a: '77.0.0.1', b: '144.0.0.1'}, egress: '77.0.0.1', ispIp: '77.0.0.1');
      expect(r.v, Verdict.pass);
      expect(r.note, contains('undetectable'));
    });
    test('strict egress mismatch → fail', () {
      final r = classifyTunnel(baseline: base, observed: {a: '5.5.5.5'}, egress: '144.0.0.1', strictEgress: true);
      expect(r.v, Verdict.fail);
      expect(r.note, contains('egress'));
    });
    test('unknown exit IP without strict egress → pass', () {
      expect(classifyTunnel(baseline: base, observed: {a: '5.5.5.5', b: null}, egress: '144.0.0.1').v, Verdict.pass);
    });
  });

  group('classifyDirect', () {
    test('direct IP seen → pass', () {
      expect(classifyDirect(baseline: '77.0.0.1', observed: '77.0.0.1', egress: '144.0.0.1').v, Verdict.pass);
    });
    test('tunnel IP seen → fail', () {
      expect(classifyDirect(baseline: '77.0.0.1', observed: '144.0.0.1', egress: '144.0.0.1').v, Verdict.fail);
    });
    test('direct equals egress → skip (indistinguishable)', () {
      expect(classifyDirect(baseline: '144.0.0.1', observed: '144.0.0.1', egress: '144.0.0.1').v, Verdict.skip);
    });
    test('no baseline → skip', () {
      expect(classifyDirect(baseline: null, observed: '1.2.3.4').v, Verdict.skip);
    });
  });

  test('informative() keeps services whose direct IP differs from the egress', () {
    expect(informative(base, '144.0.0.1'), [a]);
    expect(informative(base, null), [a, b]);
  });

  test('ip() accepts bare IPv4/IPv6 and rejects HTML', () async {
    expect(await Probes(FakeShell({'checkip': '203.0.113.7\n'})).ip('https://checkip.amazonaws.com/'),
        '203.0.113.7');
    expect(await Probes(FakeShell({'ifconfig': '2001:db8::1'})).ip('https://ifconfig.co/ip'), '2001:db8::1');
    expect(await Probes(FakeShell({'mail.ru': '<html>blocked</html>'})).ip('https://ip.mail.ru', retries: 0), isNull);
  });

  test('ip() strips the status line, retries a failed probe and logs the raw answer', () async {
    expect(await Probes(FakeShell({'ifconfig': '203.0.113.7\n\n200'})).ip('https://ifconfig.co/ip'), '203.0.113.7');
    final shell = FakeShell({'ifconfig': 'rate limited\n429'});
    final log = <String>[];
    final p = Probes(shell)..log = log.add;
    expect(await p.ip('https://ifconfig.co/ip'), isNull);
    expect(shell.calls, hasLength(2));
    expect(log, ['probe https://ifconfig.co/ip #1: rate limited 429', 'probe https://ifconfig.co/ip #2: rate limited 429']);
  });

  test('baseline keeps direct IP per service and drops loopback answers', () async {
    final b = await measureBaseline(Probes(FakeShell({
      'ifconfig.co': '77.0.0.1',
      'ipinfo.io': '77.0.0.1',
      'amazonaws': '144.0.0.1',
      'ipify': '144.0.0.1',
      'ident.me': '<html>',
      'nic.ru': '<html>no ip</html>',
    })));
    expect(b.direct['https://ifconfig.co/ip'], '77.0.0.1');
    expect(b.direct['https://checkip.amazonaws.com/'], '144.0.0.1');
    expect(b.direct['https://ident.me'], isNull);
    expect(b.directRuIp, isNull);
  });

  test('ip() takes the first public IPv4 from an HTML echo page', () async {
    final p = Probes(FakeShell({'nic.ru': '<p>router 192.168.0.1</p><b>77.0.0.9</b> 77.0.0.9'}));
    expect(await p.ip(echoRu), '77.0.0.9');
  });

  group('classifyDns', () {
    const isp = (ip: '193.232.139.48', geo: 'Russia - MSK-IX');
    test('same provider through another anycast resolver → leak', () {
      final r = classifyDns(baseline: isp, observed: (ip: '193.232.236.48', geo: 'Russia - MSK-IX'), proxy: true);
      expect(r.v, Verdict.fail);
    });
    test('other provider in proxy mode → pass', () {
      expect(classifyDns(baseline: isp, observed: (ip: '1.1.1.1', geo: 'Norway - Cloudflare'), proxy: true).v,
          Verdict.pass);
    });
    test('empty geo on both sides is not the same provider', () {
      expect(classifyDns(baseline: (ip: '9.9.9.9', geo: ''), observed: (ip: '1.1.1.1', geo: ''), proxy: true).v,
          Verdict.pass);
    });
    test('no answer → fail; direct mode only needs an answer', () {
      expect(classifyDns(baseline: isp, observed: null, proxy: false).v, Verdict.fail);
      expect(classifyDns(baseline: isp, observed: isp, proxy: false).v, Verdict.pass);
    });
  });

  test('dnsResolverIp parses edns.ip-api.com', () async {
    final p = Probes(FakeShell({'edns': '{"dns":{"geo":"X","ip":"74.125.1.1"}}'}));
    expect(await p.dnsResolver(), (ip: '74.125.1.1', geo: 'X'));
  });
}
