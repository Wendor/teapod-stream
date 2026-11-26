part of 'settings_screen.dart';

class _KVRow extends StatelessWidget {
  final TeapodTokens t;
  final String k;
  final String v;
  const _KVRow({required this.t, required this.k, required this.v});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.lineSoft)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k.toUpperCase(), style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
          Text(v, style: AppTheme.mono(size: 11, color: t.text)),
        ],
      ),
    );
  }
}

class _KVRowTap extends StatelessWidget {
  final TeapodTokens t;
  final String k;
  final String v;
  final VoidCallback? onTap;
  const _KVRowTap({required this.t, required this.k, required this.v, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.lineSoft)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k.toUpperCase(), style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
            Row(
              children: [
                Text(v, style: AppTheme.mono(size: 11, color: t.accent)),
                const SizedBox(width: 6),
                Text('›', style: AppTheme.mono(size: 14, color: t.textMuted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Core priority ─────────────────────────────────────────────────

class _BatteryRow extends ConsumerWidget {
  const _BatteryRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    return SetRowChev(
      t: t,
      title: context.l10n.settingsBattery,
      hint: context.l10n.settingsBatteryHint,
      onTap: () => ref.read(platformServiceProvider).openBatteryOptimizationSettings().ignore(),
    );
  }
}

// ── Profiles row ──────────────────────────────────────────────────

class _ProfilesRow extends ConsumerWidget {
  final TeapodTokens t;
  const _ProfilesRow({required this.t});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileState = ref.watch(profileProvider).maybeWhen(data: (d) => d, orElse: () => null);
    final profile = profileState?.activeProfile;
    final hint = profile == null
        ? context.l10n.commonLoading
        : '${profile.name}${profile.readonly ? ' · ${context.l10n.profileReadonly}' : ''}';

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ProfilesScreen())),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.settingsProfiles, style: AppTheme.sans(size: 14, color: t.text)),
                  const SizedBox(height: 3),
                  Text(
                    hint,
                    style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 0.5),
                    overflow: TextOverflow.ellipsis,
                  ),
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

// ── DNS settings screen (kept, uses Material AppBar) ──────────────

String _dnsLabel(AppSettings settings) {
  if (settings.dnsPreset == 'custom') return settings.customDnsAddress;
  return DnsServerConfig.presets.firstWhere(
            (p) => p['value'] == settings.dnsPreset,
            orElse: () => {'label': settings.dnsPreset},
          )['label']
          as String? ??
      settings.dnsPreset;
}
