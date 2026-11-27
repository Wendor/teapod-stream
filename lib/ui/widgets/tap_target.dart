// ignore: deprecated_member_use
import 'package:flutter/material.dart';

/// A tap target at least 48 dp ([kMinInteractiveDimension]) on each side around a smaller visual: the extra area is
/// transparent and centres the visual, which dims while pressed. [label] names an icon-only button for TalkBack.
/// [minWidth] 0 — the visual keeps its own width (segments that join up).
class TapTarget extends StatefulWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? label;

  /// A switch's state for TalkBack; null — not a switch.
  final bool? toggled;

  /// One choice of several that is the current one (a swatch).
  final bool selected;
  final double minWidth;
  final Widget child;

  const TapTarget({
    super.key,
    required this.onTap,
    this.onLongPress,
    this.label,
    this.toggled,
    this.selected = false,
    this.minWidth = kMinInteractiveDimension,
    required this.child,
  });

  @override
  State<TapTarget> createState() => _TapTargetState();
}

class _TapTargetState extends State<TapTarget> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null || widget.onLongPress != null;
    return Semantics(
      button: widget.toggled == null,
      toggled: widget.toggled,
      selected: widget.selected,
      enabled: interactive,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: interactive ? (_) => _set(true) : null,
        onTapUp: interactive ? (_) => _set(false) : null,
        onTapCancel: interactive ? () => _set(false) : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: widget.minWidth, minHeight: kMinInteractiveDimension),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 90),
              opacity: _pressed ? 0.55 : 1,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
