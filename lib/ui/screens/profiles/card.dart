part of 'profiles_screen.dart';

// ── Profile card ──────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final Profile profile;
  final int addr;
  final bool isActive;
  final TeapodTokens t;
  final VoidCallback onTap;
  final VoidCallback onActions;

  const _ProfileCard({
    required this.profile,
    required this.addr,
    required this.isActive,
    required this.t,
    required this.onTap,
    required this.onActions,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isActive ? t.accent : t.line;
    // Secondary text: textMuted is below AA on the highlight of the active row.
    final secondary = isActive ? t.textDim : t.textMuted;
    final hexAddr = '0x${addr.toString().padLeft(2, '0')}';

    return Pressable(
      onTap: onTap,
      onLongPress: onActions,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: t.lineSoft),
            left: BorderSide(color: borderColor, width: isActive ? 2 : 0),
          ),
          color: isActive ? t.accentSoft : Colors.transparent,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(hexAddr, style: AppTheme.mono(size: 10, color: secondary)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          profile.name,
                          style: AppTheme.sans(
                            size: 14,
                            color: isActive ? t.accent : t.text,
                            weight: isActive ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          // Only a frame: the row is highlighted already, a second highlight would darken the text's ground.
                          decoration: BoxDecoration(border: Border.all(color: t.accent)),
                          child: Text('ACTIVE', style: AppTheme.mono(size: 9, color: t.accent, letterSpacing: 1)),
                        ),
                      if (profile.readonly) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(border: Border.all(color: secondary)),
                          child: Text('RO', style: AppTheme.mono(size: 9, color: secondary, letterSpacing: 1)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${profile.id}  ·  ${_formatDate(profile.createdAt)}',
                    style: AppTheme.mono(size: 9, color: secondary, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

// ── Shared small widgets ──────────────────────────────────────────

class _ProfIconBtn extends StatelessWidget {
  final TeapodTokens t;
  final IconData icon;
  final bool accent;
  final String label;
  final VoidCallback onTap;

  const _ProfIconBtn({
    required this.t,
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return TapTarget(
      onTap: onTap,
      label: label,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: accent ? t.accent : Colors.transparent,
          border: Border.all(color: accent ? t.accent : t.line),
        ),
        child: Icon(icon, size: 14, color: accent ? t.bg : t.textDim),
      ),
    );
  }
}

class _CheckBox extends StatelessWidget {
  final TeapodTokens t;
  final bool value;

  const _CheckBox({required this.t, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        border: Border.all(color: value ? t.accent : t.line),
        color: value ? t.accent : Colors.transparent,
      ),
      child: value ? Icon(Icons.check, size: 10, color: t.bg) : null,
    );
  }
}
