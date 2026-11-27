// ignore: deprecated_member_use
import 'package:flutter/material.dart';

/// The text scale the app renders with: the system's (Android's font size and accessibility scaling, with its
/// non-linear curve for large sizes) times the app's own font setting, capped at [maxTextScale].
TextScaler appTextScaler(TextScaler system, double appFactor) =>
    (appFactor == 1.0 ? system : _MultipliedTextScaler(system, appFactor)).clamp(maxScaleFactor: maxTextScale);

/// The largest text scale: Android's largest font size. Layouts are checked at it on a device (the test font is wider
/// than the real ones, so widget tests can't tell a real overflow).
const maxTextScale = 2.0;

class _MultipliedTextScaler extends TextScaler {
  final TextScaler base;
  final double factor;
  const _MultipliedTextScaler(this.base, this.factor);

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) => other is _MultipliedTextScaler && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
