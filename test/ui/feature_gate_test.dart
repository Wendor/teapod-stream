import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/cores/core_backend.dart';
import 'package:teapodstream/protocols/xray/xray_go_backend.dart';
import 'package:teapodstream/protocols/xray/xray_rust_backend.dart';
import 'package:teapodstream/ui/widgets/feature_gate.dart';

Widget _host(CoreBackend backend, VoidCallback onTap) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: FeatureGate(
            feature: CoreFeature.mux,
            backend: backend,
            child: TextButton(onPressed: onTap, child: const Text('mux')),
          ),
        ),
      ),
    );

void main() {
  testWidgets('unsupported feature is disabled with its reason', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(const XrayRustBackend(), () => taps++));
    await tester.tap(find.text('mux'), warnIfMissed: false);
    expect(taps, 0);
    expect(find.text(const XrayRustBackend().unavailableReason(CoreFeature.mux)!), findsOneWidget);
  });

  testWidgets('supported feature is untouched', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(const XrayGoBackend(), () => taps++));
    await tester.tap(find.text('mux'));
    expect(taps, 1);
    expect(find.textContaining('Mux недоступен'), findsNothing);
  });

  testWidgets('an unsupported value that is on can still be turned off', (tester) async {
    var taps = 0;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: FeatureGate(
            feature: CoreFeature.proxyOnly,
            backend: const XrayRustBackend(),
            allowTurnOff: true,
            child: TextButton(onPressed: () => taps++, child: const Text('proxy')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('proxy'));
    expect(taps, 1);
    expect(find.text(const XrayRustBackend().unavailableReason(CoreFeature.proxyOnly)!), findsOneWidget);
  });
}
