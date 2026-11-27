part of 'routing_screen.dart';

class _PickerShell extends StatelessWidget {
  final TeapodTokens t;
  final String title;
  final VoidCallback onDone;
  final Widget child;

  const _PickerShell({required this.t, required this.title, required this.onDone, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: t.bgElev,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.line)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                TapTarget(
                  onTap: onDone,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    color: t.accent,
                    child: Text(context.l10n.commonDone, style: AppTheme.mono(size: 10, color: t.bg, letterSpacing: 1)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _PickerSubLabel extends StatelessWidget {
  final TeapodTokens t;
  final String label;
  const _PickerSubLabel({required this.t, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.lineSoft)),
      ),
      child: Text(label.toUpperCase(), style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final TeapodTokens t;
  final String title;
  final String subtitle;
  final bool value;
  final void Function(bool) onChanged;

  const _CheckRow({
    required this.t,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SetToggleRow(
      value: value,
      checkbox: true,
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.lineSoft)),
        ),
        child: Row(
          children: [
            // Square checkbox
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                border: Border.all(color: value ? t.accent : t.line),
                color: value ? t.accent : Colors.transparent,
              ),
              child: value ? Icon(Icons.check, size: 12, color: t.bg) : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTheme.sans(size: 14, color: t.text)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 0.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomInputRow extends StatelessWidget {
  final TeapodTokens t;
  final TextEditingController ctrl;
  final String hint;
  final VoidCallback onAdd;
  final VoidCallback? onSubmit;

  const _CustomInputRow({required this.t, required this.ctrl, required this.hint, required this.onAdd, this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              onSubmitted: (_) => (onSubmit ?? onAdd)(),
              style: AppTheme.mono(size: 13, color: t.text),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: AppTheme.mono(size: 12, color: t.textMuted),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
                constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: t.line),
                  borderRadius: BorderRadius.zero,
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: t.accent),
                  borderRadius: BorderRadius.zero,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TapTarget(
            onTap: onAdd,
            label: hint,
            child: Container(
              width: 40,
              height: 40,
              color: t.accent,
              child: Icon(Icons.add, size: 16, color: t.bg),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Geo update row ────────────────────────────────────────────────
