import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/models/profile.dart';
import '../../core/models/profile_bundle.dart';
import '../../providers/profile_provider.dart';
import 'dart:convert';
import '../theme/app_theme.dart';
import '../theme/app_colors.dart';
import '../widgets/breadcrumb_bar.dart';
import '../widgets/hero_panel.dart';

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
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('teapod.stream // profiles',
                      style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
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
              tagline: 'УПРАВЛЕНИЕ · ПРОФИЛИ',
              title: 'PROFILES',
              subtitle: Text('переключение и управление профилями настроек',
                  style: AppTheme.mono(size: 11, color: t.textDim, letterSpacing: 0.5)),
              trailing: Row(
                children: [
                  _ProfIconBtn(t: t, icon: Icons.download_rounded,
                      onTap: () => _profShowImportDialog(context, ref, t)),
                  const SizedBox(width: 6),
                  _ProfIconBtn(t: t, icon: Icons.add_rounded, accent: true,
                      onTap: () => _profShowCreateDialog(context, ref, t)),
                ],
              ),
            ),
            Expanded(
              child: profileAsync.when(
                loading: () => Center(
                    child: CircularProgressIndicator(
                        color: t.accent, strokeWidth: 1.5)),
                error: (e, _) => Center(
                    child: Text('Ошибка: $e',
                        style: AppTheme.mono(size: 12, color: t.danger))),
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
              border: Border(bottom: BorderSide(color: t.lineSoft))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('[profiles]',
                  style: AppTheme.mono(
                      size: 10, color: t.textMuted, letterSpacing: 1)),
              Text('${state.profiles.length.toString().padLeft(2, '0')} rows',
                  style: AppTheme.mono(
                      size: 10, color: t.textMuted, letterSpacing: 1)),
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

  void _onProfileTap(
      BuildContext context, WidgetRef ref, Profile profile, ProfileState state) {
    if (profile.id == state.activeProfileId) return;
    ref.read(profileProvider.notifier).switchProfile(profile.id);
  }
}

// ── Dialog helpers (top-level) ────────────────────────────────────

void _profShowCreateDialog(BuildContext context, WidgetRef ref, TeapodTokens t) {
    final ctrl = TextEditingController();
    var copyFromCurrent = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: t.bg,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: Text('Новый профиль',
              style: AppTheme.sans(size: 16, color: t.text, weight: FontWeight.w500)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                style: AppTheme.mono(size: 13, color: t.text),
                decoration: InputDecoration(
                  hintText: 'Название профиля',
                  hintStyle: AppTheme.mono(size: 12, color: t.textMuted),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  isDense: true,
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: t.line),
                      borderRadius: BorderRadius.zero),
                  focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: t.accent),
                      borderRadius: BorderRadius.zero),
                ),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () => setState(() => copyFromCurrent = !copyFromCurrent),
                child: Row(
                  children: [
                    _CheckBox(t: t, value: copyFromCurrent),
                    const SizedBox(width: 10),
                    Text('Скопировать текущие настройки',
                        style: AppTheme.mono(size: 11, color: t.text)),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Отмена',
                  style: AppTheme.mono(size: 11, color: t.textMuted)),
            ),
            TextButton(
              onPressed: () {
                final name = ctrl.text.trim();
                if (name.isEmpty) return;
                ref.read(profileProvider.notifier)
                    .createProfile(name, copyFromCurrent: copyFromCurrent);
                Navigator.pop(ctx);
              },
              child: Text('Создать',
                  style: AppTheme.mono(size: 11, color: t.accent)),
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

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: t.bg,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: Text('Импорт профиля',
              style: AppTheme.sans(size: 16, color: t.text, weight: FontWeight.w500)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                maxLines: 4,
                style: AppTheme.mono(size: 11, color: t.text),
                decoration: InputDecoration(
                  hintText: 'Вставьте deeplink (teapod://...) или JSON',
                  hintStyle: AppTheme.mono(size: 10, color: t.textMuted),
                  contentPadding: const EdgeInsets.all(10),
                  isDense: true,
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: t.line),
                      borderRadius: BorderRadius.zero),
                  focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: t.accent),
                      borderRadius: BorderRadius.zero),
                ),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () => setState(() => switchTo = !switchTo),
                child: Row(children: [
                  _CheckBox(t: t, value: switchTo),
                  const SizedBox(width: 10),
                  Text('Переключиться после импорта',
                      style: AppTheme.mono(size: 11, color: t.text)),
                ]),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => setState(() => makeReadonly = !makeReadonly),
                child: Row(children: [
                  _CheckBox(t: t, value: makeReadonly),
                  const SizedBox(width: 10),
                  Text('Только чтение',
                      style: AppTheme.mono(size: 11, color: t.text)),
                ]),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Отмена',
                  style: AppTheme.mono(size: 11, color: t.textMuted)),
            ),
            TextButton(
              onPressed: () async {
                final bundle = ProfileNotifier.tryParseBundle(ctrl.text);
                if (bundle == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text('Неверный формат',
                        style: AppTheme.mono(size: 12, color: t.bg)),
                    backgroundColor: t.danger,
                    duration: const Duration(seconds: 2),
                  ));
                  return;
                }
                Navigator.pop(ctx);
                await ref.read(profileProvider.notifier).importBundle(
                  bundle,
                  switchToProfile: switchTo,
                  makeReadonly: makeReadonly,
                );
              },
              child: Text('Импортировать',
                  style: AppTheme.mono(size: 11, color: t.accent)),
            ),
          ],
        ),
      ),
    );
  }

  void _showActionsSheet(
    BuildContext context,
    WidgetRef ref,
    Profile profile,
    ProfileState state,
    TeapodTokens t,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: t.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) => _ProfileActionsSheet(
        profile: profile,
        isActive: profile.id == state.activeProfileId,
        t: t,
        onSwitch: () {
          Navigator.pop(ctx);
          ref.read(profileProvider.notifier).switchProfile(profile.id);
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
      ),
    );
  }

  void _showRenameDialog(
      BuildContext context, WidgetRef ref, Profile profile, TeapodTokens t) {
    final ctrl = TextEditingController(text: profile.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.bg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text('Переименовать',
            style: AppTheme.sans(size: 16, color: t.text, weight: FontWeight.w500)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: AppTheme.mono(size: 13, color: t.text),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            isDense: true,
            enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: t.line), borderRadius: BorderRadius.zero),
            focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: t.accent), borderRadius: BorderRadius.zero),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: AppTheme.mono(size: 11, color: t.textMuted)),
          ),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              ref.read(profileProvider.notifier).renameProfile(profile.id, name);
              Navigator.pop(ctx);
            },
            child: Text('Сохранить', style: AppTheme.mono(size: 11, color: t.accent)),
          ),
        ],
      ),
    );
  }

  void _showExportSheet(
      BuildContext context, WidgetRef ref, Profile profile, TeapodTokens t) {
    final bundle =
        ref.read(profileProvider.notifier).exportBundle(profile.id);
    final deeplink = bundle.toDeeplink();

    showModalBottomSheet(
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
              Text('ЭКСПОРТ · ${profile.name.toUpperCase()}',
                  style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1.5)),
              const SizedBox(height: 16),
              _ExportRow(
                t: t,
                label: 'Копировать ссылку',
                hint: 'teapod://import?data=...',
                onTap: () {
                  Clipboard.setData(ClipboardData(text: deeplink));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Ссылка скопирована',
                        style: AppTheme.mono(size: 12, color: t.bg)),
                    backgroundColor: t.accent,
                    duration: const Duration(seconds: 2),
                  ));
                },
              ),
              _ExportRow(
                t: t,
                label: 'Поделиться файлом',
                hint: '${profile.name.toLowerCase().replaceAll(' ', '_')}.teapod',
                onTap: () async {
                  Navigator.pop(ctx);
                  await _shareAsFile(context, profile, bundle);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareAsFile(
      BuildContext context, Profile profile, ProfileBundle bundle) async {
    final dir = await getTemporaryDirectory();
    final safeName = profile.name.replaceAll(RegExp(r'[^a-zA-Z0-9а-яА-Я_\- ]'), '_');
    final file = File('${dir.path}/$safeName.teapod');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(bundle.toJson()),
    );
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Teapod profile: ${profile.name}',
    );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, Profile profile, TeapodTokens t) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.bg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text('Удалить профиль?',
            style: AppTheme.sans(size: 16, color: t.text, weight: FontWeight.w500)),
        content: Text('«${profile.name}» будет удалён без возможности восстановления.',
            style: AppTheme.mono(size: 12, color: t.textDim)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: AppTheme.mono(size: 11, color: t.textMuted)),
          ),
          TextButton(
            onPressed: () {
              ref.read(profileProvider.notifier).deleteProfile(profile.id);
              Navigator.pop(ctx);
            },
            child: Text('Удалить', style: AppTheme.mono(size: 11, color: t.danger)),
          ),
        ],
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

    return GestureDetector(
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
              child: Text(hexAddr,
                  style: AppTheme.mono(size: 10, color: t.textMuted)),
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
                        color: t.accentSoft),
                    child: Text('ACTIVE',
                        style: AppTheme.mono(
                            size: 9, color: t.accent, letterSpacing: 1)),
                  ),
                if (profile.readonly) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(border: Border.all(color: t.textMuted)),
                    child: Text('RO',
                        style: AppTheme.mono(
                            size: 9, color: t.textMuted, letterSpacing: 1)),
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

  const _ProfileActionsSheet({
    required this.profile,
    required this.isActive,
    required this.t,
    required this.onSwitch,
    required this.onRename,
    required this.onToggleReadonly,
    required this.onExport,
    this.onDelete,
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
                Text(profile.name,
                    style: AppTheme.sans(
                        size: 16, color: t.text, weight: FontWeight.w500)),
                const Spacer(),
                if (profile.readonly)
                  Text('readonly',
                      style: AppTheme.mono(size: 10, color: t.textMuted)),
              ],
            ),
          ),
          Container(height: 1, color: t.line),
          if (!isActive)
            _ActionTile(
                t: t, label: 'Переключиться', onTap: onSwitch),
          _ActionTile(t: t, label: 'Переименовать', onTap: onRename),
          _ActionTile(
            t: t,
            label: profile.readonly ? 'Разблокировать' : 'Заблокировать для редактирования',
            onTap: onToggleReadonly,
          ),
          _ActionTile(t: t, label: 'Экспортировать', onTap: onExport),
          if (onDelete != null)
            _ActionTile(
                t: t, label: 'Удалить', color: t.danger, onTap: onDelete!),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.lineSoft))),
        child: Text(label,
            style: AppTheme.sans(size: 14, color: color ?? t.text)),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.lineSoft))),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTheme.sans(size: 14, color: t.text)),
                  const SizedBox(height: 2),
                  Text(hint,
                      style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 0.5)),
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
  final VoidCallback onTap;

  const _ProfIconBtn({
    required this.t,
    required this.icon,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
          color: value ? t.accent : Colors.transparent),
      child: value
          ? Icon(Icons.check, size: 10, color: t.bg)
          : null,
    );
  }
}

