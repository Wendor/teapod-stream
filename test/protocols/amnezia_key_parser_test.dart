import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/models/protocol_settings.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/protocols/parsers/amnezia_key_parser.dart';
import 'package:teapodstream/protocols/xray/vless_parser.dart';

const _conf = '[Interface]\nPrivateKey = yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=\nAddress = 10.8.1.2/32\n'
    'DNS = \$PRIMARY_DNS\nJc = 4\nJmin = 40\nJmax = 70\nS1 = 16\nS2 = 32\nH1 = 11\nH2 = 22\nH3 = 33\nH4 = 44\n'
    '[Peer]\nPublicKey = xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=\nEndpoint = 5.6.7.8:32153\nAllowedIPs = 0.0.0.0/0\n';

/// Ключ как у AmneziaVPN (ExportController): vpn:// + base64url(qCompress(JSON)).
String _key(Map<String, dynamic> server) {
  final json = utf8.encode(jsonEncode(server));
  final length = ByteData(4)..setUint32(0, json.length);
  final compressed = [...length.buffer.asUint8List(), ...ZLibCodec(level: 8).encode(json)];
  return 'vpn://${base64Url.encode(compressed).replaceAll('=', '')}';
}

Map<String, dynamic> _server({String? config, String? mtu}) => {
      'containers': [
        {
          'container': 'amnezia-awg',
          'awg': {
            'port': '32153',
            if (config != null) 'last_config': jsonEncode({'config': config, 'hostName': '5.6.7.8', 'mtu': ?mtu}),
          },
        },
      ],
      'defaultContainer': 'amnezia-awg',
      'description': 'My Amnezia',
      'hostName': '5.6.7.8',
    };

void main() {
  test('vpn:// key with an AWG client config', () {
    final c = AmneziaKeyParser.parse(_key(_server(config: _conf)))!;
    expect(c.protocol, VpnProtocol.wireguard);
    expect(c.name, 'My Amnezia');
    expect(c.address, '5.6.7.8');
    expect(c.port, 32153);
    final wg = c.protocolSettings! as WireGuardSettings;
    expect(wg.amnezia?.s2, 32);
    expect(wg.amnezia?.h4, '44');
    expect(VlessParser.parseUri(_key(_server(config: _conf)))?.protocol, VpnProtocol.wireguard);
  });

  test('MTU from last_config when the config text has none', () {
    WireGuardSettings wg(String conf, String? mtu) =>
        AmneziaKeyParser.parse(_key(_server(config: conf, mtu: mtu)))!.protocolSettings! as WireGuardSettings;
    expect(wg(_conf, '1376').mtu, 1376);
    expect(wg(_conf.replaceFirst('[Peer]', 'MTU = 1280\n[Peer]'), '1376').mtu, 1280);
    expect(wg(_conf, null).mtu, isNull);
  });

  test('keys without a client config or garbage are not imported', () {
    expect(AmneziaKeyParser.parse(_key(_server())), isNull);
    expect(AmneziaKeyParser.parse('vpn://not-a-key'), isNull);
    expect(AmneziaKeyParser.parse('vless://x'), isNull);
  });
}
