part of 'settings_screen.dart';

class _UpdateChannelSegment extends ConsumerWidget {
  const _UpdateChannelSegment();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    final settings = ref.watch(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null);
    if (settings == null) return const SizedBox.shrink();
    return SetSegSquare(
      t: t,
      value: settings.updateChannel == UpdateChannel.stable ? 'stable' : 'beta',
      opts: const [('stable', 'STABLE'), ('beta', 'BETA')],
      locked: false,
      onChanged: (v) async {
        final ch = v == 'stable' ? UpdateChannel.stable : UpdateChannel.beta;
        await ref.read(settingsProvider.notifier).set(SettingFields.updateChannel, ch);
        ref.read(updateProvider.notifier).checkForUpdate();
      },
    );
  }
}

// ── Appearance rows ───────────────────────────────────────────────

class _UpdateTile extends ConsumerWidget {
  const _UpdateTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    final updateState = ref.watch(updateProvider);
    final l = context.l10n;
    return switch (updateState) {
      UpdateIdle() => _UpdateRow(
        t: t,
        label: l.updateTitle,
        action: _SqBtn(t: t, label: l.updateCheck, onTap: () => ref.read(updateProvider.notifier).checkForUpdate()),
      ),
      UpdateChecking() => _UpdateRow(
        t: t,
        label: l.updateChecking,
        labelColor: t.textDim,
        action: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5, color: t.accent)),
      ),
      UpdateUpToDate(:final info) => _UpdateVersionTile(info: info, isUpdate: false),
      UpdateAvailable(:final info, :final resumableBytes) => _UpdateVersionTile(
        info: info,
        isUpdate: true,
        resumableBytes: resumableBytes,
      ),
      UpdateDownloading(:final info, :final downloaded, :final total) => Container(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l.updateDownloading(info.version), style: AppTheme.sans(size: 14, color: t.text)),
                TapTarget(
                  onTap: () => ref.read(updateProvider.notifier).cancelDownload(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(border: Border.all(color: t.line)),
                    child: Text(
                      l.commonCancelUpper,
                      style: AppTheme.mono(size: 10, color: t.textDim, letterSpacing: 1),
                    ),
                  ),
                ),
              ],
            ),
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
                  ? '${(downloaded / 1024 / 1024).toStringAsFixed(1)} / ${(total / 1024 / 1024).toStringAsFixed(1)} ${l.unitMb}'
                  : '${(downloaded / 1024 / 1024).toStringAsFixed(1)} ${l.unitMb}',
              style: AppTheme.mono(size: 10, color: t.textDim),
            ),
          ],
        ),
      ),
      UpdateDownloaded(:final info, :final filePath) => _UpdateRow(
        t: t,
        label: l.updateReadyToInstall(info.version),
        action: _SqBtn(
          t: t,
          label: l.updateInstall,
          filled: true,
          onTap: () => ref.read(updateProvider.notifier).installApk(filePath),
        ),
      ),
      UpdateError(:final message, :final retryInfo) => _UpdateRow(
        t: t,
        label: message.localize(l),
        labelColor: t.danger,
        action: _SqBtn(
          t: t,
          label: l.commonRetryUpper,
          onTap: retryInfo != null
              ? () => ref.read(updateProvider.notifier).startDownload(retryInfo)
              : () => ref.read(updateProvider.notifier).checkForUpdate(),
        ),
      ),
    };
  }
}

class _UpdateRow extends StatelessWidget {
  final TeapodTokens t;
  final String label;
  final Color? labelColor;
  final Widget action;
  const _UpdateRow({required this.t, required this.label, required this.action, this.labelColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, style: AppTheme.sans(size: 14, color: labelColor ?? t.text)),
          ),
          const SizedBox(width: 12),
          action,
        ],
      ),
    );
  }
}

class _SqBtn extends StatelessWidget {
  final TeapodTokens t;
  final String label;
  final bool filled;
  final VoidCallback? onTap;
  const _SqBtn({required this.t, required this.label, this.filled = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return TapTarget(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        color: filled ? t.accent : null,
        decoration: filled ? null : BoxDecoration(border: Border.all(color: t.line)),
        child: Text(label, style: AppTheme.mono(size: 10, color: filled ? t.bg : t.accent, letterSpacing: 1)),
      ),
    );
  }
}

class _UpdateVersionTile extends ConsumerWidget {
  final UpdateInfo info;
  final bool isUpdate;
  final int resumableBytes;
  const _UpdateVersionTile({required this.info, required this.isUpdate, this.resumableBytes = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<TeapodTokens>()!;

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isUpdate ? t.accentSoft : Colors.transparent,
        border: Border.all(color: isUpdate ? t.accent : t.line),
      ),
      child: Text(
        'v${info.version}',
        style: AppTheme.mono(size: 10, color: isUpdate ? t.accent : t.textMuted, letterSpacing: 0.5),
      ),
    );

    final l = context.l10n;
    final label = isUpdate ? l.updateAvailable : l.updateUpToDate;
    final btnLabel = isUpdate ? (resumableBytes > 0 ? l.updateResume : l.updateDownload) : l.updateReinstall;
    final onTap = isUpdate
        ? () => ref.read(updateProvider.notifier).startDownload(info)
        : () => ref.read(updateProvider.notifier).reinstall(info);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              badge,
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, style: AppTheme.sans(size: 14, color: isUpdate ? t.text : t.textDim)),
              ),
              const SizedBox(width: 12),
              _SqBtn(t: t, label: btnLabel, filled: isUpdate, onTap: onTap),
            ],
          ),
          for (final n in info.notes) ...[
            const SizedBox(height: 10),
            Text('v${n.version}', style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 0.5)),
            const SizedBox(height: 4),
            SelectableText(
              n.forLanguage(Localizations.localeOf(context).languageCode),
              style: AppTheme.mono(size: 11, color: t.textDim, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Battery row ───────────────────────────────────────────────────
