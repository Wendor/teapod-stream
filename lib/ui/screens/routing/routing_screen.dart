// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/routing_settings.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/geo_provider.dart';
import '../../../core/models/app_settings.dart' show AppSettings, GeoPresets, VpnMode;
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/hero_panel.dart';
import '../../widgets/reconnect_banner.dart';
import '../../widgets/pressable.dart';
import '../../widgets/settings_shared.dart' show SetRowChev, SetSquareSwitch, saveSettings;
import '../split_tunnel_screen.dart';
import '../../../l10n/l10n.dart';

part 'controls.dart';
part 'geo.dart';
part 'picker.dart';

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
            onUpdate: (r) {
              saveSettings(context, ref, settings.copyWith(routing: r));
            },
            onUpdateSniffing: (v) {
              saveSettings(context, ref, settings.copyWith(sniffingEnabled: v));
            },
            onUpdateKillSwitch: (v) {
              saveSettings(context, ref, settings.copyWith(killSwitchEnabled: v));
            },
            onUpdateGeo: (ip, site) => saveSettings(context, ref, settings.copyWith(geoipUrl: ip, geositeUrl: site)),
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
  final void Function(RoutingSettings) onUpdate;
  final void Function(bool) onUpdateSniffing;
  final void Function(bool) onUpdateKillSwitch;
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
    required this.onUpdateSniffing,
    required this.onUpdateKillSwitch,
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
                  onChange: (v) => onUpdate(routing.copyWith(bypassLocal: v)),
                ),
                // GeoIP
                _ToggleWithChips(
                  t: t,
                  subLabel: 'geoip',
                  count: routing.geoCodes.length,
                  enabled: routing.geoEnabled,
                  locked: geoMissing,
                  hint: geoHint,
                  onToggle: (v) => onUpdate(routing.copyWith(geoEnabled: v)),
                  chips: routing.geoCodes,
                  onRemove: geoMissing
                      ? null
                      : (code) =>
                            onUpdate(routing.copyWith(geoCodes: routing.geoCodes.where((c) => c != code).toList())),
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
                  onChange: onUpdateSniffing,
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
                  onToggle: (v) => onUpdate(routing.copyWith(domainEnabled: v)),
                  chips: routing.domainZones.map(_formatDomainLabel).toList(),
                  chipKeys: routing.domainZones,
                  onRemove: domainLocked
                      ? null
                      : (zone) => onUpdate(
                          routing.copyWith(domainZones: routing.domainZones.where((z) => z != zone).toList()),
                        ),
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
                  onToggle: (v) => onUpdate(routing.copyWith(geositeEnabled: v)),
                  chips: routing.geositeCodes,
                  onRemove: geositeLocked
                      ? null
                      : (code) => onUpdate(
                          routing.copyWith(geositeCodes: routing.geositeCodes.where((c) => c != code).toList()),
                        ),
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
                  onToggle: (v) => onUpdate(routing.copyWith(sitesEnabled: v)),
                  chips: routing.sites,
                  onRemove: domainLocked
                      ? null
                      : (site) => onUpdate(routing.copyWith(sites: routing.sites.where((s) => s != site).toList())),
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
                onChange: (v) => onUpdate(routing.copyWith(adBlockEnabled: v)),
              ),
              _RowToggle(
                t: t,
                title: l.routingRuServices,
                hint: l.routingRuServicesHint,
                value: routing.ruServicesEnabled,
                locked: false,
                onChange: (v) => onUpdate(routing.copyWith(ruServicesEnabled: v)),
              ),
              _RowToggle(
                t: t,
                title: 'Kill Switch',
                hint: l.routingKillSwitchHint,
                value: killSwitchEnabled,
                locked: false,
                last: true,
                onChange: onUpdateKillSwitch,
              ),

              // 0x60 GEO.DATA
              _SectionHeader(t: t, addr: '0x60', label: 'geo.data'),
              GestureDetector(
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: t.bgElev,
                  builder: (_) =>
                      _GeoSourceSheet(currentGeoipUrl: geoipUrl, currentGeositeUrl: geositeUrl, onSave: onUpdateGeo),
                ),
                child: Container(
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

  static List<(String, String)> _popularCountries(AppLocalizations l) => [
    ('RU', l.countryRu),
    ('BY', l.countryBy),
    ('KZ', l.countryKz),
    ('UA', l.countryUa),
    ('CN', l.countryCn),
    ('US', l.countryUs),
    ('DE', l.countryDe),
    ('GB', l.countryGb),
    ('FR', l.countryFr),
    ('NL', l.countryNl),
    ('TR', l.countryTr),
    ('JP', l.countryJp),
    ('SE', l.countrySe),
    ('FI', l.countryFi),
    ('PL', l.countryPl),
  ];

  static const _popularGeoipServices = [
    ('cloudflare', 'Cloudflare'),
    ('cloudfront', 'CloudFront'),
    ('facebook', 'Facebook'),
    ('fastly', 'Fastly'),
    ('google', 'Google'),
    ('netflix', 'Netflix'),
    ('telegram', 'Telegram'),
    ('twitter', 'Twitter / X'),
  ];

  Future<void> _showCountryPicker(BuildContext context) async {
    final selected = Set<String>.from(routing.geoCodes);
    final customCtrl = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, sc) {
            final t = Theme.of(ctx).extension<TeapodTokens>()!;
            return _PickerShell(
              t: t,
              title: 'GEO IP · ${ctx.l10n.routingRegions}',
              onDone: () {
                onUpdate(routing.copyWith(geoCodes: selected.toList()));
                Navigator.pop(ctx);
              },
              child: ListView(
                controller: sc,
                children: [
                  _PickerSubLabel(t: t, label: ctx.l10n.routingCountries),
                  for (final (code, name) in _popularCountries(ctx.l10n))
                    _CheckRow(
                      t: t,
                      title: name,
                      subtitle: code,
                      value: selected.contains(code),
                      onChanged: (v) => ss(() {
                        v ? selected.add(code) : selected.remove(code);
                      }),
                    ),
                  _PickerSubLabel(t: t, label: ctx.l10n.routingServices),
                  for (final (code, name) in _popularGeoipServices)
                    _CheckRow(
                      t: t,
                      title: name,
                      subtitle: 'geoip:$code',
                      value: selected.contains(code),
                      onChanged: (v) => ss(() {
                        v ? selected.add(code) : selected.remove(code);
                      }),
                    ),
                  _CustomInputRow(
                    t: t,
                    ctrl: customCtrl,
                    hint: ctx.l10n.routingGeoipCustomHint,
                    onAdd: () {
                      final code = customCtrl.text.trim();
                      if (code.isNotEmpty) {
                        ss(() => selected.add(code.toLowerCase()));
                        customCtrl.clear();
                      }
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    customCtrl.dispose();
  }

  // ── Domain picker ───────────────────────────────────────────────

  static const _popularDomains = [
    ('ru', '.ru'),
    ('xn--p1ai', '.рф'),
    ('by', '.by'),
    ('kz', '.kz'),
    ('ua', '.ua'),
    ('cn', '.cn'),
    ('com.cn', '.com.cn'),
    ('de', '.de'),
    ('fr', '.fr'),
    ('uk', '.uk'),
    ('jp', '.jp'),
    ('nl', '.nl'),
    ('pl', '.pl'),
    ('fi', '.fi'),
  ];

  Future<void> _showDomainPicker(BuildContext context) async {
    final selected = Set<String>.from(routing.domainZones);
    final popularKeys = _popularDomains.map((e) => e.$1).toSet();
    final customDomains = Set<String>.from(selected.difference(popularKeys));
    final customCtrl = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) {
          final t = Theme.of(ctx).extension<TeapodTokens>()!;
          void add() {
            final zone = customCtrl.text.toLowerCase().trim().replaceAll(RegExp(r'^\.+'), '');
            if (zone.isNotEmpty && !selected.contains(zone)) {
              ss(() {
                selected.add(zone);
                customDomains.add(zone);
              });
              customCtrl.clear();
            }
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.5,
            maxChildSize: 0.92,
            expand: false,
            builder: (_, sc) => _PickerShell(
              t: t,
              title: 'DOMAIN · ${ctx.l10n.routingSuffixes}',
              onDone: () {
                onUpdate(routing.copyWith(domainZones: selected.toList()));
                Navigator.pop(ctx);
              },
              child: ListView(
                controller: sc,
                children: [
                  for (final (zone, label) in _popularDomains)
                    _CheckRow(
                      t: t,
                      title: label,
                      subtitle: 'domain:$zone',
                      value: selected.contains(zone),
                      onChanged: (v) => ss(() {
                        v ? selected.add(zone) : selected.remove(zone);
                      }),
                    ),
                  for (final zone in customDomains)
                    _CheckRow(
                      t: t,
                      title: _formatDomainLabel(zone),
                      subtitle: zone,
                      value: true,
                      onChanged: (v) {
                        if (v == false) {
                          ss(() {
                            selected.remove(zone);
                            customDomains.remove(zone);
                          });
                        }
                      },
                    ),
                  _CustomInputRow(
                    t: t,
                    ctrl: customCtrl,
                    hint: ctx.l10n.routingDomainCustomHint,
                    onAdd: add,
                    onSubmit: add,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    customCtrl.dispose();
  }

  // ── Sites picker ────────────────────────────────────────────────

  static const _popularSites = [
    'habr.com',
    'apkmirror.com',
    'github.com',
    'ifconfig.me',
    'checkip.amazonaws.com',
    'myip.ru',
    'myip.com',
    '2ip.ru',
  ];

  Future<void> _showSitesPicker(BuildContext context) async {
    final selected = Set<String>.from(routing.sites);
    final popularKeys = _popularSites.toSet();
    final customSites = Set<String>.from(selected.difference(popularKeys));
    final customCtrl = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) {
          final t = Theme.of(ctx).extension<TeapodTokens>()!;
          void add() {
            final site = customCtrl.text
                .toLowerCase()
                .trim()
                .replaceAll(RegExp(r'^https?://'), '')
                .replaceAll(RegExp(r'/.*'), '');
            if (site.isNotEmpty && !selected.contains(site)) {
              ss(() {
                selected.add(site);
                customSites.add(site);
              });
              customCtrl.clear();
            }
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.5,
            maxChildSize: 0.92,
            expand: false,
            builder: (_, sc) => _PickerShell(
              t: t,
              title: 'SITES · ${ctx.l10n.routingSites}',
              onDone: () {
                onUpdate(routing.copyWith(sites: selected.toList()));
                Navigator.pop(ctx);
              },
              child: ListView(
                controller: sc,
                children: [
                  for (final site in _popularSites)
                    _CheckRow(
                      t: t,
                      title: site,
                      subtitle: 'domain:$site',
                      value: selected.contains(site),
                      onChanged: (v) => ss(() {
                        v ? selected.add(site) : selected.remove(site);
                      }),
                    ),
                  for (final site in customSites)
                    _CheckRow(
                      t: t,
                      title: site,
                      subtitle: 'domain:$site',
                      value: true,
                      onChanged: (v) {
                        if (v == false) {
                          ss(() {
                            selected.remove(site);
                            customSites.remove(site);
                          });
                        }
                      },
                    ),
                  _CustomInputRow(
                    t: t,
                    ctrl: customCtrl,
                    hint: ctx.l10n.routingSiteCustomHint,
                    onAdd: add,
                    onSubmit: add,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    customCtrl.dispose();
  }

  // ── Geosite picker ──────────────────────────────────────────────

  static List<(String, String)> _popularGeosite(AppLocalizations l) => [
    ('category-ru', l.geositeCategoryRu),
    ('category-ip-geo-detect', l.geositeGeoDetect),
    ('apple', 'Apple'),
    ('apple-pki', 'Apple PKI'),
    ('huawei', 'Huawei'),
    ('xiaomi', 'Xiaomi'),
    ('category-android-app-download', 'Android App Download'),
    ('f-droid', 'F-Droid'),
    ('yandex', 'Yandex'),
    ('vk', 'VK'),
    ('microsoft', 'Microsoft'),
    ('win-update', 'Windows Update'),
    ('win-extra', 'Windows Extra'),
    ('google-play', 'Google Play'),
    ('steam', 'Steam'),
    ('cn', l.countryCn),
    ('google', 'Google'),
    ('youtube', 'YouTube'),
    ('telegram', 'Telegram'),
    ('twitter', 'Twitter / X'),
    ('instagram', 'Instagram'),
    ('facebook', 'Facebook'),
    ('netflix', 'Netflix'),
    ('disney', 'Disney+'),
    ('amazon', 'Amazon / AWS'),
    ('cloudflare', 'Cloudflare'),
    ('github', 'GitHub'),
    ('openai', 'OpenAI / ChatGPT'),
    ('tiktok', 'TikTok'),
    ('category-games', l.geositeGames),
  ];

  Future<void> _showGeositePicker(BuildContext context) async {
    final selected = Set<String>.from(routing.geositeCodes);
    final popularKeys = _popularGeosite(context.l10n).map((e) => e.$1).toSet();
    final customCodes = Set<String>.from(selected.difference(popularKeys));
    final customCtrl = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) {
          final t = Theme.of(ctx).extension<TeapodTokens>()!;
          void add() {
            final code = customCtrl.text.toLowerCase().trim();
            if (code.isNotEmpty && !selected.contains(code)) {
              ss(() {
                selected.add(code);
                customCodes.add(code);
              });
              customCtrl.clear();
            }
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.5,
            maxChildSize: 0.92,
            expand: false,
            builder: (_, sc) => _PickerShell(
              t: t,
              title: 'GEOSITE · ${ctx.l10n.routingCategories}',
              onDone: () {
                onUpdate(routing.copyWith(geositeCodes: selected.toList()));
                Navigator.pop(ctx);
              },
              child: ListView(
                controller: sc,
                children: [
                  for (final (code, name) in _popularGeosite(ctx.l10n))
                    _CheckRow(
                      t: t,
                      title: name,
                      subtitle: 'geosite:$code',
                      value: selected.contains(code),
                      onChanged: (v) => ss(() {
                        v ? selected.add(code) : selected.remove(code);
                      }),
                    ),
                  for (final code in customCodes)
                    _CheckRow(
                      t: t,
                      title: code,
                      subtitle: 'geosite:$code',
                      value: true,
                      onChanged: (v) {
                        if (v == false) {
                          ss(() {
                            selected.remove(code);
                            customCodes.remove(code);
                          });
                        }
                      },
                    ),
                  _CustomInputRow(
                    t: t,
                    ctrl: customCtrl,
                    hint: ctx.l10n.routingGeositeCustomHint,
                    onAdd: add,
                    onSubmit: add,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    customCtrl.dispose();
  }
}

// ── Section header ────────────────────────────────────────────────
