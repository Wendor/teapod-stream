// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/app_settings.dart' show AppSettings;
import '../../providers/profile_provider.dart';
import '../../providers/settings_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'pressable.dart';
import 'tap_target.dart';
import '../../l10n/l10n.dart';

/// Applies [change] to the settings from a screen ([SettingsNotifier.edit]): in a read-only profile shows a snackbar
/// instead of a silent no-op.
void saveSettings(BuildContext context, WidgetRef ref, AppSettings Function(AppSettings current) change) {
  if (ref.read(profileProvider).value?.isReadonly == true) return showReadonlySnack(context);
  ref.read(settingsProvider.notifier).edit(change);
}

/// The "profile is read-only" snackbar — shared by all locked rows.
void showReadonlySnack(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(context.l10n.settingsReadonlySnack), duration: const Duration(seconds: 2)));
}

// ── Row: toggle ───────────────────────────────────────────────────

class SetRowToggle extends StatelessWidget {
  final TeapodTokens t;
  final String title;
  final String? hint;
  final bool value;
  final bool locked;
  final void Function(bool) onChange;

  const SetRowToggle({
    super.key,
    required this.t,
    required this.title,
    required this.value,
    required this.onChange,
    this.locked = false,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return SetToggleRow(
      value: value,
      onTap: locked ? () => showReadonlySnack(context) : () => onChange(!value),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.lineSoft)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTheme.sans(size: 14, color: t.text)),
                  if (hint != null) ...[
                    const SizedBox(height: 3),
                    Text(hint!, style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 0.5)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 14),
            SetSquareSwitch(t: t, value: value),
          ],
        ),
      ),
    );
  }
}

// ── Square switch ─────────────────────────────────────────────────

/// A square on/off switch. With [onChanged] it is its own 48 dp tap target; without it (inside a row that toggles
/// as a whole, or locked) it is only the visual.
class SetSquareSwitch extends StatelessWidget {
  final TeapodTokens t;
  final bool value;
  final void Function(bool)? onChanged;

  const SetSquareSwitch({super.key, required this.t, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final visual = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 44,
      height: 22,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(color: value ? t.accent : t.line),
        color: value ? t.accentSoft : Colors.transparent,
      ),
      child: Align(
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 14,
          height: 14,
          color: value ? t.accent : t.textMuted,
        ),
      ),
    );
    if (onChanged == null) return visual;
    return TapTarget(onTap: () => onChanged!(!value), toggled: value, child: visual);
  }
}

/// A row that toggles as a whole: one tap target, announced as a switch with its [child]'s text.
class SetToggleRow extends StatelessWidget {
  final bool value;
  final VoidCallback? onTap;

  /// The row's visual is a checkbox: announced as checked / not checked rather than as a switch.
  final bool checkbox;
  final Widget child;

  const SetToggleRow({super.key, required this.value, required this.onTap, this.checkbox = false, required this.child});

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      toggled: checkbox ? null : value,
      checked: checkbox ? value : null,
      child: Pressable(onTap: onTap, child: child),
    ),
  );
}

// ── Row: chevron ──────────────────────────────────────────────────

class SetRowChev extends StatelessWidget {
  final TeapodTokens t;
  final String title;
  final String? hint;
  final bool locked;
  final bool last;
  final VoidCallback? onTap;

  const SetRowChev({
    super.key,
    required this.t,
    required this.title,
    this.locked = false,
    this.hint,
    this.last = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: locked ? () => showReadonlySnack(context) : onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: last ? t.line : t.lineSoft)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTheme.sans(size: 14, color: t.text)),
                  if (hint != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      hint!,
                      style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 0.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('›', style: AppTheme.mono(size: 16, color: t.textMuted)),
          ],
        ),
      ),
    );
  }
}

// ── Row: inline field ─────────────────────────────────────────────

class SetInlineField extends StatelessWidget {
  final TeapodTokens t;
  final String label;
  final Widget child;
  final bool locked;
  const SetInlineField({super.key, required this.t, required this.label, required this.child, this.locked = false});

  @override
  Widget build(BuildContext context) {
    final row = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.lineSoft)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(label, style: AppTheme.sans(size: 14, color: t.text)),
          child,
        ],
      ),
    );
    if (!locked) return row;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => showReadonlySnack(context), child: row);
  }
}

// ── Text fields that save once per edit ──────────────────────────

/// A settings text field that hands its text to [onCommit] once per edit — on submit, when it loses focus and when it
/// goes away (the screen closed with the keyboard up) — and only when the text changed since the last commit. Each
/// commit writes the whole profile list, so not on every key.
class _CommitField extends StatefulWidget {
  final TeapodTokens t;
  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final void Function(String) onCommit;
  final double width;
  final double fontSize;
  final TextAlign textAlign;
  final bool obscureText;
  final bool digitsOnly;

  const _CommitField({
    required this.t,
    required this.controller,
    required this.enabled,
    required this.hint,
    required this.onCommit,
    required this.width,
    required this.fontSize,
    required this.textAlign,
    this.obscureText = false,
    this.digitsOnly = false,
  });

  @override
  State<_CommitField> createState() => _CommitFieldState();
}

class _CommitFieldState extends State<_CommitField> {
  final _focus = FocusNode();
  late String _committed;

  @override
  void initState() {
    super.initState();
    _committed = widget.controller.text;
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void dispose() {
    _commit();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final text = widget.controller.text;
    if (text == _committed) return;
    _committed = text;
    widget.onCommit(text);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        enabled: widget.enabled,
        obscureText: widget.obscureText,
        textAlign: widget.textAlign,
        keyboardType: widget.digitsOnly ? TextInputType.number : null,
        inputFormatters: widget.digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
        onSubmitted: (_) => _commit(),
        onEditingComplete: () => FocusScope.of(context).unfocus(),
        style: AppTheme.mono(size: widget.fontSize, color: t.text),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: AppTheme.mono(size: widget.fontSize - 1, color: t.textMuted),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          isDense: true,
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: t.line),
            borderRadius: BorderRadius.zero,
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: t.accent),
            borderRadius: BorderRadius.zero,
          ),
          disabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: t.lineSoft),
            borderRadius: BorderRadius.zero,
          ),
        ),
      ),
    );
  }
}

/// Text setting (credentials, ranges, URL); [onCommit] once per edit.
class SetCredField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final bool obscureText;
  final void Function(String) onCommit;
  final TeapodTokens t;
  final double width;
  final double fontSize;
  final TextAlign textAlign;

  const SetCredField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.hint,
    required this.onCommit,
    required this.t,
    this.obscureText = false,
    this.width = 140,
    this.fontSize = 12,
    this.textAlign = TextAlign.end,
  });

  @override
  Widget build(BuildContext context) => _CommitField(
    t: t,
    controller: controller,
    enabled: enabled,
    hint: hint,
    onCommit: onCommit,
    width: width,
    fontSize: fontSize,
    textAlign: textAlign,
    obscureText: obscureText,
  );
}

/// Compact numeric setting (port, MTU, intervals); [onCommit] once per edit.
class SetNumField extends StatelessWidget {
  final TeapodTokens t;
  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final void Function(String) onCommit;

  const SetNumField({
    super.key,
    required this.t,
    required this.controller,
    required this.enabled,
    required this.hint,
    required this.onCommit,
  });

  @override
  Widget build(BuildContext context) => _CommitField(
    t: t,
    controller: controller,
    enabled: enabled,
    hint: hint,
    onCommit: onCommit,
    width: 90,
    fontSize: 13,
    textAlign: TextAlign.center,
    digitsOnly: true,
  );
}

// ── Segmented square selector ─────────────────────────────────────

class SetSegSquare extends StatelessWidget {
  final TeapodTokens t;
  final String value;
  final List<(String, String)> opts;
  final bool locked;
  final void Function(String) onChanged;

  const SetSegSquare({
    super.key,
    required this.t,
    required this.value,
    required this.opts,
    required this.onChanged,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    // Each segment draws its own border, so the 48 dp tap height around it stays transparent. The labels are capped
    // at 1.5× so the selector fits on its own line at the largest text scale; the tap targets are not scaled.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.5,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: opts.asMap().entries.map((e) {
          final idx = e.key;
          final (val, lab) = e.value;
          final active = value == val;
          final side = BorderSide(color: t.line);
          return TapTarget(
            onTap: locked ? () => showReadonlySnack(context) : () => onChanged(val),
            selected: active,
            minWidth: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              constraints: const BoxConstraints(minWidth: kMinInteractiveDimension),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: active ? t.accentSoft : Colors.transparent,
                border: Border(top: side, bottom: side, right: side, left: idx == 0 ? side : BorderSide.none),
              ),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: AppTheme.mono(size: 11, color: active ? t.accent : t.textDim, letterSpacing: 0.5),
                child: Text(lab),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class SetSectionHeader extends StatelessWidget {
  final TeapodTokens t;
  final String addr;
  final String label;
  const SetSectionHeader({super.key, required this.t, required this.addr, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.lineSoft)),
      ),
      child: Row(
        children: [
          Text(addr, style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
          const SizedBox(width: 8),
          Text('·', style: AppTheme.mono(size: 10, color: t.textMuted)),
          const SizedBox(width: 8),
          Text(label.toUpperCase(), style: AppTheme.mono(size: 10, color: t.textDim, letterSpacing: 1)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '—' * 16,
              style: AppTheme.mono(size: 10, color: t.textMuted),
              overflow: TextOverflow.clip,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class SetCornerTicks extends StatelessWidget {
  final TeapodTokens t;
  final Color color;
  const SetCornerTicks({super.key, required this.t, required this.color});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(top: 6, left: 6, child: _SmallTick(color: color, tl: true)),
            Positioned(top: 6, right: 6, child: _SmallTick(color: color, tr: true)),
            Positioned(bottom: 6, left: 6, child: _SmallTick(color: color, bl: true)),
            Positioned(bottom: 6, right: 6, child: _SmallTick(color: color, br: true)),
          ],
        ),
      ),
    );
  }
}

class _SmallTick extends StatelessWidget {
  final Color color;
  final bool tl, tr, bl, br;
  const _SmallTick({required this.color, this.tl = false, this.tr = false, this.bl = false, this.br = false});

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(8, 8),
    painter: _SmallTickPainter(color: color, tl: tl, tr: tr, bl: bl, br: br),
  );
}

class _SmallTickPainter extends CustomPainter {
  final Color color;
  final bool tl, tr, bl, br;
  const _SmallTickPainter({
    required this.color,
    required this.tl,
    required this.tr,
    required this.bl,
    required this.br,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final w = size.width;
    final h = size.height;
    if (tl) {
      canvas.drawLine(Offset.zero, Offset(w, 0), p);
      canvas.drawLine(Offset.zero, Offset(0, h), p);
    }
    if (tr) {
      canvas.drawLine(Offset(0, 0), Offset(w, 0), p);
      canvas.drawLine(Offset(w, 0), Offset(w, h), p);
    }
    if (bl) {
      canvas.drawLine(Offset(0, h), Offset(w, h), p);
      canvas.drawLine(Offset(0, 0), Offset(0, h), p);
    }
    if (br) {
      canvas.drawLine(Offset(0, h), Offset(w, h), p);
      canvas.drawLine(Offset(w, 0), Offset(w, h), p);
    }
  }

  @override
  bool shouldRepaint(_SmallTickPainter old) => old.color != color;
}
