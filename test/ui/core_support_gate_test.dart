import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/cores/core_backend.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/protocols/xray/xray_go_backend.dart';
import 'package:teapodstream/protocols/xray/xray_rust_backend.dart';
import 'package:teapodstream/ui/widgets/core_support_gate.dart';

final _raw = VpnConfig.fromJson({
  ...VpnConfig(
    id: 'r', name: 'r', protocol: VpnProtocol.vless, address: '1.2.3.4', port: 443,
    uuid: '11111111-2222-4333-8444-555555555555', security: VpnSecurity.tls,
    transport: VpnTransport.tcp, createdAt: DateTime(2026),
  ).toJson(),
  'rawXrayConfig': '{"outbounds":[]}',
});

Widget _host(CoreBackend backend) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: CoreSupportGate(config: _raw, backend: backend, child: const Text('row')),
        ),
      ),
    );

void main() {
  testWidgets('unsupported profile is dimmed with the reason', (tester) async {
    await tester.pumpWidget(_host(const XrayRustBackend()));
    expect(find.text(const XrayRustBackend().checkConfig(_raw)!), findsOneWidget);
    expect(find.byType(Opacity), findsOneWidget);
  });

  testWidgets('supported profile is untouched', (tester) async {
    await tester.pumpWidget(_host(const XrayGoBackend()));
    expect(find.byType(Opacity), findsNothing);
    expect(find.text('row'), findsOneWidget);
  });
}
