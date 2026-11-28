// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/app_settings.dart';
import '../../core/models/setting_field.dart';
import '../../providers/profile_provider.dart';
import '../../providers/settings_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/breadcrumb_bar.dart';
import '../widgets/hero_panel.dart';
import '../widgets/settings_shared.dart';
import '../../l10n/l10n.dart';

/// Subscription settings: scheduled auto-refresh, HWID, User-Agent.
class SubscriptionSettingsScreen extends ConsumerStatefulWidget {
  /// Opened from Settings and from the Configs tab — breadcrumb parent.
  final String breadcrumbParent;

  const SubscriptionSettingsScreen({super.key, required this.breadcrumbParent});

  @override
  ConsumerState<SubscriptionSettingsScreen> createState() => _SubscriptionSettingsScreenState();
}

class _SubscriptionSettingsScreenState extends ConsumerState<SubscriptionSettingsScreen> {
  TextEditingController? _uaCtrl;

  void _ensureControllers(AppSettings s) {
    _uaCtrl ??= TextEditingController(text: s.subUserAgent);
  }

  @override
  void dispose() {
    _uaCtrl?.dispose();
    super.dispose();
  }

  /// Read in [initState]: the User-Agent field commits its last edit while the screen is being disposed.
  late final ProviderContainer _container;

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
  }

  void _set<T>(SettingField<T> field, T value) => _container.read(settingsProvider.notifier).set(field, value);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    final settingsAsync = ref.watch(settingsProvider);
    final profileState = ref.watch(profileProvider).maybeWhen(data: (d) => d, orElse: () => null);
    final locked = profileState?.isReadonly ?? false;

    return Scaffold(
      body: SafeArea(
        child: settingsAsync.when(
          loading: () => Center(child: CircularProgressIndicator(color: t.accent, strokeWidth: 1.5)),
          error: (e, _) => Center(
            child: Text(context.l10n.commonErrorWith('$e'), style: AppTheme.mono(size: 12, color: t.danger)),
          ),
          data: (s) {
            _ensureControllers(s);
            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: t.line)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'teapod.stream // subs',
                        style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1),
                      ),
                      Text(
                        s.subAutoRefresh ? 'auto [${s.subAutoRefreshHours}h]' : 'auto [off]',
                        style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
                BreadcrumbBar(t: t, parent: widget.breadcrumbParent, current: 'subscriptions'),
                HeroPanel(t: t, tagline: context.l10n.subsTagline, title: 'SUBS'),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      SetSectionHeader(t: t, addr: '0x10', label: 'refresh'),
                      SetRowToggle(
                        t: t,
                        title: context.l10n.subsAutoRefresh,
                        hint: context.l10n.subsAutoRefreshHint,
                        value: s.subAutoRefresh,
                        locked: locked,
                        onChange: (v) => _set(SettingFields.subAutoRefresh, v),
                      ),
                      if (s.subAutoRefresh)
                        SetInlineField(
                          t: t,
                          label: context.l10n.subsInterval,
                          locked: locked,
                          child: SetSegSquare(
                            t: t,
                            value: s.subAutoRefreshHours.toString(),
                            opts: [
                              for (final h in const [1, 3, 6, 12, 24]) ('$h', context.l10n.unitHours(h)),
                            ],
                            locked: locked,
                            onChanged: (v) => _set(SettingFields.subAutoRefreshHours, int.parse(v)),
                          ),
                        ),
                      SetSectionHeader(t: t, addr: '0x20', label: 'identity'),
                      SetRowToggle(
                        t: t,
                        title: 'HWID',
                        hint: context.l10n.subsHwidHint,
                        value: s.hwidEnabled,
                        locked: locked,
                        onChange: (v) => _set(SettingFields.hwidEnabled, v),
                      ),
                      SetInlineField(
                        t: t,
                        label: 'User-Agent',
                        locked: locked,
                        child: SetCredField(
                          t: t,
                          controller: _uaCtrl!,
                          enabled: !locked,
                          hint: context.l10n.commonDefaultLower,
                          width: 200,
                          fontSize: 13,
                          textAlign: TextAlign.start,
                          onCommit: (v) => _set(SettingFields.subUserAgent, v),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
