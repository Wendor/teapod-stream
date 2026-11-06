import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/protocol_settings.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/protocols/parsers/wireguard_parser.dart';
import 'package:teapodstream/protocols/singbox/singbox_config_builder.dart';
import 'package:teapodstream/protocols/singbox/singbox_outbound.dart';
import 'package:teapodstream/protocols/xray/vless_parser.dart';

const _priv = 'yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=';
const _pub = 'xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=';
const _psk = 'FpCyhws9cxwWoV4xELtfJvjJN+zQVRPISllRWgeopVE=';

const _link = 'wireguard://${'yAnz5TF%2BlXXJte14tji3zlMNq%2Bhd2rYUIgJBgB3fBmk%3D'}@vpn.example.com:51820'
    '?publickey=xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg%3D'
    '&presharedkey=FpCyhws9cxwWoV4xELtfJvjJN%2BzQVRPISllRWgeopVE%3D'
    '&address=10.0.0.2%2F32,fd00%3A%3A2%2F128&mtu=1420&reserved=1,2,3&keepalive=25#Home%20WG';

// Реальный конфиг: CRLF, комментарии, регистр ключей, лишние ключи wg-quick, IPv6-endpoint.
const _conf = '[Interface]\r\n'
    '# client\r\n'
    'privatekey = $_priv\r\n'
    'Address = 10.0.0.2/32, fd00::2/128\r\n'
    'DNS = 1.1.1.1\r\n'
    'MTU = 1280\r\n'
    'PostUp = iptables -A FORWARD -i wg0 -j ACCEPT\r\n'
    'Table = off\r\n'
    '\r\n'
    '[Peer]\r\n'
    '; server\r\n'
    'PublicKey = $_pub\r\n'
    'PresharedKey = $_psk\r\n'
    'Endpoint = [2001:db8::1]:51820\r\n'
    'AllowedIPs = 0.0.0.0/0, ::/0\r\n'
    'PersistentKeepalive = 25\r\n';

WireGuardSettings _wg(VpnConfig c) => c.protocolSettings! as WireGuardSettings;

const _opts = VpnEngineOptions(socksPort: 1, httpPort: 0, socksUser: '', socksPassword: '');

void main() {
  test('wireguard:// link', () {
    final c = WireGuardParser.parseUri(_link)!;
    expect(c.protocol, VpnProtocol.wireguard);
    expect(c.name, 'Home WG');
    expect(c.address, 'vpn.example.com');
    expect(c.port, 51820);
    expect(c.rawUri, _link);
    final wg = _wg(c);
    expect(wg.privateKey, _priv);
    expect(wg.peerPublicKey, _pub);
    expect(wg.presharedKey, _psk);
    expect(wg.addresses, ['10.0.0.2/32', 'fd00::2/128']);
    expect(wg.mtu, 1420);
    expect(wg.reserved, [1, 2, 3]);
    expect(wg.keepalive, 25);
    expect(wg.amnezia, isNull);
    expect(c.validate(), isNull);
  });

  test('wg-quick .conf from a real client', () {
    expect(WireGuardParser.isConf(_conf), isTrue);
    expect(WireGuardParser.isConf(_link), isFalse);
    final c = WireGuardParser.parseConf(_conf);
    expect(c.address, '2001:db8::1');
    expect(c.port, 51820);
    expect(c.name, 'WireGuard 2001:db8::1');
    final wg = _wg(c);
    expect(wg.privateKey, _priv);
    expect(wg.addresses, ['10.0.0.2/32', 'fd00::2/128']);
    expect(wg.mtu, 1280);
    expect(wg.allowedIps, ['0.0.0.0/0', '::/0']);
    expect(wg.keepalive, 25);
    expect(wg.presharedKey, _psk);
    expect(c.rawUri, WireGuardParser.toUri(c));
    expect(WireGuardParser.parseConf(_conf, name: 'Office').name, 'Office');
  });

  test('wg-quick quirks: bare addresses, inline comments, repeated keys', () {
    final c = WireGuardParser.parseConf('[Interface]\nPrivateKey = $_priv # client key\n'
        'Address = 10.0.0.2\nAddress = fd00::2\n'
        '[Peer]\nPublicKey = $_pub\nEndpoint = 1.2.3.4:51820 # main\n'
        'AllowedIPs = 10.0.0.0/8\nAllowedIPs = 192.168.1.1\n');
    final wg = _wg(c);
    expect(c.address, '1.2.3.4');
    expect(wg.privateKey, _priv);
    expect(wg.addresses, ['10.0.0.2/32', 'fd00::2/128']);
    expect(wg.allowedIps, ['10.0.0.0/8', '192.168.1.1/32']);
    expect(_wg(WireGuardParser.parseUri('wireguard://k@1.2.3.4:1?publickey=p&address=10.0.0.9')!).addresses,
        ['10.0.0.9/32']);
  });

  test('toUri round-trips through parseUri', () {
    final c = WireGuardParser.parseConf(_conf);
    final back = WireGuardParser.parseUri(WireGuardParser.toUri(c))!;
    expect(back.address, c.address);
    expect(back.port, c.port);
    expect(_wg(back).toJson(), _wg(c).toJson());
  });

  test('one peer only; missing keys are errors with a reason', () {
    expect(
      () => WireGuardParser.parseConf('$_conf\n[Peer]\nPublicKey = $_pub\nEndpoint = 1.2.3.4:1\n'),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', 'Поддерживается один [Peer]; в конфиге: 2.')),
    );
    expect(() => WireGuardParser.parseConf('[Interface]\nAddress = 10.0.0.2/32\n[Peer]\nPublicKey = $_pub\nEndpoint = h:1\n'),
        throwsA(isA<FormatException>()));
  });

  test('defaults: allowed IPs cover everything', () {
    final c = WireGuardParser.parseUri('wireguard://k@1.2.3.4:51820?publickey=p&address=10.0.0.2/32')!;
    expect(_wg(c).allowedIps, ['0.0.0.0/0', '::/0']);
    expect(c.name, 'WireGuard 1.2.3.4');
  });

  test('VlessParser dispatches links and .conf text', () {
    expect(VlessParser.parseUri(_link)?.protocol, VpnProtocol.wireguard);
    expect(VlessParser.parseUri(_link.replaceFirst('wireguard://', 'wg://'))?.protocol, VpnProtocol.wireguard);
    expect(VlessParser.parseUri(_conf)?.protocol, VpnProtocol.wireguard);
    expect(VlessParser.parseUri('$_conf\n[Peer]\nPublicKey = x\n'), isNull);
  });

  test('sing-box endpoint', () {
    final c = WireGuardParser.parseUri(_link)!;
    expect(SingBoxOutbound.isEndpoint(c), isTrue);
    expect(SingBoxOutbound.build(c, _opts), {
      'type': 'wireguard',
      'tag': 'proxy',
      'address': ['10.0.0.2/32', 'fd00::2/128'],
      'private_key': _priv,
      'mtu': 1420,
      'peers': [
        {
          'address': 'vpn.example.com',
          'port': 51820,
          'public_key': _pub,
          'pre_shared_key': _psk,
          'allowed_ips': ['0.0.0.0/0', '::/0'],
          'persistent_keepalive_interval': 25,
          'reserved': [1, 2, 3],
        },
      ],
    });
  });

  group('AmneziaWG', () {
    const awg1 = '[Interface]\nPrivateKey = $_priv\nAddress = 10.8.1.2/32\nJc = 4\nJmin = 40\nJmax = 70\n'
        'S1 = 0\nS2 = 0\nH1 = 1\nH2 = 2\nH3 = 3\nH4 = 4\n'
        '[Peer]\nPublicKey = $_pub\nEndpoint = 5.6.7.8:443\nAllowedIPs = 0.0.0.0/0\nPersistentKeepalive = 22-30\n';
    const awg3 = '[Interface]\nPrivateKey = $_priv\nAddress = 10.8.1.2/32\nJc = 5\nJmin = 10\nJmax = 50\n'
        'S1 = 16\nS2 = 16\nS3 = 16\nS4 = 16\nH1 = 100-200\nH2 = 300-400\nH3 = 500\nH4 = 600-700\n'
        'I1 = <b 0xc0ffee><r 16><t>\nHeaderProtectionKey = $_psk\nContentPaddingAddition = 0-32\n'
        'RekeyAfterTime = 120\nRekeyTimeout = 5\nRejectAfterTime = 180\nKeepaliveTimeout = 10\nMaxHandshakeAttempts = 20\n'
        '[Peer]\nPublicKey = $_pub\nEndpoint = awg.example.com:51820\n';

    test('AWG 1.x .conf', () {
      final wg = _wg(WireGuardParser.parseConf(awg1));
      final a = wg.amnezia!;
      expect([a.jc, a.jmin, a.jmax, a.s1, a.s2], [4, 40, 70, 0, 0]);
      expect([a.h1, a.h2, a.h3, a.h4], ['1', '2', '3', '4']);
      expect(wg.keepalive, 22);
      expect(WireGuardParser.parseConf(awg1).protoTag, 'AWG');
    });

    test('AWG 3 .conf', () {
      final a = _wg(WireGuardParser.parseConf(awg3)).amnezia!;
      expect([a.s3, a.s4], [16, 16]);
      expect([a.h1, a.h4], ['100-200', '600-700']);
      expect(a.i1, '<b 0xc0ffee><r 16><t>');
      expect(a.headerProtectionKey, _psk);
      expect(a.contentPaddingAddition, '0-32');
      expect([a.rekeyAfterTime, a.rekeyTimeout, a.rejectAfterTime, a.keepaliveTimeout, a.maxHandshakeAttempts],
          ['120', '5', '180', '10', '20']);
    });

    test('AWG 3.1 flags: RandomTrailers/DisableCookies reach the endpoint', () {
      final conf = awg3.replaceFirst('[Peer]', 'RandomTrailers = on\nDisableCookies = on\n[Peer]');
      final a = _wg(WireGuardParser.parseConf(conf)).amnezia!;
      expect([a.randomTrailers, a.disableCookies], [true, true]);
      expect(_wg(WireGuardParser.parseConf(awg3)).amnezia!.randomTrailers, isFalse);
      final back = WireGuardParser.parseUri(WireGuardParser.toUri(WireGuardParser.parseConf(conf)))!;
      expect(_wg(back).amnezia!.toJson(), a.toJson());
      final out = SingBoxOutbound.build(WireGuardParser.parseConf(conf), _opts)['amnezia'] as Map;
      expect([out['random_trailers'], out['disable_cookies']], [true, true]);
      expect((SingBoxOutbound.build(WireGuardParser.parseConf(awg3), _opts)['amnezia'] as Map).containsKey('random_trailers'),
          isFalse);
    });

    test('link keeps AWG parameters', () {
      final c = WireGuardParser.parseConf(awg3);
      final back = WireGuardParser.parseUri(WireGuardParser.toUri(c))!;
      expect(_wg(back).amnezia!.toJson(), _wg(c).amnezia!.toJson());
    });

    test('sing-box endpoint awg with numeric fields and no zeros', () {
      final out = SingBoxOutbound.build(WireGuardParser.parseConf(awg1), _opts);
      expect(out['type'], 'awg');
      expect(out['amnezia'], {'jc': 4, 'jmin': 40, 'jmax': 70, 'h1': '1', 'h2': '2', 'h3': '3', 'h4': '4'});
      expect(SingBoxOutbound.build(WireGuardParser.parseConf(_conf), _opts)['type'], 'wireguard');
      final full = SingBoxOutbound.build(WireGuardParser.parseConf(awg3), _opts)['amnezia'] as Map;
      expect(full['header_protection_key'], _psk);
      expect(full['s3'], 16);
    });

    test('sing-box rejects AWG settings the endpoint cannot apply', () {
      final weak = WireGuardParser.parseConf(awg3.replaceFirst('S3 = 16', 'S3 = 8'));
      expect(SingBoxConfigBuilder.unsupportedReason(weak), 'AmneziaWG: защита заголовков требует S1–S4 не меньше 12.');
      final reserved = WireGuardParser.parseUri(WireGuardParser.toUri(WireGuardParser.parseConf(awg1)).replaceFirst('#', '&reserved=1,2,3#'))!;
      expect(SingBoxConfigBuilder.unsupportedReason(reserved), 'AmneziaWG не поддерживает reserved.');
      expect(SingBoxConfigBuilder.unsupportedReason(WireGuardParser.parseConf(awg3)), isNull);
    });
  });
}
