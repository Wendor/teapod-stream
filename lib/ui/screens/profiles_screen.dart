// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/profile.dart';
import '../../core/services/deeplink_router.dart';
import '../../core/models/app_message.dart';
import '../../core/services/bundle_loader.dart';
import '../../core/services/share_service.dart';
import '../../providers/profile_provider.dart';
import '../../providers/vpn_provider.dart';
import '../theme/app_theme.dart';
import '../theme/app_colors.dart';
import '../widgets/dialog_parts.dart';
import '../widgets/import_review.dart';
import '../widgets/breadcrumb_bar.dart';
import '../widgets/hero_panel.dart';
import '../widgets/pressable.dart';
import '../widgets/settings_shared.dart' show SetToggleRow;
import '../widgets/tap_target.dart';
import '../../l10n/l10n.dart';

// ── Screen ────────────────────────────────────────────────────────

class ProfilesScreen extends ConsumerWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Console header strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.line)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'teapod.stream // profiles',
                    style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1),
                  ),
                  profileAsync.maybeWhen(
                    data: (s) => Text(
                      'profiles [${s.profiles.length.toString().padLeft(2, '0')}]',
                      style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1),
                    ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            BreadcrumbBar(t: t, parent: 'settings', current: 'profiles'),
            HeroPanel(
              t: t,
              tagline: context.l10n.profilesTagline,
              title: 'PROFILES',
              subtitle: Text(
                context.l10n.profilesSubtitle,
                style: AppTheme.mono(size: 11, color: t.textDim, letterSpacing: 0.5),
              ),
              trailing: Row(
                children: [
                  _ProfIconBtn(
                    t: t,
                    icon: Icons.download_rounded,
                    label: context.l10n.profilesImport,
                    onTap: () => _profShowImportDialog(context, ref, t),
                  ),
                  _ProfIconBtn(
                    t: t,
                    icon: Icons.add_rounded,
                    accent: true,
                    label: context.l10n.profilesNew,
                    onTap: () => _profShowCreateDialog(context, ref, t),
                  ),
                ],
              ),
            ),
            Expanded(
              child: profileAsync.when(
                loading: () => Center(child: CircularProgressIndicator(color: t.accent, strokeWidth: 1.5)),
                error: (e, _) => Center(
                  child: Text(context.l10n.commonErrorWith('$e'), style: AppTheme.mono(size: 12, color: t.danger)),
                ),
                data: (state) => _ProfBody(state: state),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────

class _ProfBody extends ConsumerWidget {
  final ProfileState state;
  const _ProfBody({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).extension<TeapodTokens>()!;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Section header
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.lineSoft)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('[profiles]', style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
              Text(
                '${state.profiles.length.toString().padLeft(2, '0')} rows',
                style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1),
              ),
            ],
          ),
        ),

        // Profile list
        for (var i = 0; i < state.profiles.length; i++)
          _ProfileCard(
            profile: state.profiles[i],
            addr: i + 1,
            isActive: state.profiles[i].id == state.activeProfileId,
            t: t,
            onTap: () => _onProfileTap(context, ref, state.profiles[i], state),
            onActions: () => _showActionsSheet(context, ref, state.profiles[i], state, t),
          ),

        const SizedBox(height: 32),
      ],
    );
  }

  void _onProfileTap(BuildContext context, WidgetRef ref, Profile profile, ProfileState state) {
    if (profile.id == state.activeProfileId) return;
    ref.read(vpnProvider.notifier).switchProfile(profile.id);
  }
}

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
              child: Text(hexAddr, style: AppTheme.mono(size: 10, color: t.textMuted)),
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
                          decoration: BoxDecoration(
                            border: Border.all(color: t.accent),
                            color: t.accentSoft,
                          ),
                          child: Text('ACTIVE', style: AppTheme.mono(size: 9, color: t.accent, letterSpacing: 1)),
                        ),
                      if (profile.readonly) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(border: Border.all(color: t.textMuted)),
                          child: Text('RO', style: AppTheme.mono(size: 9, color: t.textMuted, letterSpacing: 1)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${profile.id}  ·  ${_formatDate(profile.createdAt)}',
                    style: AppTheme.mono(size: 9, color: t.textMuted, letterSpacing: 0.5),
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
