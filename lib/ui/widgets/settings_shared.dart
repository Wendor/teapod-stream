import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'pressable.dart';

/// Снэкбар «профиль только для чтения» — единый для всех заблокированных рядов.
void showReadonlySnack(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(
      content: Text('Профиль только для чтения'),
      duration: Duration(seconds: 2),
    ));
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
    return Pressable(
      onTap: locked ? () => showReadonlySnack(context) : () => onChange(!value),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.lineSoft))),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTheme.sans(size: 14, color: t.text)),
                  if (hint != null) ...[
                    const SizedBox(height: 3),
                    Text(hint!,
                        style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 0.5)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 14),
            SetSquareSwitch(
              t: t,
              value: value,
              onChanged: locked ? null : (v) => onChange(v),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Square switch ─────────────────────────────────────────────────

class SetSquareSwitch extends StatelessWidget {
  final TeapodTokens t;
  final bool value;
  final void Function(bool)? onChanged;

  const SetSquareSwitch({super.key, required this.t, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged != null ? () => onChanged!(!value) : null,
      child: AnimatedContainer(
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
      ),
    );
  }
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
            border: Border(bottom: BorderSide(color: last ? t.line : t.lineSoft))),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTheme.sans(size: 14, color: t.text)),
                  if (hint != null) ...[
                    const SizedBox(height: 3),
                    Text(hint!,
                        style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 0.5),
                        overflow: TextOverflow.ellipsis),
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
  const SetInlineField({
    super.key,
    required this.t,
    required this.label,
    required this.child,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final row = Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.lineSoft))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTheme.sans(size: 14, color: t.text)),
          child,
        ],
      ),
    );
    if (!locked) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showReadonlySnack(context),
      child: row,
    );
  }
}

// ── Cred text field ───────────────────────────────────────────────

class SetCredField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final bool obscureText;
  final void Function(String) onChanged;
  final TeapodTokens t;

  const SetCredField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.hint,
    required this.onChanged,
    required this.t,
    this.obscureText = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: TextField(
        controller: controller,
        enabled: enabled,
        obscureText: obscureText,
        textAlign: TextAlign.end,
        onChanged: onChanged,
        onEditingComplete: () => FocusScope.of(context).unfocus(),
        style: AppTheme.mono(size: 12, color: t.text),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTheme.mono(size: 11, color: t.textMuted),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          isDense: true,
          enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: t.line), borderRadius: BorderRadius.zero),
          focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: t.accent), borderRadius: BorderRadius.zero),
          disabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: t.lineSoft), borderRadius: BorderRadius.zero),
        ),
      ),
    );
  }
}

// ── Compact numeric text field (порт, MTU, интервалы) ────────────

class SetNumField extends StatelessWidget {
  final TeapodTokens t;
  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final void Function(String) onChanged;

  const SetNumField({
    super.key,
    required this.t,
    required this.controller,
    required this.enabled,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      child: TextField(
        controller: controller,
        enabled: enabled,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: onChanged,
        onEditingComplete: () => FocusScope.of(context).unfocus(),
        style: AppTheme.mono(size: 13, color: t.text),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTheme.mono(size: 12, color: t.textMuted),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          isDense: true,
          enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: t.line), borderRadius: BorderRadius.zero),
          focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: t.accent), borderRadius: BorderRadius.zero),
          disabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: t.lineSoft), borderRadius: BorderRadius.zero),
        ),
      ),
    );
  }
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
    return Container(
      decoration: BoxDecoration(border: Border.all(color: t.line)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: opts.asMap().entries.map((e) {
          final idx = e.key;
          final (val, lab) = e.value;
          final active = value == val;
          return GestureDetector(
            onTap: locked ? () => showReadonlySnack(context) : () => onChanged(val),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: active ? t.accentSoft : Colors.transparent,
                border: Border(
                  right: idx < opts.length - 1
                      ? BorderSide(color: t.line)
                      : BorderSide.none,
                ),
              ),
              child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: AppTheme.mono(
                      size: 11,
                      color: active ? t.accent : t.textDim,
                      letterSpacing: 0.5),
                  child: Text(lab)),
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
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.lineSoft))),
      child: Row(
        children: [
          Text(addr, style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
          const SizedBox(width: 8),
          Text('·', style: AppTheme.mono(size: 10, color: t.textMuted)),
          const SizedBox(width: 8),
          Text(label.toUpperCase(),
              style: AppTheme.mono(size: 10, color: t.textDim, letterSpacing: 1)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('—' * 16,
                style: AppTheme.mono(size: 10, color: t.textMuted),
                overflow: TextOverflow.clip,
                maxLines: 1),
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
            Positioned(top: 6, left: 6,    child: _SmallTick(color: color, tl: true)),
            Positioned(top: 6, right: 6,   child: _SmallTick(color: color, tr: true)),
            Positioned(bottom: 6, left: 6,  child: _SmallTick(color: color, bl: true)),
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
  const _SmallTick({
    required this.color,
    this.tl = false,
    this.tr = false,
    this.bl = false,
    this.br = false,
  });

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
