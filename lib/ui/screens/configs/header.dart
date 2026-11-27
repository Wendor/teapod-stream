part of 'configs_screen.dart';

class _CfgHeaderStrip extends StatelessWidget {
  final TeapodTokens t;
  final int total;
  final bool isPinging;
  final VoidCallback? onPing;

  const _CfgHeaderStrip({required this.t, required this.total, required this.isPinging, this.onPing});

  @override
  Widget build(BuildContext context) {
    final totalStr = total.toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // The caption gives way: the 48 dp ping target and the total keep their width on a narrow screen.
          Flexible(
            child: Text(
              'teapod.stream // configs',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1),
            ),
          ),
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isPinging)
                SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: t.accent, strokeWidth: 1.2))
              else if (onPing != null)
                TapTarget(
                  onTap: onPing,
                  child: Text('ping', style: AppTheme.mono(size: 10, color: t.accent, letterSpacing: 1)),
                ),
              const SizedBox(width: 12),
              Text('total [$totalStr]', style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Title panel ───────────────────────────────────────────────────

class _CfgTitlePanel extends StatelessWidget {
  final TeapodTokens t;
  final VoidCallback onAdd;
  final VoidCallback? onRefreshAll;
  final bool isRefreshing;
  final VoidCallback onSettings;
  final VoidCallback onSubSettings;
  final VoidCallback? onExport;

  const _CfgTitlePanel({
    required this.t,
    required this.onAdd,
    this.onRefreshAll,
    this.isRefreshing = false,
    required this.onSettings,
    required this.onSubSettings,
    this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return HeroPanel(
      t: t,
      tagline: context.l10n.configsTagline,
      title: 'CONFIGS',
      subtitle: Text(
        'subs · standalone · imported',
        style: AppTheme.mono(size: 11, color: t.textDim, letterSpacing: 0.5),
      ),
      trailing: Row(
        children: [
          _IconBtn(
            t: t,
            icon: Icons.tune_rounded,
            accent: false,
            label: context.l10n.configsDisplaySettings,
            onTap: onSettings,
          ),
          _IconBtn(
            t: t,
            icon: Icons.schedule_rounded,
            accent: false,
            label: context.l10n.configsSubSettings,
            onTap: onSubSettings,
          ),
          _IconBtn(
            t: t,
            icon: Icons.ios_share_rounded,
            accent: false,
            label: context.l10n.configsExport,
            onTap: onExport,
          ),
          if (isRefreshing)
            SizedBox(
              width: kMinInteractiveDimension,
              height: kMinInteractiveDimension,
              child: Center(
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(color: t.textDim, strokeWidth: 1.2),
                ),
              ),
            )
          else
            _IconBtn(
              t: t,
              icon: Icons.refresh_rounded,
              accent: false,
              label: context.l10n.configsRefreshSubs,
              onTap: onRefreshAll,
            ),
          _IconBtn(t: t, icon: Icons.add_rounded, accent: true, label: context.l10n.configsAdd, onTap: onAdd),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final TeapodTokens t;
  final IconData icon;
  final bool accent;
  final String label;
  final VoidCallback? onTap;

  const _IconBtn({required this.t, required this.icon, required this.accent, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return TapTarget(
      label: label,
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: accent ? t.accent : Colors.transparent,
          border: Border.all(color: accent ? t.accent : t.line),
        ),
        child: Icon(
          icon,
          size: 15,
          color: accent
              ? t.bg
              : onTap != null
              ? t.textDim
              : t.textMuted,
        ),
      ),
    );
  }
}

// ── [local] group ─────────────────────────────────────────────────
