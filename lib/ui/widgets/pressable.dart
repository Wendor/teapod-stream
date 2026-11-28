// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// GestureDetector with a background highlight on press (console style, no ripple). A row with [onTap] is announced as
/// a button.
class Pressable extends StatefulWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Highlight color; `TeapodTokens.accentFade` by default.
  final Color? pressedColor;
  final Widget child;

  const Pressable({super.key, this.onTap, this.onLongPress, this.pressedColor, required this.child});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    final color = widget.pressedColor ?? t.accentFade;
    final interactive = widget.onTap != null || widget.onLongPress != null;
    return Semantics(
      button: widget.onTap != null,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: interactive ? (_) => _set(true) : null,
        onTapUp: interactive ? (_) => _set(false) : null,
        onTapCancel: interactive ? () => _set(false) : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          color: _pressed ? color : Colors.transparent,
          child: widget.child,
        ),
      ),
    );
  }
}
