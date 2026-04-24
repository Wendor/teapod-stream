import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/routing_settings.dart';
import '../../providers/settings_provider.dart';
import '../../providers/vpn_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

String _formatDomainLabel(String zone) {
  if (zone == 'xn--p1ai') return '.рф';
  return zone.split('.').length > 2 ? zone : '.$zone';
}

class RoutingScreen extends ConsumerWidget {
  const RoutingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final isConnected   = ref.watch(vpnProvider).isConnected;

    return Scaffold(
      body: SafeArea(
        child: settingsAsync.when(
          loading: () {
            final t = Theme.of(context).extension<TeapodTokens>()!;
            return Center(child: CircularProgressIndicator(color: t.accent, strokeWidth: 1.5));
          },
          error: (e, _) {
            final t = Theme.of(context).extension<TeapodTokens>()!;
            return Center(child: Text('Ошибка: $e',
                style: AppTheme.mono(size: 12, color: t.danger)));
          },
          data: (settings) => _RoutingBody(
            routing: settings.routing,
            isConnected: isConnected,
            onUpdate: (r) => ref
                .read(settingsProvider.notifier)
                .save(settings.copyWith(routing: r)),
          ),
        ),
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────

class _RoutingBody extends StatelessWidget {
  final RoutingSettings routing;
  final bool isConnected;
  final void Function(RoutingSettings) onUpdate;

  const _RoutingBody({
    required this.routing,
    required this.isConnected,
    required this.onUpdate,
  });

  int get _ruleCount =>
      (routing.geoEnabled ? routing.geoCodes.length : 0) +
      (routing.domainEnabled ? routing.domainZones.length : 0) +
      (routing.geositeEnabled ? routing.geositeCodes.length : 0) +
      (routing.bypassLocal ? 1 : 0) +
      (routing.adBlockEnabled ? 1 : 0);

  String get _modeWord => switch (routing.direction) {
    RoutingDirection.global       => 'FULL',
    RoutingDirection.bypass       => 'BYPASS',
    RoutingDirection.onlySelected => 'ONLY',
  };

  String get _modeHint => switch (routing.direction) {
    RoutingDirection.global       => 'весь трафик через VPN · правила выключены',
    RoutingDirection.bypass       => '$_ruleCount правил · совпавшие напрямую, остальное через VPN',
    RoutingDirection.onlySelected => '$_ruleCount правил · только совпавшие через VPN',
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    final ruleStr = _ruleCount.toString().padLeft(2, '0');
    final locked  = isConnected;

    return Column(
      children: [
        // ── Console header strip ────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('teapod.stream // route',
                  style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
              Text('rules [$ruleStr]',
                  style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
            ],
          ),
        ),
        // ── Breadcrumb back row ─────────────────────────────────
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.lineSoft))),
            child: Row(
              children: [
                Text('‹', style: AppTheme.mono(size: 12, color: t.textMuted)),
                const SizedBox(width: 8),
                Text('settings',
                    style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                const SizedBox(width: 6),
                Text('/', style: AppTheme.mono(size: 10, color: t.textMuted)),
                const SizedBox(width: 6),
                Text('routing',
                    style: AppTheme.mono(size: 10, color: t.text, letterSpacing: 1)),
              ],
            ),
          ),
        ),
        // ── Hero panel ──────────────────────────────────────────
        Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
          child: Stack(
            children: [
              _CornerTicks(t: t),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('МАРШРУТИЗАЦИЯ · SPLIT-TUNNEL',
                              style: AppTheme.mono(
                                  size: 10, color: t.textMuted, letterSpacing: 1.5)),
                          const SizedBox(height: 8),
                          Text(_modeWord,
                              style: AppTheme.sans(
                                  size: 30, weight: FontWeight.w500,
                                  color: t.accent, letterSpacing: -1, height: 1)),
                          const SizedBox(height: 6),
                          Text(_modeHint,
                              style: AppTheme.mono(
                                  size: 11, color: t.textDim, letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Summary square
                    Container(
                      width: 72,
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      decoration: BoxDecoration(
                        color: t.bgElev,
                        border: Border.all(color: t.line),
                      ),
                      child: Stack(
                        children: [
                          // Corner notches
                          Positioned(top: -1, left: -1,
                              child: _NotchTick(color: t.accent, topLeft: true)),
                          Positioned(bottom: -1, right: -1,
                              child: _NotchTick(color: t.accent, topLeft: false)),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('SUMMARY',
                                  style: AppTheme.mono(size: 7, color: t.textMuted, letterSpacing: 1)),
                              const SizedBox(height: 4),
                              Text('$_ruleCount',
                                  style: AppTheme.mono(
                                      size: 22, weight: FontWeight.w500, color: t.text, height: 1.0)),
                              const SizedBox(height: 2),
                              Text('ACTIVE',
                                  style: AppTheme.mono(size: 7, color: t.textDim, letterSpacing: 1)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // ── Scrollable sections ─────────────────────────────────
        Expanded(
          child: Opacity(
            opacity: locked ? 0.6 : 1.0,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // 0x10 MODE
                _SectionHeader(t: t, addr: '0x10', label: 'mode'),
                _ModeSelector(t: t, routing: routing, locked: locked, onUpdate: onUpdate),

                if (routing.isActive) ...[
                  // 0x20 BYPASS
                  _SectionHeader(t: t, addr: '0x20', label: 'bypass'),
                  // LAN
                  _RowToggle(
                    t: t,
                    title: 'Локальные сети',
                    hint: 'Не туннелировать 10/8, 192.168/16',
                    value: routing.bypassLocal,
                    locked: locked,
                    onChange: (v) => onUpdate(routing.copyWith(bypassLocal: v)),
                  ),
                  // GeoIP
                  _ToggleWithChips(
                    t: t,
                    subLabel: 'geoip',
                    count: routing.geoCodes.length,
                    enabled: routing.geoEnabled,
                    locked: locked,
                    onToggle: (v) => onUpdate(routing.copyWith(geoEnabled: v)),
                    chips: routing.geoCodes,
                    onRemove: locked ? null : (code) => onUpdate(routing.copyWith(
                        geoCodes: routing.geoCodes.where((c) => c != code).toList())),
                    onAdd: locked ? null : () => _showCountryPicker(context),
                    addLabel: '+ регион',
                  ),
                  // Domain
                  _ToggleWithChips(
                    t: t,
                    subLabel: 'domain.suffix',
                    count: routing.domainZones.length,
                    enabled: routing.domainEnabled,
                    locked: locked,
                    last: true,
                    onToggle: (v) => onUpdate(routing.copyWith(domainEnabled: v)),
                    chips: routing.domainZones.map(_formatDomainLabel).toList(),
                    chipKeys: routing.domainZones,
                    onRemove: locked ? null : (zone) => onUpdate(routing.copyWith(
                        domainZones: routing.domainZones.where((z) => z != zone).toList())),
                    onAdd: locked ? null : () => _showDomainPicker(context),
                    addLabel: '+ суффикс',
                  ),

                  // 0x30 GEOSITE
                  _SectionHeader(t: t, addr: '0x30', label: 'geosite.sets'),
                  _ToggleWithChips(
                    t: t,
                    subLabel: 'geosite',
                    count: routing.geositeCodes.length,
                    enabled: routing.geositeEnabled,
                    locked: locked,
                    last: true,
                    onToggle: (v) => onUpdate(routing.copyWith(geositeEnabled: v)),
                    chips: routing.geositeCodes,
                    onRemove: locked ? null : (code) => onUpdate(routing.copyWith(
                        geositeCodes: routing.geositeCodes.where((c) => c != code).toList())),
                    onAdd: locked ? null : () => _showGeositePicker(context),
                    addLabel: '+ категория',
                  ),
                ],

                // 0x40 EXTRAS
                _SectionHeader(t: t, addr: '0x40', label: 'extras'),
                _RowToggle(
                  t: t,
                  title: 'Блокировка рекламы',
                  hint: 'geosite:category-ads-all → block',
                  value: routing.adBlockEnabled,
                  locked: locked,
                  last: true,
                  onChange: (v) => onUpdate(routing.copyWith(adBlockEnabled: v)),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Country picker ──────────────────────────────────────────────

  static const _popularCountries = [
    ('RU', 'Россия'), ('BY', 'Беларусь'), ('KZ', 'Казахстан'),
    ('UA', 'Украина'), ('CN', 'Китай'), ('US', 'США'),
    ('DE', 'Германия'), ('GB', 'Великобритания'), ('FR', 'Франция'),
    ('NL', 'Нидерланды'), ('TR', 'Турция'), ('JP', 'Япония'),
    ('SE', 'Швеция'), ('FI', 'Финляндия'), ('PL', 'Польша'),
  ];

  static const _popularGeoipServices = [
    ('cloudflare', 'Cloudflare'), ('cloudfront', 'CloudFront'),
    ('facebook', 'Facebook'), ('fastly', 'Fastly'), ('google', 'Google'),
    ('netflix', 'Netflix'), ('telegram', 'Telegram'), ('twitter', 'Twitter / X'),
  ];

  Future<void> _showCountryPicker(BuildContext context) async {
    final selected  = Set<String>.from(routing.geoCodes);
    final customCtrl = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => DraggableScrollableSheet(
          initialChildSize: 0.7, minChildSize: 0.5, maxChildSize: 0.92,
          expand: false,
          builder: (_, sc) {
            final t = Theme.of(ctx).extension<TeapodTokens>()!;
            return _PickerShell(
              t: t, title: 'GEO IP · РЕГИОНЫ',
              onDone: () {
                onUpdate(routing.copyWith(geoCodes: selected.toList()));
                Navigator.pop(ctx);
              },
              child: ListView(
                controller: sc,
                children: [
                  _PickerSubLabel(t: t, label: 'страны'),
                  for (final (code, name) in _popularCountries)
                    _CheckRow(
                      t: t, title: name, subtitle: code,
                      value: selected.contains(code),
                      onChanged: (v) => ss(() { v ? selected.add(code) : selected.remove(code); }),
                    ),
                  _PickerSubLabel(t: t, label: 'сервисы'),
                  for (final (code, name) in _popularGeoipServices)
                    _CheckRow(
                      t: t, title: name, subtitle: 'geoip:$code',
                      value: selected.contains(code),
                      onChanged: (v) => ss(() { v ? selected.add(code) : selected.remove(code); }),
                    ),
                  _CustomInputRow(
                    t: t, ctrl: customCtrl,
                    hint: 'Код страны (напр. IT)',
                    onAdd: () {
                      final code = customCtrl.text.toUpperCase().trim();
                      if (code.isNotEmpty) { ss(() => selected.add(code)); customCtrl.clear(); }
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
    ('ru', '.ru'), ('xn--p1ai', '.рф'), ('by', '.by'), ('kz', '.kz'),
    ('ua', '.ua'), ('cn', '.cn'), ('com.cn', '.com.cn'),
    ('de', '.de'), ('fr', '.fr'), ('uk', '.uk'),
    ('jp', '.jp'), ('nl', '.nl'), ('pl', '.pl'), ('fi', '.fi'),
  ];

  Future<void> _showDomainPicker(BuildContext context) async {
    final selected     = Set<String>.from(routing.domainZones);
    final popularKeys  = _popularDomains.map((e) => e.$1).toSet();
    final customDomains = Set<String>.from(selected.difference(popularKeys));
    final customCtrl   = TextEditingController();

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
              ss(() { selected.add(zone); customDomains.add(zone); });
              customCtrl.clear();
            }
          }
          return DraggableScrollableSheet(
            initialChildSize: 0.7, minChildSize: 0.5, maxChildSize: 0.92,
            expand: false,
            builder: (_, sc) => _PickerShell(
              t: t, title: 'DOMAIN · СУФФИКСЫ',
              onDone: () {
                onUpdate(routing.copyWith(domainZones: selected.toList()));
                Navigator.pop(ctx);
              },
              child: ListView(
                controller: sc,
                children: [
                  for (final (zone, label) in _popularDomains)
                    _CheckRow(
                      t: t, title: label, subtitle: 'domain:$zone',
                      value: selected.contains(zone),
                      onChanged: (v) => ss(() { v ? selected.add(zone) : selected.remove(zone); }),
                    ),
                  for (final zone in customDomains)
                    _CheckRow(
                      t: t, title: _formatDomainLabel(zone), subtitle: zone,
                      value: true,
                      onChanged: (v) {
                        if (v == false) ss(() { selected.remove(zone); customDomains.remove(zone); });
                      },
                    ),
                  _CustomInputRow(
                    t: t, ctrl: customCtrl,
                    hint: 'Домен или зона (напр. example.com)',
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

  static const _popularGeosite = [
    ('category-ru', 'Россия (категория)'), ('cn', 'Китай'),
    ('google', 'Google'), ('youtube', 'YouTube'), ('telegram', 'Telegram'),
    ('twitter', 'Twitter / X'), ('instagram', 'Instagram'), ('facebook', 'Facebook'),
    ('netflix', 'Netflix'), ('disney', 'Disney+'), ('amazon', 'Amazon / AWS'),
    ('cloudflare', 'Cloudflare'), ('github', 'GitHub'),
    ('openai', 'OpenAI / ChatGPT'), ('apple', 'Apple'),
    ('microsoft', 'Microsoft'), ('tiktok', 'TikTok'),
    ('steam', 'Steam'), ('category-games', 'Игры'),
  ];

  Future<void> _showGeositePicker(BuildContext context) async {
    final selected    = Set<String>.from(routing.geositeCodes);
    final popularKeys = _popularGeosite.map((e) => e.$1).toSet();
    final customCodes = Set<String>.from(selected.difference(popularKeys));
    final customCtrl  = TextEditingController();

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
              ss(() { selected.add(code); customCodes.add(code); });
              customCtrl.clear();
            }
          }
          return DraggableScrollableSheet(
            initialChildSize: 0.7, minChildSize: 0.5, maxChildSize: 0.92,
            expand: false,
            builder: (_, sc) => _PickerShell(
              t: t, title: 'GEOSITE · КАТЕГОРИИ',
              onDone: () {
                onUpdate(routing.copyWith(geositeCodes: selected.toList()));
                Navigator.pop(ctx);
              },
              child: ListView(
                controller: sc,
                children: [
                  for (final (code, name) in _popularGeosite)
                    _CheckRow(
                      t: t, title: name, subtitle: 'geosite:$code',
                      value: selected.contains(code),
                      onChanged: (v) => ss(() { v ? selected.add(code) : selected.remove(code); }),
                    ),
                  for (final code in customCodes)
                    _CheckRow(
                      t: t, title: code, subtitle: 'geosite:$code',
                      value: true,
                      onChanged: (v) {
                        if (v == false) ss(() { selected.remove(code); customCodes.remove(code); });
                      },
                    ),
                  _CustomInputRow(
                    t: t, ctrl: customCtrl,
                    hint: 'Категория (напр. geolocation-!cn)',
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

class _SectionHeader extends StatelessWidget {
  final TeapodTokens t;
  final String addr;
  final String label;
  const _SectionHeader({required this.t, required this.addr, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.lineSoft))),
      child: Row(
        children: [
          Text(addr, style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
          const SizedBox(width: 8),
          Text('·', style: AppTheme.mono(size: 10, color: t.textMuted)),
          const SizedBox(width: 8),
          Text(label.toUpperCase(),
              style: AppTheme.mono(size: 10, color: t.textDim, letterSpacing: 1)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('—' * 16,
                style: AppTheme.mono(size: 10, color: t.textMuted),
                overflow: TextOverflow.clip, maxLines: 1),
          ),
        ],
      ),
    );
  }
}

// ── Mode selector ─────────────────────────────────────────────────

class _ModeSelector extends StatelessWidget {
  final TeapodTokens t;
  final RoutingSettings routing;
  final bool locked;
  final void Function(RoutingSettings) onUpdate;

  const _ModeSelector({
    required this.t, required this.routing,
    required this.locked, required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    const opts = [
      (RoutingDirection.global,       'FULL',   'весь трафик'),
      (RoutingDirection.bypass,       'BYPASS', 'по правилам'),
      (RoutingDirection.onlySelected, 'ONLY',   'только match'),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: t.line)),
        child: Row(
          children: opts.asMap().entries.map((e) {
            final idx   = e.key;
            final (dir, lab, sub) = e.value;
            final active = routing.direction == dir;
            return Expanded(
              child: GestureDetector(
                onTap: locked ? null : () => onUpdate(routing.copyWith(direction: dir)),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                  decoration: BoxDecoration(
                    color: active ? t.accentSoft : Colors.transparent,
                    border: Border(
                      right: idx < opts.length - 1
                          ? BorderSide(color: t.line)
                          : BorderSide.none,
                    ),
                  ),
                  child: Stack(
                    children: [
                      if (active) ...[
                        Positioned(top: -1, left: -1,
                            child: _NotchTick(color: t.accent, topLeft: true)),
                        Positioned(bottom: -1, right: -1,
                            child: _NotchTick(color: t.accent, topLeft: false)),
                      ],
                      Column(
                        children: [
                          Text(lab,
                              style: AppTheme.mono(
                                  size: 12, color: active ? t.accent : t.text,
                                  letterSpacing: 1),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 3),
                          Text(sub,
                              style: AppTheme.mono(size: 9, color: t.textMuted, letterSpacing: 0.5),
                              textAlign: TextAlign.center),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Toggle with chips ─────────────────────────────────────────────

class _ToggleWithChips extends StatelessWidget {
  final TeapodTokens t;
  final String subLabel;
  final int count;
  final bool enabled;
  final bool locked;
  final bool last;
  final void Function(bool) onToggle;
  final List<String> chips;
  final List<String>? chipKeys;
  final void Function(String)? onRemove;
  final VoidCallback? onAdd;
  final String addLabel;

  const _ToggleWithChips({
    required this.t,
    required this.subLabel,
    required this.count,
    required this.enabled,
    required this.locked,
    required this.onToggle,
    required this.chips,
    required this.addLabel,
    this.chipKeys,
    this.onRemove,
    this.onAdd,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: last ? t.line : t.lineSoft))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sublabel + toggle row
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(subLabel.toUpperCase(),
                        style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                    const SizedBox(width: 10),
                    Text('$count',
                        style: AppTheme.mono(size: 10, color: t.textDim)),
                  ],
                ),
                _SquareSwitch(
                  t: t, value: enabled,
                  onChanged: locked ? null : (v) => onToggle(v),
                ),
              ],
            ),
          ),
          if (enabled) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < chips.length; i++)
                    _SquareChip(
                      t: t,
                      label: chips[i],
                      active: true,
                      onTap: onRemove != null
                          ? () => onRemove!(chipKeys != null ? chipKeys![i] : chips[i])
                          : null,
                      showDelete: true,
                    ),
                  if (onAdd != null)
                    _SquareChip(
                      t: t, label: addLabel, ghost: true, onTap: onAdd),
                ],
              ),
            ),
          ] else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Row toggle ────────────────────────────────────────────────────

class _RowToggle extends StatelessWidget {
  final TeapodTokens t;
  final String title;
  final String? hint;
  final bool value;
  final bool locked;
  final bool last;
  final void Function(bool) onChange;

  const _RowToggle({
    required this.t, required this.title, required this.value,
    required this.locked, required this.onChange,
    this.hint, this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: last ? t.line : t.lineSoft))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.sans(size: 14, color: t.text)),
                if (hint != null) ...[
                  const SizedBox(height: 3),
                  Text(hint!,
                      style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 0.5)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 14),
          _SquareSwitch(
            t: t, value: value,
            onChanged: locked ? null : (v) => onChange(v),
          ),
        ],
      ),
    );
  }
}

// ── Square switch ─────────────────────────────────────────────────

class _SquareSwitch extends StatelessWidget {
  final TeapodTokens t;
  final bool value;
  final void Function(bool)? onChanged;
  const _SquareSwitch({required this.t, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged != null ? () => onChanged!(!value) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 44, height: 22,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          border: Border.all(color: value ? t.accent : t.line),
          color: value ? t.accentSoft : Colors.transparent,
        ),
        child: Align(
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 14, height: 14,
            color: value ? t.accent : t.textMuted,
          ),
        ),
      ),
    );
  }
}

// ── Square chip ───────────────────────────────────────────────────

class _SquareChip extends StatelessWidget {
  final TeapodTokens t;
  final String label;
  final bool active;
  final bool ghost;
  final bool showDelete;
  final VoidCallback? onTap;

  const _SquareChip({
    required this.t,
    required this.label,
    this.active = false,
    this.ghost = false,
    this.showDelete = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = active
        ? t.accent
        : ghost
            ? t.line
            : t.line;
    final textColor  = active ? t.accent : ghost ? t.textMuted : t.textDim;
    final bgColor    = active ? t.accentSoft : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bgColor,
          border: ghost
              ? Border.all(color: borderColor, style: BorderStyle.solid, width: 0.5)
              : Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: AppTheme.mono(size: 11, color: textColor, letterSpacing: 0.5)),
            if (showDelete && onTap != null) ...[
              const SizedBox(width: 5),
              Icon(Icons.close, size: 10, color: textColor),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Corner ticks + notch ──────────────────────────────────────────

class _CornerTicks extends StatelessWidget {
  final TeapodTokens t;
  const _CornerTicks({required this.t});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(top: 6, left: 6,   child: _Tick(color: t.textMuted, tl: true)),
            Positioned(top: 6, right: 6,  child: _Tick(color: t.textMuted, tr: true)),
            Positioned(bottom: 6, left: 6,  child: _Tick(color: t.textMuted, bl: true)),
            Positioned(bottom: 6, right: 6, child: _Tick(color: t.textMuted, br: true)),
          ],
        ),
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  final Color color;
  final bool tl, tr, bl, br;
  const _Tick({required this.color, this.tl=false, this.tr=false, this.bl=false, this.br=false});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(8, 8), painter: _TickPainter(color, tl, tr, bl, br));
}

class _TickPainter extends CustomPainter {
  final Color color;
  final bool tl, tr, bl, br;
  const _TickPainter(this.color, this.tl, this.tr, this.bl, this.br);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..strokeWidth = 1..style = PaintingStyle.stroke;
    final w = size.width; final h = size.height;
    if (tl) { canvas.drawLine(Offset.zero, Offset(w, 0), p); canvas.drawLine(Offset.zero, Offset(0, h), p); }
    if (tr) { canvas.drawLine(const Offset(0,0), Offset(w, 0), p); canvas.drawLine(Offset(w,0), Offset(w, h), p); }
    if (bl) { canvas.drawLine(Offset(0,h), Offset(w, h), p); canvas.drawLine(const Offset(0,0), Offset(0, h), p); }
    if (br) { canvas.drawLine(Offset(0,h), Offset(w, h), p); canvas.drawLine(Offset(w,0), Offset(w, h), p); }
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.color != color;
}

class _NotchTick extends StatelessWidget {
  final Color color;
  final bool topLeft;
  const _NotchTick({required this.color, required this.topLeft});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(5, 5), painter: _NotchPainter(color, topLeft));
}

class _NotchPainter extends CustomPainter {
  final Color color;
  final bool topLeft;
  const _NotchPainter(this.color, this.topLeft);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..strokeWidth = 2..style = PaintingStyle.stroke;
    if (topLeft) {
      canvas.drawLine(Offset.zero, Offset(size.width, 0), p);
      canvas.drawLine(Offset.zero, Offset(0, size.height), p);
    } else {
      canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), p);
      canvas.drawLine(Offset(size.width, 0), Offset(size.width, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_NotchPainter old) => old.color != color;
}

// ── Picker bottom sheet shell ─────────────────────────────────────

class _PickerShell extends StatelessWidget {
  final TeapodTokens t;
  final String title;
  final VoidCallback onDone;
  final Widget child;

  const _PickerShell({
    required this.t, required this.title,
    required this.onDone, required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: t.bgElev,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title,
                    style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
                GestureDetector(
                  onTap: onDone,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    color: t.accent,
                    child: Text('ГОТОВО',
                        style: AppTheme.mono(size: 10, color: t.bg, letterSpacing: 1)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _PickerSubLabel extends StatelessWidget {
  final TeapodTokens t;
  final String label;
  const _PickerSubLabel({required this.t, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.lineSoft))),
      child: Text(label.toUpperCase(),
          style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 1)),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final TeapodTokens t;
  final String title;
  final String subtitle;
  final bool value;
  final void Function(bool) onChanged;

  const _CheckRow({
    required this.t, required this.title, required this.subtitle,
    required this.value, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.lineSoft))),
        child: Row(
          children: [
            // Square checkbox
            Container(
              width: 18, height: 18,
              decoration: BoxDecoration(
                border: Border.all(color: value ? t.accent : t.line),
                color: value ? t.accent : Colors.transparent,
              ),
              child: value
                  ? Icon(Icons.check, size: 12, color: t.bg)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTheme.sans(size: 14, color: t.text)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: AppTheme.mono(size: 10, color: t.textMuted, letterSpacing: 0.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomInputRow extends StatelessWidget {
  final TeapodTokens t;
  final TextEditingController ctrl;
  final String hint;
  final VoidCallback onAdd;
  final VoidCallback? onSubmit;

  const _CustomInputRow({
    required this.t, required this.ctrl,
    required this.hint, required this.onAdd, this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              onSubmitted: (_) => (onSubmit ?? onAdd)(),
              style: AppTheme.mono(size: 13, color: t.text),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: AppTheme.mono(size: 12, color: t.textMuted),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: t.line), borderRadius: BorderRadius.zero),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: t.accent), borderRadius: BorderRadius.zero),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 40, height: 40,
              color: t.accent,
              child: Icon(Icons.add, size: 16, color: t.bg),
            ),
          ),
        ],
      ),
    );
  }
}
