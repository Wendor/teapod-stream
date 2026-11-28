// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/profile.dart';
import '../../../core/services/deeplink_router.dart';
import '../../../core/models/app_message.dart';
import '../../../core/services/bundle_loader.dart';
import '../../../core/services/share_service.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/vpn_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_colors.dart';
import '../../widgets/dialog_parts.dart';
import '../../widgets/import_review.dart';
import '../../widgets/breadcrumb_bar.dart';
import '../../widgets/hero_panel.dart';
import '../../widgets/pressable.dart';
import '../../widgets/settings_shared.dart' show SetToggleRow;
import '../../widgets/tap_target.dart';
import '../../../l10n/l10n.dart';

part 'actions.dart';
part 'card.dart';
part 'dialogs.dart';

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
