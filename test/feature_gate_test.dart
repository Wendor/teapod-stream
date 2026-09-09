import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/constants/core_features.dart';
import 'package:teapodstream/ui/widgets/feature_gate.dart';

void main() {
  testWidgets('unsupported control stays visible and cannot change its value', (
    tester,
  ) async {
    var changed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeatureGate(
            features: CoreFeatures.rust,
            feature: CoreFeature.mux,
            child: SwitchListTile(
              title: const Text('Mux'),
              value: false,
              onChanged: (_) => changed = true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Mux'), findsOneWidget);
    expect(
      find.text(CoreFeatures.rust.unavailableReason(CoreFeature.mux)),
      findsOneWidget,
    );
    await tester.tap(find.byType(Switch), warnIfMissed: false);
    expect(changed, isFalse);
  });

  testWidgets('the same control is interactive in Go', (tester) async {
    var changed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeatureGate(
            features: CoreFeatures.go,
            feature: CoreFeature.mux,
            child: SwitchListTile(
              title: const Text('Mux'),
              value: false,
              onChanged: (_) => changed = true,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(Switch));
    expect(changed, isTrue);
    expect(
      find.text(CoreFeatures.rust.unavailableReason(CoreFeature.mux)),
      findsNothing,
    );
  });

  testWidgets('an imported unsupported setting can be explicitly reset', (
    tester,
  ) async {
    var reset = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeatureGate(
            features: CoreFeatures.rust,
            feature: CoreFeature.adBlocking,
            onReset: () => reset = true,
            child: const Text('Ad blocking: on'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Сбросить неподдерживаемое значение'));
    expect(reset, isTrue);
  });
}
