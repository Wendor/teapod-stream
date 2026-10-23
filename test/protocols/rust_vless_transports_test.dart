import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/constants/core_features.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/protocols/xray/rust_config_builder.dart';
import 'package:teapodstream/protocols/xray/vless_parser.dart';

const options = VpnEngineOptions(
  socksPort: 10808,
  httpPort: 0,
  socksUser: '',
  socksPassword: '',
);

String link(
  String transport,
  String security, {
  String flow = '',
  String extra = '',
}) =>
    'vless://11111111-2222-4333-8444-555555555555@server.example:443'
    '?type=$transport&security=$security&encryption=none&flow=$flow&fp=firefox'
    '&sni=cover.example&pbk=${base64Url.encode(List.filled(32, 7)).replaceAll('=', '')}'
    '&sid=1234abcd&host=server.example&path=%2Ftunnel&serviceName=grpc-service$extra';

void main() {
  for (final security in ['tls', 'reality']) {
    for (final transport in ['tcp', 'raw', 'grpc', 'xhttp', 'splithttp']) {
      test('preserves VLESS $transport + $security', () {
        final config = VlessParser.parseUri(link(transport, security))!;
        expect(RustConfigBuilder.supports(config), isTrue);
        final json = RustConfigBuilder.build(config, options);
        final stream =
            (json['outbounds'] as List).first['streamSettings'] as Map;
        expect(stream['security'], security);
        final expected = switch (transport) {
          'raw' => 'tcp',
          'splithttp' => 'xhttp',
          _ => transport,
        };
        expect(stream['network'], expected);
        expect(stream.containsKey('xhttpSettings'), expected == 'xhttp');
        expect(stream['${security}Settings']['serverName'], 'cover.example');
        if (transport == 'grpc') {
          expect(stream['grpcSettings']['serviceName'], 'grpc-service');
        }
      });
    }
    // xray-rust 0.8.0 fixed Vision direct mode beneath plain TLS on RAW.
    for (final flow in RustConfigBuilder.visionFlows) {
      test('preserves $flow over TCP + $security', () {
        final config = VlessParser.parseUri(link('tcp', security, flow: flow))!;
        final json = RustConfigBuilder.build(config, options);
        final outbound = (json['outbounds'] as List).first;
        expect(outbound['settings']['vnext'][0]['users'][0]['flow'], flow);
        expect(outbound['streamSettings']['network'], 'tcp');
        expect(
          outbound['streamSettings'].containsKey('xhttpSettings'),
          isFalse,
        );
        expect(outbound.containsKey('mux'), isFalse);
      });
    }
  }

  for (final transport in ['ws', 'websocket', 'httpupgrade']) {
    test('preserves $transport + TLS path and host', () {
      final config = VlessParser.parseUri(link(transport, 'tls'))!;
      final json = RustConfigBuilder.build(config, options);
      final stream = (json['outbounds'] as List).first['streamSettings'];
      final name = transport == 'httpupgrade' ? 'httpupgrade' : 'ws';
      expect(stream['network'], name);
      expect(stream['${name}Settings']['path'], '/tunnel');
      expect(stream.containsKey('xhttpSettings'), isFalse);
    });
  }

  test('rejects incompatible transport/security/flow combinations', () {
    for (final uri in [
      link('ws', 'reality'),
      link('httpupgrade', 'reality'),
      for (final security in ['tls', 'reality'])
        for (final t in ['ws', 'grpc', 'httpupgrade', 'xhttp'])
          link(t, security, flow: 'xtls-rprx-vision'),
      link('tcp', 'tls', extra: '&headerType=http'),
      link('tcp', 'tls', extra: '&ech=AEX%2B'),
      link('tcp', 'none'),
      link('kcp', 'tls'),
      link('quic', 'tls'),
      link('h2', 'tls'),
      link('tcp', 'reality', flow: 'xtls-rprx-direct'),
      link('tcp', 'tls', extra: '&allowInsecure=1'),
    ]) {
      final config = VlessParser.parseUri(uri)!;
      expect(RustConfigBuilder.supports(config), isFalse, reason: uri);
      expect(
        () => RustConfigBuilder.build(config, options),
        throwsFormatException,
      );
    }
  });

  test('maps certificate pins into the Rust TLS field', () {
    final pin = base64.encode(List.filled(32, 42));
    final config = VlessParser.parseUri(
      link('tcp', 'tls', extra: '&pinSHA256=${Uri.encodeComponent(pin)}'),
    )!;
    final json = RustConfigBuilder.build(config, options);
    final tls =
        (json['outbounds'] as List).first['streamSettings']['tlsSettings'];
    expect(tls['pinnedPeerCertSha256'], List.filled(32, '2a').join());
    expect(tls['allowInsecure'], isFalse);
  });

  test('Vision over TLS keeps its flow and leaves UDP/443 to the core', () {
    for (final flow in RustConfigBuilder.visionFlows) {
      final config = VlessParser.parseUri(link('tcp', 'tls', flow: flow))!;
      expect(RustConfigBuilder.unsupportedReason(config), isNull);
      final json = RustConfigBuilder.build(
        config,
        VpnEngineOptions(
          socksPort: 10808,
          httpPort: 0,
          socksUser: '',
          socksPassword: '',
          blockQuic: CoreFeatures.rust.effectiveQuicBlock(
            requested: false,
            flow: config.flow,
          ),
        ),
      );
      final outbound = (json['outbounds'] as List).first;
      expect(outbound['settings']['vnext'][0]['users'][0]['flow'], flow);
      expect(outbound['streamSettings']['security'], 'tls');
      final rules = json['routing']['rules'] as List;
      final outbounds = json['outbounds'] as List;
      if (flow == 'xtls-rprx-vision') {
        // The core answers plain-Vision UDP/443 with ICMP port unreachable
        // itself; a blackhole rule would turn that into a silent drop.
        expect(rules.where((dynamic r) => r['outboundTag'] == 'block'), isEmpty);
        expect(
          outbounds.where((dynamic o) => o['protocol'] == 'blackhole'),
          isEmpty,
        );
      } else {
        // -udp443 gets the QUIC block, as in Go.
        expect(rules.last, {
          'type': 'field',
          'inboundTag': ['tun-in'],
          'network': 'udp',
          'port': '443',
          'outboundTag': 'block',
        });
      }
    }
  });
}
