// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class BreadcrumbBar extends StatelessWidget {
  final TeapodTokens t;
  final String parent;
  final String current;
  final VoidCallback? onBack;

  const BreadcrumbBar({super.key, required this.t, required this.parent, required this.current, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onBack ?? () => Navigator.pop(context),
        child: Container(
          // The whole bar is the back button: at least 48 dp tall.
          constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.lineSoft)),
          ),
          child: Row(
            children: [
              Text('‹', style: AppTheme.mono(size: 12, color: t.textMuted)),
              const SizedBox(width: 8),
              Text(parent, style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
              const SizedBox(width: 6),
              Text('/', style: AppTheme.mono(size: 10, color: t.textMuted)),
              const SizedBox(width: 6),
              Text(current, style: AppTheme.mono(size: 10, color: t.text, letterSpacing: 1)),
            ],
          ),
        ),
      ),
    );
  }
}
