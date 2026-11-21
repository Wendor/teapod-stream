// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import '../../core/cores/core_backend.dart';
import '../widgets/feature_gate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/heartbeat_settings.dart';
import '../../core/models/xray_tuning.dart';
import '../../core/models/app_settings.dart';
import '../../providers/profile_provider.dart';
import '../../providers/settings_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/breadcrumb_bar.dart';
import '../widgets/hero_panel.dart';
import '../widgets/reconnect_banner.dart';
import '../widgets/settings_shared.dart';
import '../../l10n/l10n.dart';

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

  void _update(AppSettings s) => ref.read(settingsProvider.notifier).save(s);

  static String _fpLabel(TlsFingerprint fp) => fp == TlsFingerprint.defaultFp ? 'DEFAULT' : fp.name.toUpperCase();

  /// Screen-styled dropdown of values; used for enums.
  void _showEnumPicker<T>(
    BuildContext context, {
    required String title,
    required List<T> values,
    required T current,
    required String Function(T) labelOf,
    required void Function(T) onPick,
  }) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title, style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: t.line),
            for (final v in values)
              InkWell(
                onTap: () {
                  onPick(v);
                  Navigator.pop(ctx);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          labelOf(v),
                          style: AppTheme.mono(size: 12, color: v == current ? t.accent : t.text, letterSpacing: 0.5),
                        ),
                      ),
                      if (v == current) Text('•', style: AppTheme.mono(size: 12, color: t.accent)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showFingerprintPicker(BuildContext context, AppSettings s) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'tls // fingerprint',
                      style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1),
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: t.line),
            for (final fp in TlsFingerprint.values)
              InkWell(
                onTap: () {
                  _update(s.copyWith(tlsFingerprint: fp));
                  Navigator.pop(ctx);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _fpLabel(fp),
                          style: AppTheme.mono(
                            size: 12,
                            color: fp == s.tlsFingerprint ? t.accent : t.text,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      if (fp == s.tlsFingerprint) Text('●', style: AppTheme.mono(size: 10, color: t.accent)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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
                      SetSectionHeader(t: t, addr: '0x31', label: 'socks'),
                      SetRowToggle(
                        t: t,
                        title: l.networkRandomPort,
                        hint: l.networkRandomPortHint,
                        value: s.randomPort,
                        locked: locked,
                        onChange: (v) => _update(s.copyWith(randomPort: v)),
                      ),
                      if (!s.randomPort)
                        SetInlineField(
                          t: t,
                          label: l.networkSocksPort,
                          locked: locked,
                          child: SetNumField(
                            t: t,
                            controller: _socksPortCtrl!,
                            enabled: !locked,
                            hint: '10808',
                            onChanged: (v) {
                              final socks = int.tryParse(v);
                              if (socks != null) {
                                _update(s.copyWith(socksPort: socks.clamp(1024, 65535)));
                              }
                            },
                          ),
                        ),
                      SetRowToggle(
                        t: t,
                        title: l.networkRandomCreds,
                        hint: l.networkRandomCredsHint,
                        value: s.randomCredentials,
                        locked: locked,
                        onChange: (v) => _update(s.copyWith(randomCredentials: v)),
                      ),
                      if (!s.randomCredentials) ...[
                        SetInlineField(
                          t: t,
                          label: l.networkSocksLogin,
                          locked: locked,
                          child: SetCredField(
                            controller: _socksUserCtrl!,
                            enabled: !locked,
                            hint: l.networkNoAuth,
                            onChanged: (_) => _update(
                              s.copyWith(socksUser: _socksUserCtrl!.text, socksPassword: _socksPasswordCtrl!.text),
                            ),
                            t: t,
                          ),
                        ),
                        SetInlineField(
                          t: t,
                          label: l.networkSocksPassword,
                          locked: locked,
                          child: SetCredField(
                            controller: _socksPasswordCtrl!,
                            enabled: !locked,
                            hint: l.networkNoAuth,
                            obscureText: true,
                            onChanged: (_) => _update(
                              s.copyWith(socksUser: _socksUserCtrl!.text, socksPassword: _socksPasswordCtrl!.text),
                            ),
                            t: t,
                          ),
                        ),
                      ],
                      FeatureGate(
                        feature: CoreFeature.proxyOnly,
                        child: SetRowToggle(
                          t: t,
                          title: l.networkProxyOnly,
                          hint: l.networkProxyOnlyHint,
                          value: s.proxyOnly,
                          locked: locked,
                          onChange: (v) => _update(s.copyWith(proxyOnly: v)),
                        ),
                      ),
                      SetSectionHeader(t: t, addr: '0x32', label: 'traffic'),
                      SetRowToggle(
                        t: t,
                        title: 'UDP',
                        hint: l.networkUdpHint,
                        value: s.enableUdp,
                        locked: locked,
                        onChange: (v) => _update(s.copyWith(enableUdp: v)),
                      ),
                      FeatureGate(
                        feature: CoreFeature.icmpToggle,
                        child: SetRowToggle(
                          t: t,
                          title: 'ICMP (ping)',
                          hint: l.networkIcmpHint,
                          value: s.allowIcmp,
                          locked: locked,
                          onChange: (v) => _update(s.copyWith(allowIcmp: v)),
                        ),
                      ),
                      SetRowToggle(
                        t: t,
                        title: l.networkBlockQuic,
                        hint: l.networkBlockQuicHint,
                        value: s.blockQuic,
                        locked: locked,
                        onChange: (v) => _update(s.copyWith(blockQuic: v)),
                      ),
                      // TLS fingerprint (uTLS) override
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: t.lineSoft)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('TLS fingerprint', style: AppTheme.sans(size: 14, color: t.text)),
                                  const SizedBox(height: 3),
                                  Text(
                                    l.networkFingerprintHint,
                                    style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 0.5),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            GestureDetector(
                              onTap: locked
                                  ? () => showReadonlySnack(context)
                                  : () => _showFingerprintPicker(context, s),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(border: Border.all(color: t.line)),
                                child: Text(
                                  _fpLabel(s.tlsFingerprint),
                                  style: AppTheme.mono(
                                    size: 11,
                                    color: locked ? t.textDim : t.accent,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SetSectionHeader(t: t, addr: '0x33', label: 'tun'),
                      if (!s.proxyOnly)
                        SetRowToggle(
                          t: t,
                          title: l.networkIpv6,
                          hint: l.networkIpv6Hint,
                          value: s.ipv6Enabled,
                          locked: locked,
                          onChange: (v) => _update(s.copyWith(ipv6Enabled: v)),
                        ),
                      if (!s.proxyOnly)
                        FeatureGate(
                          feature: CoreFeature.customMtu,
                          child: SetInlineField(
                            t: t,
                            label: 'MTU',
                            locked: locked,
                            child: SetNumField(
                              t: t,
                              controller: _mtuCtrl!,
                              enabled: !locked,
                              hint: '1500',
                              onChanged: (v) {
                                final mtu = int.tryParse(v);
                                if (mtu != null) {
                                  _update(s.copyWith(mtu: mtu.clamp(576, 9000)));
                                }
                              },
                            ),
                          ),
                        ),
                      FeatureGate(
                        feature: CoreFeature.observatory,
                        child: SetInlineField(
                          t: t,
                          label: l.networkObservatoryInterval,
                          locked: locked,
                          child: SetNumField(
                            t: t,
                            controller: _obsCtrl!,
                            enabled: !locked,
                            hint: '600',
                            onChanged: (v) {
                              final sec = int.tryParse(v);
                              if (sec != null) {
                                _update(s.copyWith(obsProbeIntervalSec: sec.clamp(0, 86400)));
                              }
                            },
                          ),
                        ),
                      ),
                      SetSectionHeader(t: t, addr: '0x34', label: 'fragment'),
                      SetRowToggle(
                        t: t,
                        title: l.networkFragment,
                        hint: l.networkFragmentHint,
                        value: s.fragment.enabled,
                        locked: locked,
                        onChange: (v) => _update(s.copyWith(fragment: s.fragment.copyWith(enabled: v))),
                      ),
                      if (s.fragment.enabled) ...[
                        SetInlineField(
                          t: t,
                          label: l.networkFragmentPackets,
                          locked: locked,
                          child: SetCredField(
                            t: t,
                            controller: _fragPacketsCtrl!,
                            enabled: !locked,
                            hint: 'tlshello',
                            onChanged: (v) => _update(s.copyWith(fragment: s.fragment.copyWith(packets: v.trim()))),
                          ),
                        ),
                        SetInlineField(
                          t: t,
                          label: l.networkFragmentLength,
                          locked: locked,
                          child: SetCredField(
                            t: t,
                            controller: _fragLengthCtrl!,
                            enabled: !locked,
                            hint: '100-200',
                            onChanged: (v) => _update(s.copyWith(fragment: s.fragment.copyWith(length: v.trim()))),
                          ),
                        ),
                        SetInlineField(
                          t: t,
                          label: l.networkPauseMs,
                          locked: locked,
                          child: SetCredField(
                            t: t,
                            controller: _fragIntervalCtrl!,
                            enabled: !locked,
                            hint: '10-20',
                            onChanged: (v) => _update(s.copyWith(fragment: s.fragment.copyWith(interval: v.trim()))),
                          ),
                        ),
                      ],
                      if (s.fragment.enabled && !s.fragment.isValid) _HintRow(t: t, text: l.networkFragmentInvalid),
                      SetSectionHeader(t: t, addr: '0x35', label: 'noise'),
                      SetRowToggle(
                        t: t,
                        title: l.networkNoise,
                        hint: l.networkNoiseHint,
                        value: s.noise.enabled,
                        locked: locked,
                        onChange: (v) => _update(s.copyWith(noise: s.noise.copyWith(enabled: v))),
                      ),
                      if (s.noise.enabled) ...[
                        _PickerRow(
                          t: t,
                          title: l.networkNoiseType,
                          hint: l.networkNoiseTypeHint,
                          value: s.noise.type.name.toUpperCase(),
                          locked: locked,
                          onTap: () => _showEnumPicker<NoiseType>(
                            context,
                            title: 'noise // type',
                            values: NoiseType.values,
                            current: s.noise.type,
                            labelOf: (v) => v.name.toUpperCase(),
                            onPick: (v) => _update(s.copyWith(noise: s.noise.copyWith(type: v))),
                          ),
                        ),
                        SetInlineField(
                          t: t,
                          label: s.noise.type == NoiseType.rand ? l.networkNoiseLength : l.networkNoisePacket,
                          locked: locked,
                          child: SetCredField(
                            t: t,
                            controller: _noisePacketCtrl!,
                            enabled: !locked,
                            hint: s.noise.type == NoiseType.rand ? '50-100' : l.networkNoiseContent,
                            onChanged: (v) => _update(s.copyWith(noise: s.noise.copyWith(packet: v.trim()))),
                          ),
                        ),
                        SetInlineField(
                          t: t,
                          label: l.networkPauseMs,
                          locked: locked,
                          child: SetCredField(
                            t: t,
                            controller: _noiseDelayCtrl!,
                            enabled: !locked,
                            hint: '10-20',
                            onChanged: (v) => _update(s.copyWith(noise: s.noise.copyWith(delay: v.trim()))),
                          ),
                        ),
                        if (!s.noise.isValid)
                          _HintRow(
                            t: t,
                            text: s.noise.type == NoiseType.rand
                                ? l.networkNoiseInvalidRand
                                : l.networkNoiseInvalidPacket,
                          ),
                      ],
                      SetSectionHeader(t: t, addr: '0x36', label: 'mux'),
                      FeatureGate(
                        feature: CoreFeature.mux,
                        child: SetRowToggle(
                          t: t,
                          title: 'Mux',
                          hint: l.networkMuxHint,
                          value: s.mux.enabled,
                          locked: locked,
                          onChange: (v) => _update(s.copyWith(mux: s.mux.copyWith(enabled: v))),
                        ),
                      ),
                      if (s.mux.enabled) ...[
                        SetInlineField(
                          t: t,
                          label: l.networkMuxTcp,
                          locked: locked,
                          child: SetNumField(
                            t: t,
                            controller: _muxConcCtrl!,
                            enabled: !locked,
                            hint: '8',
                            onChanged: (v) {
                              final n = int.tryParse(v);
                              if (n != null) {
                                _update(s.copyWith(mux: s.mux.copyWith(concurrency: n.clamp(1, 1024))));
                              }
                            },
                          ),
                        ),
                        SetInlineField(
                          t: t,
                          label: l.networkMuxXudp,
                          locked: locked,
                          child: SetNumField(
                            t: t,
                            controller: _muxXudpCtrl!,
                            enabled: !locked,
                            hint: '16',
                            onChanged: (v) {
                              final n = int.tryParse(v);
                              if (n != null) {
                                _update(s.copyWith(mux: s.mux.copyWith(xudpConcurrency: n.clamp(1, 1024))));
                              }
                            },
                          ),
                        ),
                        _PickerRow(
                          t: t,
                          title: l.networkMuxQuic,
                          hint: l.networkMuxQuicHint,
                          value: s.mux.xudpProxyUDP443.name.toUpperCase(),
                          locked: locked,
                          onTap: () => _showEnumPicker<XudpUdp443>(
                            context,
                            title: 'mux // xudpProxyUDP443',
                            values: XudpUdp443.values,
                            current: s.mux.xudpProxyUDP443,
                            labelOf: (v) => v.name.toUpperCase(),
                            onPick: (v) => _update(s.copyWith(mux: s.mux.copyWith(xudpProxyUDP443: v))),
                          ),
                        ),
                      ],
                      SetSectionHeader(t: t, addr: '0x37', label: 'heartbeat'),
                      _PickerRow(
                        t: t,
                        title: l.networkProbeType,
                        hint: l.networkProbeTypeHint,
                        value: s.heartbeat.probe.name.toUpperCase(),
                        locked: locked,
                        onTap: () => _showEnumPicker<HeartbeatProbe>(
                          context,
                          title: 'heartbeat // probe',
                          values: HeartbeatProbe.values,
                          current: s.heartbeat.probe,
                          labelOf: (v) => v.name.toUpperCase(),
                          onPick: (v) => _update(s.copyWith(heartbeat: s.heartbeat.copyWith(probe: v))),
                        ),
                      ),
                      if (s.heartbeat.probe != HeartbeatProbe.passive) ...[
                        _PickerRow(
                          t: t,
                          title: l.networkProbeTarget,
                          hint: l.networkProbeTargetHint,
                          value: s.heartbeat.target.name.toUpperCase(),
                          locked: locked,
                          onTap: () => _showEnumPicker<HeartbeatTarget>(
                            context,
                            title: 'heartbeat // target',
                            values: HeartbeatTarget.values,
                            current: s.heartbeat.target,
                            labelOf: (v) => v.name.toUpperCase(),
                            onPick: (v) => _update(s.copyWith(heartbeat: s.heartbeat.copyWith(target: v))),
                          ),
                        ),
                        if (s.heartbeat.target == HeartbeatTarget.custom)
                          SetInlineField(
                            t: t,
                            label: 'URL',
                            locked: locked,
                            child: SetCredField(
                              t: t,
                              controller: _hbUrlCtrl!,
                              enabled: !locked,
                              hint: 'http://…/generate_204',
                              onChanged: (v) =>
                                  _update(s.copyWith(heartbeat: s.heartbeat.copyWith(customUrl: v.trim()))),
                            ),
                          ),
                      ],
                      SetInlineField(
                        t: t,
                        label: l.networkFailureThreshold,
                        locked: locked,
                        child: SetNumField(
                          t: t,
                          controller: _hbThresholdCtrl!,
                          enabled: !locked,
                          hint: '3',
                          onChanged: (v) {
                            final n = int.tryParse(v);
                            if (n != null) {
                              _update(s.copyWith(heartbeat: s.heartbeat.copyWith(failureThreshold: n.clamp(1, 10))));
                            }
                          },
                        ),
                      ),
                      _PickerRow(
                        t: t,
                        title: l.networkFailAction,
                        hint: l.networkFailActionHint,
                        value: s.heartbeat.failAction.name.toUpperCase(),
                        locked: locked,
                        onTap: () => _showEnumPicker<HeartbeatFailAction>(
                          context,
                          title: 'heartbeat // action',
                          values: HeartbeatFailAction.values,
                          current: s.heartbeat.failAction,
                          labelOf: (v) => v.name.toUpperCase(),
                          onPick: (v) => _update(s.copyWith(heartbeat: s.heartbeat.copyWith(failAction: v))),
                        ),
                      ),
                      if (s.heartbeat.failAction == HeartbeatFailAction.switchConfig)
                        _PickerRow(
                          t: t,
                          title: l.networkSwitchSource,
                          hint: l.networkSwitchSourceHint,
                          value: s.heartbeat.switchSource.name.toUpperCase(),
                          locked: locked,
                          onTap: () => _showEnumPicker<SwitchSource>(
                            context,
                            title: 'heartbeat // source',
                            values: SwitchSource.values,
                            current: s.heartbeat.switchSource,
                            labelOf: (v) => v.name.toUpperCase(),
                            onPick: (v) => _update(s.copyWith(heartbeat: s.heartbeat.copyWith(switchSource: v))),
                          ),
                        ),
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

/// Setting row with a value button that opens a list picker.
class _PickerRow extends StatelessWidget {
  final TeapodTokens t;
  final String title;
  final String hint;
  final String value;
  final bool locked;
  final VoidCallback onTap;

  const _PickerRow({
    required this.t,
    required this.title,
    required this.hint,
    required this.value,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.lineSoft)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.sans(size: 14, color: t.text)),
                const SizedBox(height: 3),
                Text(hint, style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 0.5)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: locked ? () => showReadonlySnack(context) : onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(border: Border.all(color: t.line)),
              child: Text(
                value,
                style: AppTheme.mono(size: 11, color: locked ? t.textDim : t.accent, letterSpacing: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Warning under a section: the setting is invalid and won't make it into the config.
class _HintRow extends StatelessWidget {
  final TeapodTokens t;
  final String text;

  const _HintRow({required this.t, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.lineSoft)),
      ),
      child: Text(text, style: AppTheme.mono(size: 10, color: t.danger, letterSpacing: 0.5)),
    );
  }
}
