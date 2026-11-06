import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/cores/core_backend.dart';
import 'package:teapodstream/core/cores/core_resolver.dart';
import 'package:teapodstream/core/models/core_kind.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/providers/core_provider.dart';
import 'package:teapodstream/ui/widgets/feature_gate.dart';

Widget _host(AppSettings settings, VoidCallback onTap) => ProviderScope(
      overrides: [
        coreResolverProvider
            .overrideWithValue(CoreResolver(settings, CoreKind.values.toSet(), coreBackendFor)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: FeatureGate(
            feature: CoreFeature.mux,
            child: TextButton(onPressed: onTap, child: const Text('mux')),
          ),
        ),
      ),
    );

void main() {
  testWidgets('setting stays usable and names the enabled cores that ignore it', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(const AppSettings(), () => taps++));
    await tester.tap(find.text('mux'));
    expect(taps, 1);
    expect(find.text('Не поддерживается: sing-box, Xray (Rust).'), findsOneWidget);
  });

  testWidgets('disabled cores are not listed', (tester) async {
    await tester.pumpWidget(
        _host(const AppSettings(disabledCores: {CoreKind.xrayRust, CoreKind.singBox}), () {}));
    expect(find.textContaining('Не поддерживается'), findsNothing);
  });
}
