// ignore: deprecated_member_use
import 'package:flutter/material.dart';

/// A caption that stays on one line at any text scale: in a box too narrow for it, it shrinks instead of wrapping
/// mid-word (a tab label, a `0x01` address, a hero title). Body text wraps; only short captions use this.
class OneLine extends StatelessWidget {
  const OneLine(this.child, {super.key, this.alignment = AlignmentDirectional.centerStart});

  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => FittedBox(fit: BoxFit.scaleDown, alignment: alignment, child: child);
}
