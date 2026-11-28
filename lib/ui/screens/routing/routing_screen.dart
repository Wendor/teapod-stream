// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/routing_settings.dart';
import '../../../core/models/setting_field.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/geo_provider.dart';
import '../../../core/models/app_settings.dart' show AppSettings, GeoPresets, VpnMode;
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/hero_panel.dart';
import '../../widgets/pressable.dart';
import '../../widgets/reconnect_banner.dart';
import '../../widgets/settings_shared.dart'
    show SetRowChev, SetSquareSwitch, SetToggleRow, SettingModify, writeSettings;
import '../../widgets/tap_target.dart';
import '../split_tunnel_screen.dart';
import '../../../l10n/l10n.dart';

part 'controls.dart';
part 'geo.dart';
part 'picker.dart';
part 'rule_pickers.dart';

String _formatDomainLabel(String zone) {
  if (zone == 'xn--p1ai') return '.рф';
  return zone.split('.').length > 2 ? zone : '.$zone';
}

String _splitHint(AppLocalizations l, AppSettings s) {
  if (!s.splitTunnelingEnabled) return l.routingSplitOff;
  return s.vpnMode == VpnMode.onlySelected
      ? l.routingSplitOnly(s.includedPackages.length)
      : l.routingSplitExcept(s.excludedPackages.length);
}

class RoutingScreen extends ConsumerWidget {
  const RoutingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final geoMissing = ref.watch(geoProvider) is GeoMissing;

    return Scaffold(
      body: SafeArea(
        child: settingsAsync.when(
          loading: () {
            final t = Theme.of(context).extension<TeapodTokens>()!;
            return Center(child: CircularProgressIndicator(color: t.accent, strokeWidth: 1.5));
          },
          error: (e, _) {
            final t = Theme.of(context).extension<TeapodTokens>()!;
            return Center(
              child: Text(context.l10n.commonErrorWith('$e'), style: AppTheme.mono(size: 12, color: t.danger)),
            );
          },
          data: (settings) => _RoutingBody(
            routing: settings.routing,
            geoMissing: geoMissing,
            geoipUrl: settings.geoipUrl,
            geositeUrl: settings.geositeUrl,
            sniffingEnabled: settings.sniffingEnabled,
            splitTunnelHint: _splitHint(context.l10n, settings),
            killSwitchEnabled: settings.killSwitchEnabled,
            onUpdate: <T>(SettingField<T> field, T Function(T current) change) =>
                writeSettings(context, ref, (s) => s.modify(field, change)),
            onUpdateGeo: (ip, site) => writeSettings(context, ref, (s) => s.setGeoSources(ip, site)),
          ),
        ),
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────

class _RoutingBody extends StatelessWidget {
  final RoutingSettings routing;
  final bool geoMissing;
  final String geoipUrl;
  final String geositeUrl;
  final bool sniffingEnabled;
  final String splitTunnelHint;
  final bool killSwitchEnabled;

  final SettingModify onUpdate;
  final void Function(String geoipUrl, String geositeUrl) onUpdateGeo;

  const _RoutingBody({
    required this.routing,
    required this.geoMissing,
    required this.geoipUrl,
    required this.geositeUrl,
    required this.sniffingEnabled,
    required this.splitTunnelHint,
    required this.killSwitchEnabled,
    required this.onUpdate,
    required this.onUpdateGeo,
  });

  int get _ruleCount =>
      (routing.geoEnabled ? routing.geoCodes.length : 0) +
      (routing.domainEnabled ? routing.domainZones.length : 0) +
      (routing.geositeEnabled ? routing.geositeCodes.length : 0) +
      (routing.sitesEnabled ? routing.sites.length : 0) +
      (routing.ruServicesEnabled ? 1 : 0) +
      (routing.bypassLocal ? 1 : 0) +
      (routing.adBlockEnabled ? 1 : 0);

  String get _modeWord => switch (routing.direction) {
    RoutingDirection.global => 'FULL',
    RoutingDirection.bypass => 'BYPASS',
    RoutingDirection.onlySelected => 'ONLY',
  };

  String _modeHint(AppLocalizations l) => switch (routing.direction) {
    RoutingDirection.global => l.routingModeGlobalHint,
    RoutingDirection.bypass => l.routingModeBypassHint(_ruleCount),
    RoutingDirection.onlySelected => l.routingModeOnlyHint(_ruleCount),
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    final ruleStr = _ruleCount.toString().padLeft(2, '0');
    final l = context.l10n;
    final geoHint = geoMissing ? l.routingGeoMissingHint : null;
    final sniffHint = l.routingSniffHint;
    final domainLocked = !sniffingEnabled;
    final geositeLocked = geoMissing || !sniffingEnabled;

    return Column(
      children: [
        // ── Console header strip ────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.line)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('teapod.stream // route', style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
              Text('rules [$ruleStr]', style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
            ],
          ),
        ),
        // ── Hero panel ──────────────────────────────────────────
        HeroPanel(
          t: t,
          tagline: l.routingTagline,
          title: _modeWord,
          titleColor: t.accent,
          subtitle: Text(_modeHint(l), style: AppTheme.mono(size: 11, color: t.textDim, letterSpacing: 0.5)),
          trailing: Container(
            width: 88,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: t.bgElev,
              border: Border.all(color: t.line),
            ),
            child: Stack(
              children: [
                Positioned(top: -1, left: -1, child: _NotchTick(color: t.accent, topLeft: true)),
                Positioned(bottom: -1, right: -1, child: _NotchTick(color: t.accent, topLeft: false)),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SUMMARY', style: AppTheme.mono(size: 7, color: t.textMuted, letterSpacing: 1)),
                    const SizedBox(height: 4),
                    Text(
                      '$_ruleCount',
                      style: AppTheme.mono(size: 22, weight: FontWeight.w500, color: t.text, height: 1.0),
                    ),
                    const SizedBox(height: 2),
                    Text('ACTIVE', style: AppTheme.mono(size: 7, color: t.textDim, letterSpacing: 1)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const ReconnectBanner(),
        // ── Scrollable sections ─────────────────────────────────
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // 0x10 APPS
              _SectionHeader(t: t, addr: '0x10', label: 'apps'),
              SetRowChev(
                t: t,
                title: l.routingSplitTunnel,
                hint: splitTunnelHint,
                last: true,
                onTap: () =>
                    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SplitTunnelScreen())),
              ),

              // 0x20 MODE
              _SectionHeader(t: t, addr: '0x20', label: 'mode'),
              _ModeSelector(t: t, routing: routing, locked: false, onUpdate: onUpdate),

              if (routing.isActive) ...[
                // 0x30 BYPASS
                _SectionHeader(t: t, addr: '0x30', label: 'bypass'),
                // LAN
                _RowToggle(
                  t: t,
                  title: l.routingLocalNetworks,
                  hint: l.routingLocalNetworksHint,
                  value: routing.bypassLocal,
                  locked: false,
                  onChange: (v) => onUpdate(SettingFields.bypassLocal, (_) => v),
                ),
                // GeoIP
                _ToggleWithChips(
                  t: t,
                  subLabel: 'geoip',
                  count: routing.geoCodes.length,
                  enabled: routing.geoEnabled,
                  locked: geoMissing,
                  hint: geoHint,
                  onToggle: (v) => onUpdate(SettingFields.geoEnabled, (_) => v),
                  chips: routing.geoCodes,
                  onRemove: geoMissing
                      ? null
                      : (code) => onUpdate(SettingFields.geoCodes, (l) => l.where((c) => c != code).toList()),
                  onAdd: geoMissing ? null : () => _showCountryPicker(context),
                  addLabel: '+ ${l.routingAddRegion}',
                ),
                // Sniffing
                _RowToggle(
                  t: t,
                  title: l.routingSniffing,
                  hint: l.routingSniffingHint,
                  value: sniffingEnabled,
                  locked: false,
                  onChange: (v) => onUpdate(SettingFields.sniffingEnabled, (_) => v),
                ),
                // Domain
                _ToggleWithChips(
                  t: t,
                  subLabel: 'domain.suffix',
                  count: routing.domainZones.length,
                  enabled: routing.domainEnabled,
                  locked: domainLocked,
                  hint: !sniffingEnabled ? sniffHint : null,
                  last: true,
                  onToggle: (v) => onUpdate(SettingFields.domainEnabled, (_) => v),
                  chips: routing.domainZones.map(_formatDomainLabel).toList(),
                  chipKeys: routing.domainZones,
                  onRemove: domainLocked
                      ? null
                      : (zone) => onUpdate(SettingFields.domainZones, (l) => l.where((z) => z != zone).toList()),
                  onAdd: domainLocked ? null : () => _showDomainPicker(context),
                  addLabel: '+ ${l.routingAddSuffix}',
                ),

                // 0x40 GEOSITE
                _SectionHeader(t: t, addr: '0x40', label: 'geosite.sets'),
                _ToggleWithChips(
                  t: t,
                  subLabel: 'geosite',
                  count: routing.geositeCodes.length,
                  enabled: routing.geositeEnabled,
                  locked: geositeLocked,
                  hint: !sniffingEnabled ? sniffHint : geoHint,
                  last: false,
                  onToggle: (v) => onUpdate(SettingFields.geositeEnabled, (_) => v),
                  chips: routing.geositeCodes,
                  onRemove: geositeLocked
                      ? null
                      : (code) => onUpdate(SettingFields.geositeCodes, (l) => l.where((c) => c != code).toList()),
                  onAdd: geositeLocked ? null : () => _showGeositePicker(context),
                  addLabel: '+ ${l.routingAddCategory}',
                ),

                // 0x35 SITES
                _SectionHeader(t: t, addr: '0x45', label: 'sites'),
                _ToggleWithChips(
                  t: t,
                  subLabel: 'sites',
                  count: routing.sites.length,
                  enabled: routing.sitesEnabled,
                  locked: domainLocked,
                  hint: !sniffingEnabled ? sniffHint : null,
                  last: true,
                  onToggle: (v) => onUpdate(SettingFields.sitesEnabled, (_) => v),
                  chips: routing.sites,
                  onRemove: domainLocked
                      ? null
                      : (site) => onUpdate(SettingFields.sites, (l) => l.where((s) => s != site).toList()),
                  onAdd: domainLocked ? null : () => _showSitesPicker(context),
                  addLabel: '+ ${l.routingAddSite}',
                ),
              ],

              // 0x50 EXTRAS
              _SectionHeader(t: t, addr: '0x50', label: 'extras'),
              _RowToggle(
                t: t,
                title: l.routingAdBlock,
                hint: geoHint ?? 'geosite:category-ads-all + geosite:win-spy → block',
                value: routing.adBlockEnabled,
                locked: geoMissing,
                onChange: (v) => onUpdate(SettingFields.adBlockEnabled, (_) => v),
              ),
              _RowToggle(
                t: t,
                title: l.routingRuServices,
                hint: l.routingRuServicesHint,
                value: routing.ruServicesEnabled,
                locked: false,
                onChange: (v) => onUpdate(SettingFields.ruServicesEnabled, (_) => v),
              ),
              _RowToggle(
                t: t,
                title: 'Kill Switch',
                hint: l.routingKillSwitchHint,
                value: killSwitchEnabled,
                locked: false,
                last: true,
                onChange: (v) => onUpdate(SettingFields.killSwitchEnabled, (_) => v),
              ),

              // 0x60 GEO.DATA
              _SectionHeader(t: t, addr: '0x60', label: 'geo.data'),
              Pressable(
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: t.bgElev,
                  builder: (_) =>
                      _GeoSourceSheet(currentGeoipUrl: geoipUrl, currentGeositeUrl: geositeUrl, onSave: onUpdateGeo),
                ),
                child: Container(
                  constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: t.lineSoft)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        context.l10n.routingSource,
                        style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _geoSourceLabel(context, GeoPresets.nameOf(geoipUrl, geositeUrl)),
                        style: AppTheme.mono(size: 10, color: t.textDim),
                      ),
                      const Spacer(),
                      Text('›', style: AppTheme.mono(size: 16, color: t.textMuted)),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: t.line)),
                ),
                child: const _GeoUpdateRow(),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ],
    );
  }

  // ── Country picker ──────────────────────────────────────────────
}
