part of 'routing_screen.dart';

/// The pickers that add rules: countries, domain zones, sites, geosite categories.
extension _RulePickers on _RoutingBody {
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
                onUpdate(SettingFields.geoCodes, (_) => selected.toList());
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
                onUpdate(SettingFields.domainZones, (_) => selected.toList());
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
                onUpdate(SettingFields.sites, (_) => selected.toList());
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
                onUpdate(SettingFields.geositeCodes, (_) => selected.toList());
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
