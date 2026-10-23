import '../../core/constants/core_features.dart';
import '../widgets/feature_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/dns_config.dart';
import '../../core/services/settings_service.dart';
import '../../providers/settings_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/settings_shared.dart';

class DnsSettingsScreen extends ConsumerStatefulWidget {
  const DnsSettingsScreen({super.key});

  @override
  ConsumerState<DnsSettingsScreen> createState() => _DnsSettingsScreenState();
}

class _DnsSettingsScreenState extends ConsumerState<DnsSettingsScreen> {
  late String _selectedPreset;
  late DnsType _customType;
  late TextEditingController _customCtrl;
  late DnsMode _dnsMode;
  late DnsQueryStrategy _strategy;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null) ??
        const AppSettings();
    _selectedPreset = s.dnsPreset;
    _customType = s.customDnsType == 'doh'
        ? DnsType.doh
        : s.customDnsType == 'dot'
            ? DnsType.dot
            : DnsType.udp;
    _customCtrl = TextEditingController(text: s.customDnsAddress);
    _dnsMode = s.dnsMode;
    _strategy = s.dnsQueryStrategy;
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final s = ref.read(settingsProvider).maybeWhen(data: (d) => d, orElse: () => null);
    if (s != null) {
      ref.read(settingsProvider.notifier).save(s.copyWith(
            dnsPreset: _selectedPreset,
            customDnsAddress:
                _customCtrl.text.trim().isEmpty ? '1.1.1.1' : _customCtrl.text.trim(),
            customDnsType: _customType.name,
            dnsMode: _dnsMode,
            dnsQueryStrategy: _strategy,
          ));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    final isCustom = _selectedPreset == 'custom';
    final currentLabel = DnsServerConfig.presets
            .firstWhere((p) => p['value'] == _selectedPreset,
                orElse: () => {'label': _selectedPreset})['label'] as String? ??
        _selectedPreset;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Header strip ──────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('teapod.stream // dns',
                      style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                  Text(currentLabel.toLowerCase(),
                      style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                ],
              ),
            ),
            // ── Breadcrumb + save ─────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.lineSoft))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Row(
                      children: [
                        Text('‹', style: AppTheme.mono(size: 12, color: t.textMuted)),
                        const SizedBox(width: 8),
                        Text('config',
                            style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                        const SizedBox(width: 6),
                        Text('/', style: AppTheme.mono(size: 10, color: t.textMuted)),
                        const SizedBox(width: 6),
                        Text('dns',
                            style: AppTheme.mono(size: 10, color: t.text, letterSpacing: 1)),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _save,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      color: t.accent,
                      child: Text('СОХРАНИТЬ',
                          style: AppTheme.mono(size: 10, color: t.bg, letterSpacing: 1)),
                    ),
                  ),
                ],
              ),
            ),
            // ── Hero ──────────────────────────────────────────
            Container(
              width: double.infinity,
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
              child: Stack(
                children: [
                  SetCornerTicks(t: t, color: t.textMuted),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('НАСТРОЙКИ · DNS РЕЗОЛВЕР',
                            style: AppTheme.mono(
                                size: 10, color: t.textMuted, letterSpacing: 1.5)),
                        const SizedBox(height: 8),
                        Text('DNS',
                            style: AppTheme.sans(
                                size: 30,
                                weight: FontWeight.w500,
                                color: t.text,
                                letterSpacing: -1,
                                height: 1)),
                        const SizedBox(height: 6),
                        Text(currentLabel,
                            style: AppTheme.mono(size: 11, color: t.textDim, letterSpacing: 0.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Preset list ───────────────────────────────────
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  SetSectionHeader(t: t, addr: '0x05', label: 'mode'),
                  FeatureGate(
                    feature: CoreFeature.directDns,
                    onReset: _dnsMode != DnsMode.proxy
                        ? () => setState(() => _dnsMode = DnsMode.proxy)
                        : null,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: t.lineSoft)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Режим DNS', style: AppTheme.sans(size: 14, color: t.text)),
                              const SizedBox(height: 3),
                              Text(
                                _dnsMode == DnsMode.proxy ? 'через VPN-туннель' : 'напрямую',
                                style: AppTheme.mono(
                                  size: 10,
                                  color: t.textMuted,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          SetSegSquare(
                            t: t,
                            value: _dnsMode == DnsMode.proxy ? 'proxy' : 'direct',
                            opts: const [('proxy', 'VPN'), ('direct', 'DIRECT')],
                            onChanged: (v) => setState(
                              () => _dnsMode = v == 'proxy' ? DnsMode.proxy : DnsMode.direct,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                    decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: t.lineSoft))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('DNS стратегия',
                                style: AppTheme.sans(size: 14, color: t.text)),
                            const SizedBox(height: 3),
                            Text('IP-версия для DNS-запросов',
                                style: AppTheme.mono(
                                    size: 10, color: t.textMuted, letterSpacing: 0.5)),
                          ],
                        ),
                        SetSegSquare(
                          t: t,
                          value: _strategy.name,
                          opts: const [
                            ('ipv4Only', 'IPv4'),
                            ('ipv6Only', 'IPv6'),
                            ('auto', 'AUTO'),
                          ],
                          onChanged: (v) => setState(() => _strategy =
                              DnsQueryStrategy.values.firstWhere((e) => e.name == v)),
                        ),
                      ],
                    ),
                  ),
                  SetSectionHeader(t: t, addr: '0x10', label: 'preset'),
                  for (final p in DnsServerConfig.presets)
                    _DnsPresetRow(
                      t: t,
                      label: p['label'] as String,
                      value: p['value'] as String,
                      selected: _selectedPreset == p['value'],
                      onTap: () => setState(() => _selectedPreset = p['value'] as String),
                    ),
                  if (isCustom) ...[
                    SetSectionHeader(t: t, addr: '0x20', label: 'custom server'),
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                      decoration:
                          BoxDecoration(border: Border(bottom: BorderSide(color: t.lineSoft))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ТИП ПРОТОКОЛА',
                              style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                          const SizedBox(height: 10),
                          Container(
                            decoration: BoxDecoration(border: Border.all(color: t.line)),
                            child: Row(
                              children: [
                                for (final (type, lab) in [
                                  (DnsType.udp, 'UDP'),
                                  (DnsType.doh, 'DOH'),
                                  (DnsType.dot, 'DOT'),
                                ])
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(() => _customType = type),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        decoration: BoxDecoration(
                                          color: _customType == type
                                              ? t.accentSoft
                                              : Colors.transparent,
                                          border: Border(
                                            right: type != DnsType.dot
                                                ? BorderSide(color: t.line)
                                                : BorderSide.none,
                                          ),
                                        ),
                                        child: Text(lab,
                                            textAlign: TextAlign.center,
                                            style: AppTheme.mono(
                                                size: 11,
                                                color: _customType == type
                                                    ? t.accent
                                                    : t.textDim,
                                                letterSpacing: 1)),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('АДРЕС СЕРВЕРА',
                              style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _customCtrl,
                            style: AppTheme.mono(size: 13, color: t.text),
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: _customType == DnsType.doh
                                  ? 'https://1.1.1.1/dns-query'
                                  : '1.1.1.1',
                              hintStyle: AppTheme.mono(size: 12, color: t.textMuted),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              isDense: true,
                              enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: t.line),
                                  borderRadius: BorderRadius.zero),
                              focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: t.accent),
                                  borderRadius: BorderRadius.zero),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DnsPresetRow extends StatelessWidget {
  final TeapodTokens t;
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  const _DnsPresetRow({
    required this.t,
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.lineSoft))),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                border: Border.all(color: selected ? t.accent : t.line),
                color: selected ? t.accent : Colors.transparent,
              ),
              child: selected ? Icon(Icons.check, size: 12, color: t.bg) : null,
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: AppTheme.sans(size: 14, color: t.text))),
            Text(value,
                style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}
