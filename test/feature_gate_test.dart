import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/constants/core_features.dart';
import 'package:teapodstream/core/models/heartbeat_settings.dart';
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
      find.text(CoreFeatures.rust.unavailableReason(CoreFeature.mux)!),
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
      find.text(CoreFeatures.rust.unavailableReason(CoreFeature.mux)!),
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
            feature: CoreFeature.customMtu,
            onReset: () => reset = true,
            child: const Text('MTU: 1400'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Сбросить неподдерживаемое значение'));
    expect(reset, isTrue);
  });

  Widget tetheringToggle(
    CoreFeatures features, {
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => MaterialApp(
    home: Scaffold(
      body: FeatureGate(
        features: features,
        feature: CoreFeature.tetheringControl,
        child: SwitchListTile(
          title: const Text('Раздача через VPN'),
          value: value,
          onChanged: onChanged,
        ),
      ),
    ),
  );

  testWidgets('both cores check flow owners, so the tethering switch applies', (
    tester,
  ) async {
    for (final features in [CoreFeatures.go, CoreFeatures.rust]) {
      var changed = false;
      await tester.pumpWidget(
        tetheringToggle(
          features,
          value: false,
          onChanged: (_) => changed = true,
        ),
      );
      await tester.tap(find.byType(Switch));
      expect(changed, isTrue);
      expect(find.text('Сбросить неподдерживаемое значение'), findsNothing);
    }
  });

  testWidgets('an inert Rust control explains itself and offers no reset', (
    tester,
  ) async {
    var changed = false;
    // No stored ICMP value changes what Rust does, so there is nothing to reset.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeatureGate(
            features: CoreFeatures.rust,
            feature: CoreFeature.icmpToggle,
            child: SwitchListTile(
              title: const Text('ICMP (ping)'),
              value: true,
              onChanged: (_) => changed = true,
            ),
          ),
        ),
      ),
    );
    expect(
      find.text(CoreFeatures.rust.unavailableReason(CoreFeature.icmpToggle)!),
      findsOneWidget,
    );
    await tester.tap(find.byType(Switch), warnIfMissed: false);
    expect(changed, isFalse);
    expect(find.text('Сбросить неподдерживаемое значение'), findsNothing);
  });

  testWidgets('a stored XRAYDELAY probe stays as is in both cores', (
    tester,
  ) async {
    final feature = CoreFeatures.heartbeatProbeFeature(
      HeartbeatProbe.xrayDelay,
    )!;
    for (final features in [CoreFeatures.go, CoreFeatures.rust]) {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeatureGate(
              features: features,
              feature: feature,
              onReset: () {},
              child: TextButton(
                onPressed: () => tapped = true,
                child: const Text('XRAYDELAY'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('XRAYDELAY'));
      expect(tapped, isTrue);
      expect(find.text('Сбросить неподдерживаемое значение'), findsNothing);
    }
  });

  testWidgets('PASSIVE stays an ordinary interactive value in both cores', (
    tester,
  ) async {
    final feature = CoreFeatures.heartbeatProbeFeature(HeartbeatProbe.passive)!;
    for (final features in [CoreFeatures.go, CoreFeatures.rust]) {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeatureGate(
              features: features,
              feature: feature,
              onReset: () {},
              child: TextButton(
                onPressed: () => tapped = true,
                child: const Text('PASSIVE'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('PASSIVE'));
      expect(tapped, isTrue);
      expect(find.text('Сбросить неподдерживаемое значение'), findsNothing);
    }
  });
}
