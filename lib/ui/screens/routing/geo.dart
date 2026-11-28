part of 'routing_screen.dart';

class _GeoUpdateRow extends ConsumerWidget {
  const _GeoUpdateRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    final geoState = ref.watch(geoProvider);
    return switch (geoState) {
      GeoMissing() => _GeoActionRow(
        t: t,
        label: context.l10n.geoNotLoaded,
        labelColor: t.danger,
        btnLabel: context.l10n.geoDownload,
        filled: true,
        onTap: () => ref.read(geoProvider.notifier).download(),
      ),
      GeoReady(:final lastUpdated) => _GeoActionRow(
        t: t,
        label: lastUpdated != null ? _daysAgo(context.l10n, lastUpdated) : context.l10n.geoLoaded,
        btnLabel: context.l10n.geoUpdate,
        onTap: () => ref.read(geoProvider.notifier).download(),
      ),
      GeoDownloading(:final downloaded, :final total) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.geoDownloading, style: AppTheme.sans(size: 13, color: t.text)),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: total > 0 ? downloaded / total : null,
              backgroundColor: t.line,
              color: t.accent,
              minHeight: 2,
            ),
            const SizedBox(height: 4),
            Text(
              total > 0
                  ? '${(downloaded / 1024 / 1024).toStringAsFixed(1)} / ${(total / 1024 / 1024).toStringAsFixed(1)} ${context.l10n.unitMb}'
                  : '${(downloaded / 1024 / 1024).toStringAsFixed(1)} ${context.l10n.unitMb}',
              style: AppTheme.mono(size: 10, color: t.textDim),
            ),
          ],
        ),
      ),
      GeoNeedsTrust(:final changed) => _GeoActionRow(
        t: t,
        label: changed ? context.l10n.geoChanged : context.l10n.geoUnverified,
        labelColor: t.warning,
        btnLabel: context.l10n.geoReview,
        onTap: () => _confirmTrust(context, ref, geoState),
      ),
      GeoError(:final message) => _GeoActionRow(
        t: t,
        label: message.localize(context.l10n),
        labelColor: t.danger,
        btnLabel: context.l10n.commonRetryUpper,
        onTap: () => ref.read(geoProvider.notifier).download(),
      ),
    };
  }

  /// Shows the URL and SHA-256 of each unverified file; trusting downloads again and installs only these files.
  Future<void> _confirmTrust(BuildContext context, WidgetRef ref, GeoNeedsTrust state) async {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.geoTrustTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(state.changed ? l.geoTrustChangedBody : l.geoTrustFirstBody),
              for (final MapEntry(key: url, value: sha256) in state.sha256ByUrl.entries) ...[
                const SizedBox(height: 12),
                SelectableText(url, style: AppTheme.mono(size: 11, color: t.textDim)),
                const SizedBox(height: 2),
                SelectableText('sha256 $sha256', style: AppTheme.mono(size: 11, color: t.text)),
              ],
            ],
          ),
        ),
        actions: [
          const DialogCancel(result: false),
          DialogAction(l.geoTrustButton, danger: true, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok == true) await ref.read(geoProvider.notifier).trust();
  }

  String _daysAgo(AppLocalizations l, DateTime dt) {
    final days = DateTime.now().difference(dt).inDays;
    if (days == 0) return l.geoUpdatedToday;
    if (days == 1) return l.geoUpdatedYesterday;
    return l.geoUpdatedDaysAgo(days);
  }
}

class _GeoActionRow extends StatelessWidget {
  final TeapodTokens t;
  final String label;
  final Color? labelColor;
  final String btnLabel;
  final bool filled;
  final VoidCallback onTap;

  const _GeoActionRow({
    required this.t,
    required this.label,
    required this.btnLabel,
    required this.onTap,
    this.labelColor,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, style: AppTheme.sans(size: 13, color: labelColor ?? t.text)),
          ),
          const SizedBox(width: 12),
          TapTarget(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: filled ? t.accent : null,
              decoration: filled ? null : BoxDecoration(border: Border.all(color: t.line)),
              child: Text(btnLabel, style: AppTheme.mono(size: 10, color: filled ? t.bg : t.accent, letterSpacing: 1)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Geo source bottom sheet ───────────────────────────────────────

class _GeoSourceSheet extends StatefulWidget {
  final String currentGeoipUrl;
  final String currentGeositeUrl;
  final void Function(String geoipUrl, String geositeUrl) onSave;

  const _GeoSourceSheet({required this.currentGeoipUrl, required this.currentGeositeUrl, required this.onSave});

  @override
  State<_GeoSourceSheet> createState() => _GeoSourceSheetState();
}

class _GeoSourceSheetState extends State<_GeoSourceSheet> {
  late String _geoipUrl;
  late String _geositeUrl;
  late final TextEditingController _geoipCtrl;
  late final TextEditingController _geositeCtrl;

  bool get _isCustom => GeoPresets.nameOf(_geoipUrl, _geositeUrl) == GeoPresets.custom;

  @override
  void initState() {
    super.initState();
    _geoipUrl = widget.currentGeoipUrl;
    _geositeUrl = widget.currentGeositeUrl;
    _geoipCtrl = TextEditingController(text: _isCustom ? _geoipUrl : '');
    _geositeCtrl = TextEditingController(text: _isCustom ? _geositeUrl : '');
  }

  @override
  void dispose() {
    _geoipCtrl.dispose();
    _geositeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    final currentName = GeoPresets.nameOf(_geoipUrl, _geositeUrl);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('GEO.DATA // SOURCE', style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
          const SizedBox(height: 16),
          // The presets' 48 dp tap targets space the runs.
          Wrap(
            spacing: 8,
            children: [
              for (final preset in GeoPresets.all)
                TapTarget(
                  selected: currentName == preset.name,
                  onTap: () => setState(() {
                    _geoipUrl = preset.geoipUrl;
                    _geositeUrl = preset.geositeUrl;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: currentName == preset.name ? t.accentSoft : null,
                      border: Border.all(color: currentName == preset.name ? t.accent : t.line),
                    ),
                    child: Text(
                      preset.name,
                      style: AppTheme.mono(
                        size: 11,
                        color: currentName == preset.name ? t.accent : t.textDim,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              TapTarget(
                selected: currentName == GeoPresets.custom,
                onTap: () => setState(() {
                  _geoipUrl = _geoipCtrl.text.trim().isNotEmpty ? _geoipCtrl.text.trim() : 'custom';
                  _geositeUrl = _geositeCtrl.text.trim().isNotEmpty ? _geositeCtrl.text.trim() : 'custom';
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: currentName == GeoPresets.custom ? t.accentSoft : null,
                    border: Border.all(color: currentName == GeoPresets.custom ? t.accent : t.line),
                  ),
                  child: Text(
                    context.l10n.routingSourceCustom,
                    style: AppTheme.mono(
                      size: 11,
                      color: currentName == GeoPresets.custom ? t.accent : t.textDim,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (currentName == GeoPresets.custom) ...[
            const SizedBox(height: 16),
            Text('GEOIP URL', style: AppTheme.mono(size: 9, color: t.textMuted, letterSpacing: 1)),
            const SizedBox(height: 6),
            TextField(
              controller: _geoipCtrl,
              style: AppTheme.mono(size: 12, color: t.text),
              decoration: InputDecoration(
                hintText: 'https://example.com/geoip.dat',
                hintStyle: AppTheme.mono(size: 12, color: t.textMuted),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: t.line),
                  borderRadius: BorderRadius.zero,
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: t.accent),
                  borderRadius: BorderRadius.zero,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
              ),
              onChanged: (v) => setState(() => _geoipUrl = v.trim()),
            ),
            const SizedBox(height: 12),
            Text('GEOSITE URL', style: AppTheme.mono(size: 9, color: t.textMuted, letterSpacing: 1)),
            const SizedBox(height: 6),
            TextField(
              controller: _geositeCtrl,
              style: AppTheme.mono(size: 12, color: t.text),
              decoration: InputDecoration(
                hintText: 'https://example.com/geosite.dat',
                hintStyle: AppTheme.mono(size: 12, color: t.textMuted),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: t.line),
                  borderRadius: BorderRadius.zero,
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: t.accent),
                  borderRadius: BorderRadius.zero,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
              ),
              onChanged: (v) => setState(() => _geositeUrl = v.trim()),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: TapTarget(
              onTap: () {
                widget.onSave(_geoipUrl, _geositeUrl);
                Navigator.pop(context);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                color: t.accent,
                alignment: Alignment.center,
                child: Text(
                  context.l10n.commonApplyUpper,
                  style: AppTheme.mono(size: 11, color: t.bg, letterSpacing: 1),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A geodata preset's name, or the localized label for a custom source.
String _geoSourceLabel(BuildContext context, String name) =>
    name == GeoPresets.custom ? context.l10n.routingSourceCustom : name;
