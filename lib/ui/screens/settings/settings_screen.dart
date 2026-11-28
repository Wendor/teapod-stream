import 'dart:async';
import '../../../core/models/app_message.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import '../../../core/models/core_kind.dart';
import '../../../providers/core_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../providers/app_info_provider.dart';
import '../../../providers/update_provider.dart';
import '../../../core/models/dns_config.dart';
import '../../../core/services/update_service.dart' show UpdateInfo;
import '../../../core/models/app_settings.dart';
import '../../../core/models/setting_field.dart';
import '../logs_screen.dart';
import '../network_settings_screen.dart';
import '../profiles_screen.dart';
import '../dns_settings_screen.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/theme_provider.dart';
import '../../../providers/locale_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/settings_shared.dart';
import '../../widgets/reconnect_banner.dart';
import '../../widgets/pressable.dart';
import '../../widgets/tap_target.dart';
import '../subscription_settings_screen.dart';
import '../whats_new_screen.dart';
import '../../../l10n/l10n.dart';
import '../../../core/services/platform_service.dart';

part 'appearance.dart';
part 'core_order.dart';
part 'header.dart';
part 'rows.dart';
part 'update.dart';

// ── Screen ────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Map<String, String>? _coreVersions;

  @override
  void initState() {
    super.initState();
    _loadBinaryVersions();
  }

  Future<void> _loadBinaryVersions() async {
    try {
      final result = await ref.read(platformServiceProvider).binaryVersions();
      if (mounted) {
        setState(() {
          _coreVersions = result;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _coreVersions = const {};
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final profileState = ref.watch(profileProvider).maybeWhen(data: (d) => d, orElse: () => null);
    final version = ref.watch(appVersionProvider).maybeWhen(data: (v) => v, orElse: () => 'v?');
    final t = Theme.of(context).extension<TeapodTokens>()!;
    final profileReadonly = profileState?.isReadonly ?? false;
    final locked = profileReadonly;
    final updateState = ref.watch(updateProvider);
    final hasUpdate =
        updateState is UpdateAvailable || updateState is UpdateDownloading || updateState is UpdateDownloaded;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _SetHeaderStrip(t: t, locked: locked),
            _SetHeroPanel(
              t: t,
              locked: locked,
              profileName: profileState?.activeProfile?.name ?? 'default',
              profileReadonly: profileReadonly,
            ),
            const ReconnectBanner(),
            Expanded(
              child: settingsAsync.when(
                loading: () => Center(child: CircularProgressIndicator(color: t.accent, strokeWidth: 1.5)),
                error: (e, _) => Center(
                  child: Text(
                    context.l10n.commonErrorWith(ReasonException.ofError(e).localize(context.l10n)),
                    style: AppTheme.mono(size: 12, color: t.danger),
                  ),
                ),
                data: (settings) => _SettingsBody(
                  settings: settings,
                  isProfileReadonly: profileReadonly,
                  hasUpdate: hasUpdate,
                  version: version,
                  coreVersions: _coreVersions,
                  notifier: ref.read(settingsProvider.notifier),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Console header strip ──────────────────────────────────────────

class _SettingsBody extends StatelessWidget {
  final AppSettings settings;
  final bool isProfileReadonly;
  final bool hasUpdate;
  final String version;

  /// Core versions by `CoreKind.versionKey`; null — not loaded yet.
  final Map<String, String>? coreVersions;

  final SettingsNotifier notifier;

  const _SettingsBody({
    required this.settings,
    required this.isProfileReadonly,
    required this.hasUpdate,
    required this.version,
    required this.coreVersions,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    final s = settings;
    final locked = isProfileReadonly;
    final l = context.l10n;

    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.zero,
          children: [
            // Update available — tile at the top so it isn't lost at the end of the list
            if (hasUpdate)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                decoration: BoxDecoration(
                  color: t.accentFade,
                  border: Border(bottom: BorderSide(color: t.accent)),
                ),
                child: const _UpdateTile(),
              ),

            // ── 0x10 DIAGNOSTICS ──────────────────────────────────
            SetSectionHeader(t: t, addr: '0x10', label: 'diagnostics'),
            SetRowChev(
              t: t,
              title: l.settingsLogs,
              hint: l.settingsLogsHint,
              last: true,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const LogsScreen(breadcrumbParent: 'settings')),
              ),
            ),

            // ── 0x20 APPEARANCE ───────────────────────────────────
            SetSectionHeader(t: t, addr: '0x20', label: 'appearance'),
            _AppearanceRows(t: t),

            // ── 0x30 CONNECTION ───────────────────────────────────
            SetSectionHeader(t: t, addr: '0x30', label: 'connection'),
            SetRowToggle(
              t: t,
              title: l.settingsAutoConnect,
              hint: l.settingsAutoConnectHint,
              value: s.autoConnect,
              locked: locked,
              onChange: (v) => notifier.set(SettingFields.autoConnect, v),
            ),
            SetRowToggle(
              t: t,
              title: l.settingsStartOnBoot,
              hint: l.settingsStartOnBootHint,
              value: s.autoStartOnBoot,
              locked: locked,
              onChange: (v) => notifier.set(SettingFields.autoStartOnBoot, v),
            ),
            SetRowToggle(
              t: t,
              title: l.settingsAutomation,
              hint: l.settingsAutomationHint,
              value: s.automationEnabled,
              locked: locked,
              onChange: (v) => notifier.set(SettingFields.automationEnabled, v),
            ),
            SetRowToggle(
              t: t,
              title: l.settingsNotification,
              hint: l.settingsNotificationHint,
              value: s.showNotification,
              locked: locked,
              onChange: (v) => notifier.set(SettingFields.showNotification, v),
            ),
            SetRowChev(
              t: t,
              title: l.settingsSubscriptions,
              hint: s.subAutoRefresh ? l.settingsSubAutoRefreshOn(s.subAutoRefreshHours) : l.settingsSubAutoRefreshOff,
              last: true,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const SubscriptionSettingsScreen(breadcrumbParent: 'settings')),
              ),
            ),

            // ── 0x40 NETWORK ──────────────────────────────────────
            SetSectionHeader(t: t, addr: '0x40', label: 'network'),
            _CoreOrderList(t: t, settings: s, versions: coreVersions, locked: locked, notifier: notifier),
            SetRowChev(
              t: t,
              title: l.settingsNetwork,
              hint:
                  'SOCKS ${s.randomPort ? 'random' : s.socksPort} · MTU ${s.mtu}'
                  '${s.proxyOnly ? ' · ${l.settingsProxyOnlyShort}' : ''}',
              onTap: () =>
                  Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const NetworkSettingsScreen())),
            ),
            SetRowChev(
              t: t,
              title: 'DNS',
              hint: '${s.dnsMode == DnsMode.proxy ? l.dnsViaVpn : l.dnsDirect} · ${_dnsLabel(s)}',
              last: true,
              onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const DnsSettingsScreen())),
            ),

            // ── 0x50 SYSTEM ───────────────────────────────────────
            SetSectionHeader(t: t, addr: '0x50', label: 'system'),
            _ProfilesRow(t: t),
            const _BatteryRow(),
            SetInlineField(t: t, label: l.settingsUpdateChannel, child: const _UpdateChannelSegment()),
            // Update tile (complex) — shown at the top when an update is available
            if (!hasUpdate)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: t.line)),
                ),
                child: const _UpdateTile(),
              ),

            // ── 0x60 ABOUT ────────────────────────────────────────
            SetSectionHeader(t: t, addr: '0x60', label: 'about'),
            _KVRow(t: t, k: 'version', v: version.isEmpty ? '...' : version),
            _KVRowTap(
              t: t,
              k: 'changelog',
              v: l.whatsNewTitle,
              onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const WhatsNewScreen())),
            ),
            _KVRowTap(
              t: t,
              k: 'licenses',
              v: 'open-source',
              onTap: () => showLicensePage(context: context, applicationName: 'TeapodStream'),
            ),
            _KVRowTap(
              t: t,
              k: 'source',
              v: 'github.com/Wendor/teapod-stream',
              onTap: () => launchUrl(
                Uri.parse('https://github.com/Wendor/teapod-stream'),
                mode: LaunchMode.externalApplication,
              ).ignore(),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ],
    );
  }
}

// ── Row: KV ───────────────────────────────────────────────────────
