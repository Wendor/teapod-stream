// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

// Every dialog is a plain `AlertDialog`: its frame, title and body text come from `dialogTheme`, the buttons from
// `textButtonTheme` (app_theme.dart). These parts cover what a theme can't: the button colour by role and the field.

/// The button that closes a dialog without acting; pops [result].
class DialogCancel extends StatelessWidget {
  const DialogCancel({super.key, this.result});

  final Object? result;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    return TextButton(
      onPressed: () => Navigator.pop(context, result),
      style: TextButton.styleFrom(foregroundColor: t.textMuted),
      child: Text(context.l10n.commonCancel),
    );
  }
}

/// A dialog's acting button in the accent colour, or in the danger colour when [danger] (deletes or lowers security).
class DialogAction extends StatelessWidget {
  const DialogAction(this.label, {super.key, required this.onPressed, this.danger = false});

  final String label;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    return TextButton(
      onPressed: onPressed,
      style: danger ? TextButton.styleFrom(foregroundColor: t.danger) : null,
      child: Text(label),
    );
  }
}

/// A text field in a dialog: the theme's outlined box, dense, at least 48 dp high.
InputDecoration dialogField({String? hint, String? label}) => InputDecoration(
  hintText: hint,
  labelText: label,
  isDense: true,
  contentPadding: const EdgeInsets.all(10),
  constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
);

/// The text style of a dialog's text field.
TextStyle dialogFieldStyle(BuildContext context) =>
    AppTheme.mono(size: 13, color: Theme.of(context).extension<TeapodTokens>()!.text);
