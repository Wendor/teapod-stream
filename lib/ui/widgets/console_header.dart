import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class ConsoleHeader extends StatelessWidget {
  final TeapodTokens t;
  final String section;
  final Widget? trailing;

  const ConsoleHeader({
    super.key,
    required this.t,
    required this.section,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'teapod.stream // $section',
            style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
