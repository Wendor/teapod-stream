part of 'settings_screen.dart';

class _AppearanceRows extends ConsumerWidget {
  final TeapodTokens t;
  const _AppearanceRows({required this.t});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final accent = ref.watch(accentProvider);
    final settings = ref.watch(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null);
    final locale = ref.watch(localeProvider);
    final l = context.l10n;

    return Column(
      children: [
        // Theme
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.lineSoft)),
          ),
          // A Wrap, not a Row: at a large text scale the segments go under the label instead of past the edge.
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(l.settingsTheme, style: AppTheme.sans(size: 14, color: t.text)),
              SetSegSquare(
                t: t,
                value: themeMode == ThemeMode.dark
                    ? 'dark'
                    : themeMode == ThemeMode.light
                    ? 'light'
                    : 'system',
                opts: [('dark', l.settingsThemeDark), ('light', l.settingsThemeLight), ('system', l.settingsSystem)],
                locked: false,
                onChanged: (v) {
                  final m = v == 'dark'
                      ? ThemeMode.dark
                      : v == 'light'
                      ? ThemeMode.light
                      : ThemeMode.system;
                  ref.read(themeModeProvider.notifier).set(m);
                },
              ),
            ],
          ),
        ),
        // Language
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.lineSoft)),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(l.settingsLanguage, style: AppTheme.sans(size: 14, color: t.text)),
              SetSegSquare(
                t: t,
                value: locale?.languageCode ?? 'system',
                opts: [('system', l.settingsSystem), ('en', 'EN'), ('ru', 'RU')],
                locked: false,
                onChanged: (v) => ref.read(localeProvider.notifier).set(v == 'system' ? null : Locale(v)),
              ),
            ],
          ),
        ),
        // Font scale
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.lineSoft)),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(l.settingsFontSize, style: AppTheme.sans(size: 14, color: t.text)),
              if (settings != null)
                SetSegSquare(
                  t: t,
                  value: settings.fontScale == FontScale.large ? 'large' : 'normal',
                  opts: [('normal', l.settingsFontNormal), ('large', l.settingsFontLarge)],
                  locked: false,
                  onChanged: (v) {
                    final scale = v == 'large' ? FontScale.large : FontScale.normal;
                    ref.read(settingsProvider.notifier).edit((c) => c.copyWith(fontScale: scale));
                  },
                ),
            ],
          ),
        ),
        // Accent
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.settingsAccentColor, style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
              const SizedBox(height: 10),
              Wrap(
                children: AppColors.accentPresets.map((c) {
                  final selected = accent.toARGB32() == c.toARGB32();
                  return TapTarget(
                    onTap: () => ref.read(accentProvider.notifier).set(c),
                    label: l.settingsAccentSwatch(
                      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                    ),
                    selected: selected,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: c,
                        border: Border.all(color: selected ? t.text : Colors.transparent, width: 1.5),
                      ),
                      child: selected ? Center(child: Container(width: 10, height: 10, color: t.bg)) : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Text(
                '#${accent.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                style: AppTheme.mono(size: 11, color: t.textDim, letterSpacing: 1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Update tile ───────────────────────────────────────────────────
