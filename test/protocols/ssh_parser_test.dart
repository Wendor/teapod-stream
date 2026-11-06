import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/protocol_settings.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/protocols/parsers/ssh_parser.dart';
import 'package:teapodstream/protocols/singbox/singbox_outbound.dart';
import 'package:teapodstream/protocols/xray/vless_parser.dart';

const _pem = '-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjE=\n-----END OPENSSH PRIVATE KEY-----\n';

SshSettings _ssh(VpnConfig c) => c.protocolSettings! as SshSettings;

void main() {
  test('password login', () {
    final c = SshParser.parseUri('ssh://root:p%40ss@1.2.3.4:2222#Box%20SSH')!;
    expect(c.protocol, VpnProtocol.ssh);
    expect([c.address, c.port, c.name], ['1.2.3.4', 2222, 'Box SSH']);
    expect(_ssh(c).user, 'root');
    expect(_ssh(c).password, 'p@ss');
    expect(c.validate(), isNull);
    expect(VlessParser.parseUri('ssh://root:pw@h.example')?.port, 22);
    expect(SshParser.parseUri('ssh://root:pw@h.example')!.name, 'SSH h.example');
  });

  test('private key with passphrase and host keys', () {
    final c = SshParser.parseUri('ssh://deploy@h.example:22?pk=${Uri.encodeComponent(_pem)}&pkp=secret'
        '&hk=${Uri.encodeComponent('ssh-ed25519 AAAA1,ssh-rsa BBBB2')}')!;
    final s = _ssh(c);
    expect(s.privateKey, _pem);
    expect(s.privateKeyPassphrase, 'secret');
    expect(s.password, isNull);
    expect(s.hostKeys, ['ssh-ed25519 AAAA1', 'ssh-rsa BBBB2']);
  });

  test('bare key body is wrapped into an OpenSSH PEM (hiddify)', () {
    final c = SshParser.parseUri('ssh://u@h.example?pk=b3BlbnNzaC1rZXktdjE%3D')!;
    expect(_ssh(c).privateKey, _pem);
  });

  test('without password or key the link is rejected', () {
    expect(SshParser.parseUri('ssh://root@h.example:22'), isNull);
    expect(SshParser.parseUri('ssh://h.example:22'), isNull);
  });

  test('sing-box outbound', () {
    const opts = VpnEngineOptions(socksPort: 1, httpPort: 0, socksUser: '', socksPassword: '');
    expect(SingBoxOutbound.build(SshParser.parseUri('ssh://root:pw@h.example:2222?hk=k1')!, opts), {
      'type': 'ssh', 'tag': 'proxy', 'server': 'h.example', 'server_port': 2222,
      'user': 'root', 'password': 'pw', 'host_key': ['k1'],
    });
    expect(SingBoxOutbound.build(SshParser.parseUri('ssh://u@h.example?pk=b3BlbnNzaC1rZXktdjE%3D&pkp=x')!, opts), {
      'type': 'ssh', 'tag': 'proxy', 'server': 'h.example', 'server_port': 22,
      'user': 'u', 'private_key': [_pem], 'private_key_passphrase': 'x',
    });
  });
}
