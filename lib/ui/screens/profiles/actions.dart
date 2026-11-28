part of 'profiles_screen.dart';

// ── Actions bottom sheet ──────────────────────────────────────────

class _ProfileActionsSheet extends StatelessWidget {
  final Profile profile;
  final bool isActive;
  final TeapodTokens t;
  final VoidCallback onSwitch;
  final VoidCallback onRename;
  final VoidCallback onToggleReadonly;
  final VoidCallback onExport;
  final VoidCallback? onDelete;
  final VoidCallback? onRefresh;

  const _ProfileActionsSheet({
    required this.profile,
    required this.isActive,
    required this.t,
    required this.onSwitch,
    required this.onRename,
    required this.onToggleReadonly,
    required this.onExport,
    this.onDelete,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Text(
                  profile.name,
                  style: AppTheme.sans(size: 16, color: t.text, weight: FontWeight.w500),
                ),
                const Spacer(),
                if (profile.readonly) Text('readonly', style: AppTheme.mono(size: 10, color: t.textMuted)),
              ],
            ),
          ),
          Container(height: 1, color: t.line),
          if (!isActive) _ActionTile(t: t, label: context.l10n.profilesSwitch, onTap: onSwitch),
          if (onRefresh != null) _ActionTile(t: t, label: context.l10n.configsRefresh, onTap: onRefresh!),
          _ActionTile(t: t, label: context.l10n.commonRename, onTap: onRename),
          _ActionTile(
            t: t,
            label: profile.readonly ? context.l10n.profilesUnlock : context.l10n.profilesLock,
            onTap: onToggleReadonly,
          ),
          _ActionTile(t: t, label: context.l10n.profilesExport, onTap: onExport),
          if (onDelete != null) _ActionTile(t: t, label: context.l10n.commonDelete, color: t.danger, onTap: onDelete!),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final TeapodTokens t;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _ActionTile({required this.t, required this.label, required this.onTap, this.color});

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

// ── Export row ────────────────────────────────────────────────────

class _ExportRow extends StatelessWidget {
  final TeapodTokens t;
  final String label;
  final String hint;
  final VoidCallback onTap;

  const _ExportRow({required this.t, required this.label, required this.hint, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.lineSoft)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTheme.sans(size: 14, color: t.text)),
                  const SizedBox(height: 2),
                  Text(hint, style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 0.5)),
                ],
              ),
            ),
            Text('›', style: AppTheme.mono(size: 16, color: t.textMuted)),
          ],
        ),
      ),
    );
  }
}
