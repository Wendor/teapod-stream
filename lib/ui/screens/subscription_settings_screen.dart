import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/settings_service.dart';
import '../../providers/profile_provider.dart';
import '../../providers/settings_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/breadcrumb_bar.dart';
import '../widgets/hero_panel.dart';
import '../widgets/settings_shared.dart';

/// Настройки подписок: автообновление по расписанию, HWID, User-Agent.
class SubscriptionSettingsScreen extends ConsumerStatefulWidget {
  /// Экран открывается из Настроек и с вкладки «Конфиги» — родитель для breadcrumb.
  final String breadcrumbParent;

  const SubscriptionSettingsScreen({super.key, required this.breadcrumbParent});

  @override
  ConsumerState<SubscriptionSettingsScreen> createState() =>
      _SubscriptionSettingsScreenState();
}

class _SubscriptionSettingsScreenState
    extends ConsumerState<SubscriptionSettingsScreen> {
  TextEditingController? _uaCtrl;

  void _ensureControllers(AppSettings s) {
    _uaCtrl ??= TextEditingController(text: s.subUserAgent);
  }

  @override
  void dispose() {
    _uaCtrl?.dispose();
    super.dispose();
  }

  void _update(AppSettings s) => ref.read(settingsProvider.notifier).save(s);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    final settingsAsync = ref.watch(settingsProvider);
    final profileState =
        ref.watch(profileProvider).maybeWhen(data: (d) => d, orElse: () => null);
    final locked = profileState?.isReadonly ?? false;

    return Scaffold(
      body: SafeArea(
        child: settingsAsync.when(
          loading: () => Center(
              child: CircularProgressIndicator(color: t.accent, strokeWidth: 1.5)),
          error: (e, _) => Center(
              child: Text('Ошибка: $e', style: AppTheme.mono(size: 12, color: t.danger))),
          data: (s) {
            _ensureControllers(s);
            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration:
                      BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('teapod.stream // subs',
                          style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                      Text(s.subAutoRefresh ? 'auto [${s.subAutoRefreshHours}h]' : 'auto [off]',
                          style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                    ],
                  ),
                ),
                BreadcrumbBar(
                    t: t, parent: widget.breadcrumbParent, current: 'subscriptions'),
                HeroPanel(
                  t: t,
                  tagline: 'ПОДПИСКИ · ОБНОВЛЕНИЕ',
                  title: 'SUBS',
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      SetSectionHeader(t: t, addr: '0x10', label: 'refresh'),
                      SetRowToggle(
                        t: t,
                        title: 'Автообновление подписок',
                        hint: 'Обновлять подписки по расписанию',
                        value: s.subAutoRefresh,
                        locked: locked,
                        onChange: (v) => _update(s.copyWith(subAutoRefresh: v)),
                      ),
                      if (s.subAutoRefresh)
                        SetInlineField(
                          t: t,
                          label: 'Интервал',
                          locked: locked,
                          child: SetSegSquare(
                            t: t,
                            value: s.subAutoRefreshHours.toString(),
                            opts: const [
                              ('1', '1ч'),
                              ('3', '3ч'),
                              ('6', '6ч'),
                              ('12', '12ч'),
                              ('24', '24ч'),
                            ],
                            locked: locked,
                            onChanged: (v) =>
                                _update(s.copyWith(subAutoRefreshHours: int.parse(v))),
                          ),
                        ),
                      SetSectionHeader(t: t, addr: '0x20', label: 'identity'),
                      SetRowToggle(
                        t: t,
                        title: 'HWID',
                        hint: 'Отправлять ID устройства для привязки подписки',
                        value: s.hwidEnabled,
                        locked: locked,
                        onChange: (v) => _update(s.copyWith(hwidEnabled: v)),
                      ),
                      SetInlineField(
                        t: t,
                        label: 'User-Agent',
                        locked: locked,
                        child: SizedBox(
                          width: 200,
                          child: TextField(
                            controller: _uaCtrl,
                            enabled: !locked,
                            keyboardType: TextInputType.text,
                            onChanged: (v) => _update(s.copyWith(subUserAgent: v)),
                            onEditingComplete: () => FocusScope.of(context).unfocus(),
                            style: AppTheme.mono(size: 13, color: t.text),
                            decoration: InputDecoration(
                              hintText: 'по умолчанию',
                              hintStyle: AppTheme.mono(size: 12, color: t.textMuted),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              isDense: true,
                              enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: t.line),
                                  borderRadius: BorderRadius.zero),
                              focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: t.accent),
                                  borderRadius: BorderRadius.zero),
                              disabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: t.lineSoft),
                                  borderRadius: BorderRadius.zero),
                            ),
                          ),
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
