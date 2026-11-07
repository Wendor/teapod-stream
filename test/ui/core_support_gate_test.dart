import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/cores/core_resolver.dart';
import 'package:teapodstream/core/models/core_kind.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/protocols/xray/xray_rust_backend.dart';
import 'package:teapodstream/providers/core_provider.dart';
import 'package:teapodstream/ui/widgets/core_support_gate.dart';

final _raw = VpnConfig.fromJson({
  ...VpnConfig(
    id: 'r', name: 'r', protocol: VpnProtocol.vless, address: '1.2.3.4', port: 443,
    uuid: '11111111-2222-4333-8444-555555555555', security: VpnSecurity.tls,
    transport: VpnTransport.tcp, createdAt: DateTime(2026),
  ).toJson(),
  'rawXrayConfig': '{"outbounds":[]}',
});

Widget _host(Set<CoreKind> available) => ProviderScope(
      overrides: [
        coreResolverProvider.overrideWithValue(CoreResolver(const AppSettings(), available, coreBackendFor)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: CoreSupportGate(config: _raw, child: const Text('row')),
        ),
      ),
    );

void main() {
  testWidgets('profile no core can run is dimmed with the reason', (tester) async {
    await tester.pumpWidget(_host({CoreKind.xrayRust}));
    expect(find.text(const XrayRustBackend().checkConfig(_raw)!), findsOneWidget);
    expect(find.byType(Opacity), findsOneWidget);
  });

  testWidgets('profile some core can run is untouched', (tester) async {
    await tester.pumpWidget(_host({CoreKind.xrayRust, CoreKind.xrayGo}));
    expect(find.byType(Opacity), findsNothing);
    expect(find.text('row'), findsOneWidget);
  });
}
