part of 'configs_screen.dart';

class _ToggleTile extends StatelessWidget {
  final TeapodTokens t;
  final String label;
  final bool value;
  final void Function(bool) onChanged;

  const _ToggleTile({required this.t, required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SetToggleRow(
      value: value,
      checkbox: true,
      onTap: () => onChanged(!value),
      child: Container(
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.lineSoft)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: AppTheme.sans(size: 14, color: t.text)),
            ),
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                border: Border.all(color: value ? t.accent : t.line),
                color: value ? t.accentFade : Colors.transparent,
              ),
              child: value ? Icon(Icons.check, size: 12, color: t.accent) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  final TeapodTokens t;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _SheetTile({required this.t, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.lineSoft)),
        ),
        child: Text(label, style: AppTheme.sans(size: 14, color: color ?? t.text)),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('[ no configs ]', style: AppTheme.mono(size: 14, color: t.textMuted, letterSpacing: 1)),
          const SizedBox(height: 20),
          Text(
            context.l10n.configsEmpty,
            textAlign: TextAlign.center,
            style: AppTheme.sans(size: 14, color: t.textDim),
          ),
          const SizedBox(height: 24),
          TapTarget(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              color: t.accent,
              child: Text('+ ADD CONFIG', style: AppTheme.mono(size: 11, color: t.bg, letterSpacing: 1)),
            ),
          ),
        ],
      ),
    );
  }
}
