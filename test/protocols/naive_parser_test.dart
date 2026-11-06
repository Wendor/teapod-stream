import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/protocol_settings.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/protocols/parsers/naive_parser.dart';
import 'package:teapodstream/protocols/singbox/singbox_outbound.dart';
import 'package:teapodstream/protocols/xray/vless_parser.dart';

NaiveSettings _naive(VpnConfig c) => c.protocolSettings! as NaiveSettings;

void main() {
  test('naive+https link with extra headers', () {
    final c = NaiveParser.parseUri('naive+https://user:pa%40ss@n.example.com:8443'
        '?extra-headers=X-A%3A%201%0D%0AX-B%3A2#My%20Naive')!;
    expect(c.protocol, VpnProtocol.naive);
    expect([c.address, c.port, c.name], ['n.example.com', 8443, 'My Naive']);
    final n = _naive(c);
    expect([n.user, n.password, n.quic], ['user', 'pa@ss', false]);
    expect(n.extraHeaders, {'X-A': '1', 'X-B': '2'});
    expect(c.validate(), isNull);
  });

  test('naive+quic, default port and name', () {
    final c = VlessParser.parseUri('naive+quic://u:p@q.example.com')!;
    expect(_naive(c).quic, isTrue);
    expect(c.port, 443);
    expect(c.name, 'Naive q.example.com');
    expect(NaiveParser.parseUri('naive+https://q.example.com'), isNull);
    expect(NaiveParser.parseUri('https://u:p@q.example.com'), isNull);
  });

  test('sing-box outbound', () {
    const opts = VpnEngineOptions(socksPort: 1, httpPort: 0, socksUser: '', socksPassword: '');
    expect(SingBoxOutbound.build(NaiveParser.parseUri('naive+https://u:p@n.example.com?extra-headers=X-A%3A1')!, opts), {
      'type': 'naive', 'tag': 'proxy', 'server': 'n.example.com', 'server_port': 443,
      'username': 'u', 'password': 'p', 'extra_headers': {'X-A': '1'},
      'tls': {'enabled': true, 'server_name': 'n.example.com'},
    });
    expect(SingBoxOutbound.build(NaiveParser.parseUri('naive+quic://u:p@n.example.com')!, opts)['quic'], isTrue);
  });
}
