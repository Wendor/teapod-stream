part of 'routing_screen.dart';

class _SectionHeader extends StatelessWidget {
  final TeapodTokens t;
  final String addr;
  final String label;
  const _SectionHeader({required this.t, required this.addr, required this.label});

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

// ── Mode selector ─────────────────────────────────────────────────

class _ModeSelector extends StatelessWidget {
  final TeapodTokens t;
  final RoutingSettings routing;
  final bool locked;
  final void Function(RoutingSettings) onUpdate;

  const _ModeSelector({required this.t, required this.routing, required this.locked, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final opts = [
      (RoutingDirection.global, 'FULL', l.routingModeAll),
      (RoutingDirection.bypass, 'BYPASS', l.routingModeRules),
      (RoutingDirection.onlySelected, 'ONLY', l.routingModeMatch),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: t.line)),
        child: Row(
          children: opts.asMap().entries.map((e) {
            final idx = e.key;
            final (dir, lab, sub) = e.value;
            final active = routing.direction == dir;
            return Expanded(
              child: GestureDetector(
                onTap: locked ? null : () => onUpdate(routing.copyWith(direction: dir)),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                  decoration: BoxDecoration(
                    color: active ? t.accentSoft : Colors.transparent,
                    border: Border(right: idx < opts.length - 1 ? BorderSide(color: t.line) : BorderSide.none),
                  ),
                  child: Stack(
                    children: [
                      if (active) ...[
                        Positioned(top: -1, left: -1, child: _NotchTick(color: t.accent, topLeft: true)),
                        Positioned(bottom: -1, right: -1, child: _NotchTick(color: t.accent, topLeft: false)),
                      ],
                      Column(
                        children: [
                          Text(
                            lab,
                            style: AppTheme.mono(size: 12, color: active ? t.accent : t.text, letterSpacing: 1),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            sub,
                            style: AppTheme.mono(size: 9, color: t.textMuted, letterSpacing: 0.5),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Toggle with chips ─────────────────────────────────────────────

class _ToggleWithChips extends StatelessWidget {
  final TeapodTokens t;
  final String subLabel;
  final int count;
  final bool enabled;
  final bool locked;
  final bool last;
  final String? hint;
  final void Function(bool) onToggle;
  final List<String> chips;
  final List<String>? chipKeys;
  final void Function(String)? onRemove;
  final VoidCallback? onAdd;
  final String addLabel;

  const _ToggleWithChips({
    required this.t,
    required this.subLabel,
    required this.count,
    required this.enabled,
    required this.locked,
    required this.onToggle,
    required this.chips,
    required this.addLabel,
    this.hint,
    this.chipKeys,
    this.onRemove,
    this.onAdd,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: last ? t.line : t.lineSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sublabel + toggle row
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          subLabel.toUpperCase(),
                          style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1),
                        ),
                        const SizedBox(width: 10),
                        Text('$count', style: AppTheme.mono(size: 10, color: t.textDim)),
                      ],
                    ),
                    SetSquareSwitch(t: t, value: enabled, onChanged: locked ? null : (v) => onToggle(v)),
                  ],
                ),
                if (hint != null) ...[
                  const SizedBox(height: 3),
                  Text(hint!, style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 0.5)),
                ],
              ],
            ),
          ),
          if (enabled) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < chips.length; i++)
                    _SquareChip(
                      t: t,
                      label: chips[i],
                      active: true,
                      onTap: onRemove != null ? () => onRemove!(chipKeys != null ? chipKeys![i] : chips[i]) : null,
                      showDelete: true,
                    ),
                  if (onAdd != null) _SquareChip(t: t, label: addLabel, ghost: true, onTap: onAdd),
                ],
              ),
            ),
          ] else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Row toggle ────────────────────────────────────────────────────

class _RowToggle extends StatelessWidget {
  final TeapodTokens t;
  final String title;
  final String? hint;
  final bool value;
  final bool locked;
  final bool last;
  final void Function(bool) onChange;

  const _RowToggle({
    required this.t,
    required this.title,
    required this.value,
    required this.locked,
    required this.onChange,
    this.hint,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    // The whole row toggles, as in settings.
    return Pressable(
      onTap: locked ? null : () => onChange(!value),
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
                    Text(hint!, style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 0.5)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 14),
            SetSquareSwitch(t: t, value: value, onChanged: locked ? null : (v) => onChange(v)),
          ],
        ),
      ),
    );
  }
}

// ── Square chip ───────────────────────────────────────────────────

class _SquareChip extends StatelessWidget {
  final TeapodTokens t;
  final String label;
  final bool active;
  final bool ghost;
  final bool showDelete;
  final VoidCallback? onTap;

  const _SquareChip({
    required this.t,
    required this.label,
    this.active = false,
    this.ghost = false,
    this.showDelete = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = active
        ? t.accent
        : ghost
        ? t.line
        : t.line;
    final textColor = active
        ? t.accent
        : ghost
        ? t.textMuted
        : t.textDim;
    final bgColor = active ? t.accentSoft : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bgColor,
          border: ghost
              ? Border.all(color: borderColor, style: BorderStyle.solid, width: 0.5)
              : Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: AppTheme.mono(size: 11, color: textColor, letterSpacing: 0.5)),
            if (showDelete && onTap != null) ...[
              const SizedBox(width: 5),
              Icon(Icons.close, size: 10, color: textColor),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Notch tick (summary square corner) ───────────────────────────

class _NotchTick extends StatelessWidget {
  final Color color;
  final bool topLeft;
  const _NotchTick({required this.color, required this.topLeft});

  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(5, 5), painter: _NotchPainter(color, topLeft));
}

class _NotchPainter extends CustomPainter {
  final Color color;
  final bool topLeft;
  const _NotchPainter(this.color, this.topLeft);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    if (topLeft) {
      canvas.drawLine(Offset.zero, Offset(size.width, 0), p);
      canvas.drawLine(Offset.zero, Offset(0, size.height), p);
    } else {
      canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), p);
      canvas.drawLine(Offset(size.width, 0), Offset(size.width, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_NotchPainter old) => old.color != color;
}

// ── Picker bottom sheet shell ─────────────────────────────────────
