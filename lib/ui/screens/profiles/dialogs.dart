part of 'profiles_screen.dart';

// ── Dialog helpers (top-level) ────────────────────────────────────

void _profShowCreateDialog(BuildContext context, WidgetRef ref, TeapodTokens t) {
  final ctrl = TextEditingController();
  var copyFromCurrent = true;

  showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(context.l10n.profilesNew),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              style: dialogFieldStyle(ctx),
              decoration: dialogField(hint: context.l10n.profilesNameHint),
            ),
            const SizedBox(height: 14),
            SetToggleRow(
              value: copyFromCurrent,
              checkbox: true,
              onTap: () => setState(() => copyFromCurrent = !copyFromCurrent),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
                child: Row(
                  children: [
                    _CheckBox(t: t, value: copyFromCurrent),
                    const SizedBox(width: 10),
                    Text(context.l10n.profilesCopyCurrent, style: AppTheme.mono(size: 11, color: t.text)),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          const DialogCancel(),
          DialogAction(
            context.l10n.commonCreate,
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              ref.read(profileProvider.notifier).createProfile(name, copyFromCurrent: copyFromCurrent);
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    ),
  );
}

void _profShowImportDialog(BuildContext context, WidgetRef ref, TeapodTokens t) {
  final ctrl = TextEditingController();
  var switchTo = true;
  var makeReadonly = false;

  showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(context.l10n.profileImportTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              maxLines: 4,
              style: dialogFieldStyle(ctx),
              decoration: dialogField(hint: context.l10n.profilesImportHint),
            ),
            const SizedBox(height: 14),
            SetToggleRow(
              value: switchTo,
              checkbox: true,
              onTap: () => setState(() => switchTo = !switchTo),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
                child: Row(
                  children: [
                    _CheckBox(t: t, value: switchTo),
                    const SizedBox(width: 10),
                    Text(context.l10n.profilesSwitchAfterImport, style: AppTheme.mono(size: 11, color: t.text)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SetToggleRow(
              value: makeReadonly,
              checkbox: true,
              onTap: () => setState(() => makeReadonly = !makeReadonly),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
                child: Row(
                  children: [
                    _CheckBox(t: t, value: makeReadonly),
                    const SizedBox(width: 10),
                    Text(context.l10n.profilesReadonly, style: AppTheme.mono(size: 11, color: t.text)),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          const DialogCancel(),
          DialogAction(
            context.l10n.commonImport,
            onPressed: () async {
              var loading = false;

              final loadFuture = ref.read(bundleLoaderProvider).profileInput(ctrl.text);

              if (DeeplinkRouter.parse(ctrl.text.trim())?.source == DeeplinkSource.url) {
                loading = true;
                showDialog<void>(
                  context: ctx,
                  barrierDismissible: false,
                  builder: (_) => const Center(child: CircularProgressIndicator()),
                );
              }

              final load = await loadFuture;

              if (loading && ctx.mounted) Navigator.pop(ctx);
              if (!ctx.mounted) return;

              if (load is! ProfileLoaded) {
                final reason = load is BundleFailed ? load.reason : const AppMessage(MessageCode.bundleFetchFailed);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(reason.localize(context.l10n), style: AppTheme.mono(size: 12, color: t.bg)),
                    backgroundColor: t.danger,
                    duration: const Duration(seconds: 2),
                  ),
                );
                return;
              }
              final review = await ref.read(profileProvider.notifier).reviewImport(load.bundle);
              if (!ctx.mounted || !await confirmImportReview(ctx, review) || !ctx.mounted) return;
              Navigator.pop(ctx);
              await ref
                  .read(vpnProvider.notifier)
                  .importProfile(
                    load.bundle,
                    makeReadonly: makeReadonly,
                    sourceUrl: load.sourceUrl,
                    switchTo: switchTo,
                  );
            },
          ),
        ],
      ),
    ),
  );
}

void _showActionsSheet(BuildContext context, WidgetRef ref, Profile profile, ProfileState state, TeapodTokens t) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: t.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    builder: (ctx) => _ProfileActionsSheet(
      profile: profile,
      isActive: profile.id == state.activeProfileId,
      t: t,
      onSwitch: () {
        Navigator.pop(ctx);
        ref.read(vpnProvider.notifier).switchProfile(profile.id);
      },
      onRename: () {
        Navigator.pop(ctx);
        _showRenameDialog(context, ref, profile, t);
      },
      onToggleReadonly: () {
        Navigator.pop(ctx);
        ref.read(profileProvider.notifier).toggleReadonly(profile.id);
      },
      onExport: () {
        Navigator.pop(ctx);
        _showExportSheet(context, ref, profile, t);
      },
      onDelete: !profile.isDefault && profile.id != state.activeProfileId
          ? () {
              Navigator.pop(ctx);
              _confirmDelete(context, ref, profile, t);
            }
          : null,
      onRefresh: profile.sourceUrl != null
          ? () {
              Navigator.pop(ctx);
              _refreshProfile(context, ref, profile, t);
            }
          : null,
    ),
  );
}

void _showRenameDialog(BuildContext context, WidgetRef ref, Profile profile, TeapodTokens t) {
  final ctrl = TextEditingController(text: profile.name);
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(context.l10n.commonRename),
      content: TextField(controller: ctrl, autofocus: true, style: dialogFieldStyle(ctx), decoration: dialogField()),
      actions: [
        const DialogCancel(),
        DialogAction(
          context.l10n.commonSave,
          onPressed: () {
            final name = ctrl.text.trim();
            if (name.isEmpty) return;
            ref.read(profileProvider.notifier).renameProfile(profile.id, name);
            Navigator.pop(ctx);
          },
        ),
      ],
    ),
  );
}

void _showExportSheet(BuildContext context, WidgetRef ref, Profile profile, TeapodTokens t) {
  final bundle = ref.read(profileProvider.notifier).exportBundle(profile.id);
  final deeplink = bundle.toDeeplink();

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: t.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${context.l10n.profilesExportUpper} · ${profile.name.toUpperCase()}',
              style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1.5),
            ),
            const SizedBox(height: 16),
            _ExportRow(
              t: t,
              label: context.l10n.profilesCopyLink,
              hint: 'teapod://import/profile?data=...',
              onTap: () {
                Clipboard.setData(ClipboardData(text: deeplink));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.l10n.profilesLinkCopied, style: AppTheme.mono(size: 12, color: t.bg)),
                    backgroundColor: t.accent,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
            _ExportRow(
              t: t,
              label: context.l10n.profilesShareFile,
              hint: '${profile.name.toLowerCase().replaceAll(' ', '_')}.json',
              onTap: () async {
                Navigator.pop(ctx);
                await ref.read(shareServiceProvider).shareProfile(profile.name, bundle);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

void _confirmDelete(BuildContext context, WidgetRef ref, Profile profile, TeapodTokens t) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(context.l10n.profilesDeleteTitle),
      content: Text(context.l10n.profilesDeleteMessage(profile.name)),
      actions: [
        const DialogCancel(),
        DialogAction(
          context.l10n.commonDelete,
          danger: true,
          onPressed: () {
            ref.read(profileProvider.notifier).deleteProfile(profile.id);
            Navigator.pop(ctx);
          },
        ),
      ],
    ),
  );
}

Future<void> _refreshProfile(BuildContext context, WidgetRef ref, Profile profile, TeapodTokens t) async {
  var spinner = true;
  void closeSpinner() {
    if (spinner && context.mounted) Navigator.pop(context);
    spinner = false;
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  final outcome = await ref
      .read(profileProvider.notifier)
      .refreshProfile(
        profile.id,
        profile.sourceUrl!,
        confirm: (review) async {
          closeSpinner();
          return context.mounted && await confirmImportReview(context, review);
        },
      );
  closeSpinner();
  if (!context.mounted) return;
  final (text, failed) = switch (outcome) {
    ProfileRefreshed() => (context.l10n.profilesUpdated(profile.name), false),
    ProfileRefreshDeclined() => (null, false),
    ProfileRefreshFailed(:final reason) => (reason.localize(context.l10n), true),
  };
  if (text == null) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text, style: AppTheme.mono(size: 12, color: t.bg)),
      backgroundColor: failed ? t.danger : t.accent,
      duration: const Duration(seconds: 2),
    ),
  );
}
