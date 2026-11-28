part of 'network_settings_screen.dart';

String _fpLabel(TlsFingerprint fp) => fp == TlsFingerprint.defaultFp ? 'DEFAULT' : fp.name.toUpperCase();

extension _Pickers on _NetworkSettingsScreenState {
  /// Screen-styled dropdown of values; used for enums.
  void _showEnumPicker<T>(
    BuildContext context, {
    required String title,
    required List<T> values,
    required T current,
    required String Function(T) labelOf,
    required void Function(T) onPick,
  }) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title, style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: t.line),
            for (final v in values)
              InkWell(
                onTap: () {
                  onPick(v);
                  Navigator.pop(ctx);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          labelOf(v),
                          style: AppTheme.mono(size: 12, color: v == current ? t.accent : t.text, letterSpacing: 0.5),
                        ),
                      ),
                      if (v == current) Text('•', style: AppTheme.mono(size: 12, color: t.accent)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showFingerprintPicker(BuildContext context, AppSettings s) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'tls // fingerprint',
                      style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1),
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: t.line),
            for (final fp in TlsFingerprint.values)
              InkWell(
                onTap: () {
                  _set(SettingFields.tlsFingerprint, fp);
                  Navigator.pop(ctx);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _fpLabel(fp),
                          style: AppTheme.mono(
                            size: 12,
                            color: fp == s.tlsFingerprint ? t.accent : t.text,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      if (fp == s.tlsFingerprint) Text('●', style: AppTheme.mono(size: 10, color: t.accent)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Setting row with a value button that opens a list picker.
class _PickerRow extends StatelessWidget {
  final TeapodTokens t;
  final String title;
  final String hint;
  final String value;
  final bool locked;
  final VoidCallback onTap;

  const _PickerRow({
    required this.t,
    required this.title,
    required this.hint,
    required this.value,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.lineSoft)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.sans(size: 14, color: t.text)),
                const SizedBox(height: 3),
                Text(hint, style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 0.5)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          TapTarget(
            onTap: locked ? () => showReadonlySnack(context) : onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(border: Border.all(color: t.line)),
              child: Text(
                value,
                style: AppTheme.mono(size: 11, color: locked ? t.textDim : t.accent, letterSpacing: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Warning under a section: the setting is invalid and won't make it into the config.
class _HintRow extends StatelessWidget {
  final TeapodTokens t;
  final String text;

  const _HintRow({required this.t, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.lineSoft)),
      ),
      child: Text(text, style: AppTheme.mono(size: 10, color: t.danger, letterSpacing: 0.5)),
    );
  }
}
