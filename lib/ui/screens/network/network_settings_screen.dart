// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import '../../../core/cores/core_backend.dart';
import '../../widgets/feature_gate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/heartbeat_settings.dart';
import '../../../core/models/xray_tuning.dart';
import '../../../core/models/app_settings.dart';
import '../../../core/models/setting_field.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/breadcrumb_bar.dart';
import '../../widgets/hero_panel.dart';
import '../../widgets/reconnect_banner.dart';
import '../../widgets/settings_shared.dart';
import '../../../l10n/l10n.dart';
import '../../widgets/tap_target.dart';

part 'connection.dart';
part 'heartbeat.dart';
part 'pickers.dart';
part 'tuning.dart';

/// Expert network settings: SOCKS, TUN, TLS fingerprint, observatory.
class NetworkSettingsScreen extends ConsumerStatefulWidget {
  const NetworkSettingsScreen({super.key});

  @override
  ConsumerState<NetworkSettingsScreen> createState() => _NetworkSettingsScreenState();
}

class _NetworkSettingsScreenState extends ConsumerState<NetworkSettingsScreen> {
  TextEditingController? _socksPortCtrl;
  TextEditingController? _socksUserCtrl;
  TextEditingController? _socksPasswordCtrl;
  TextEditingController? _mtuCtrl;
  TextEditingController? _obsCtrl;
  TextEditingController? _fragPacketsCtrl;
  TextEditingController? _fragLengthCtrl;
  TextEditingController? _fragIntervalCtrl;
  TextEditingController? _noisePacketCtrl;
  TextEditingController? _noiseDelayCtrl;
  TextEditingController? _muxConcCtrl;
  TextEditingController? _muxXudpCtrl;
  TextEditingController? _hbThresholdCtrl;
  TextEditingController? _hbUrlCtrl;

  void _ensureControllers(AppSettings s) {
    _socksPortCtrl ??= TextEditingController(text: s.socksPort.toString());
    _socksUserCtrl ??= TextEditingController(text: s.socksUser);
    _socksPasswordCtrl ??= TextEditingController(text: s.socksPassword);
    _mtuCtrl ??= TextEditingController(text: s.mtu.toString());
    _obsCtrl ??= TextEditingController(text: s.obsProbeIntervalSec.toString());
    _fragPacketsCtrl ??= TextEditingController(text: s.fragment.packets);
    _fragLengthCtrl ??= TextEditingController(text: s.fragment.length);
    _fragIntervalCtrl ??= TextEditingController(text: s.fragment.interval);
    _noisePacketCtrl ??= TextEditingController(text: s.noise.packet);
    _noiseDelayCtrl ??= TextEditingController(text: s.noise.delay);
    _muxConcCtrl ??= TextEditingController(text: s.mux.concurrency.toString());
    _muxXudpCtrl ??= TextEditingController(text: s.mux.xudpConcurrency.toString());
    _hbThresholdCtrl ??= TextEditingController(text: s.heartbeat.failureThreshold.toString());
    _hbUrlCtrl ??= TextEditingController(text: s.heartbeat.customUrl);
  }

  @override
  void dispose() {
    _socksPortCtrl?.dispose();
    _socksUserCtrl?.dispose();
    _socksPasswordCtrl?.dispose();
    _mtuCtrl?.dispose();
    _obsCtrl?.dispose();
    _fragPacketsCtrl?.dispose();
    _fragLengthCtrl?.dispose();
    _fragIntervalCtrl?.dispose();
    _noisePacketCtrl?.dispose();
    _noiseDelayCtrl?.dispose();
    _muxConcCtrl?.dispose();
    _muxXudpCtrl?.dispose();
    _hbThresholdCtrl?.dispose();
    _hbUrlCtrl?.dispose();
    super.dispose();
  }

  /// Read in [initState]: a text field commits its last edit while the screen is being disposed, when `ref` can't
  /// be used anymore.
  late final ProviderContainer _container;

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
  }

  SettingsNotifier get _settings => _container.read(settingsProvider.notifier);

  void _set<T>(SettingField<T> field, T value) => _settings.set(field, value);

  /// Login and password are saved together: the text of both fields now (the change may run after they are gone).
  void _updateSocksCredentials() {
    final user = _socksUserCtrl!.text;
    final password = _socksPasswordCtrl!.text;
    _settings.setSocksCredentials(user, password);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    final settingsAsync = ref.watch(settingsProvider);
    final profileState = ref.watch(profileProvider).maybeWhen(data: (d) => d, orElse: () => null);
    final locked = profileState?.isReadonly ?? false;
    final l = context.l10n;

    return Scaffold(
      body: SafeArea(
        child: settingsAsync.when(
          loading: () => Center(child: CircularProgressIndicator(color: t.accent, strokeWidth: 1.5)),
          error: (e, _) => Center(
            child: Text(l.commonErrorWith('$e'), style: AppTheme.mono(size: 12, color: t.danger)),
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
                        'teapod.stream // network',
                        style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1),
                      ),
                      Text(
                        'socks [${s.randomPort ? 'rnd' : s.socksPort}]',
                        style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
                BreadcrumbBar(t: t, parent: 'settings', current: 'network'),
                HeroPanel(t: t, tagline: l.networkTagline, title: 'NETWORK'),
                const ReconnectBanner(),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      ..._socksSection(context, t, s, locked),
                      ..._trafficSection(context, t, s, locked),
                      ..._tunSection(context, t, s, locked),
                      ..._fragmentSection(context, t, s, locked),
                      ..._noiseSection(context, t, s, locked),
                      ..._muxSection(context, t, s, locked),
                      ..._heartbeatSection(context, t, s, locked),
                      const SizedBox(height: 32),
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
