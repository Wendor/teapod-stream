enum RoutingDirection { global, bypass, onlySelected }

class RoutingSettings {
  final RoutingDirection direction;
  final bool bypassLocal;
  final bool geoEnabled;
  final List<String> geoCodes;
  final bool domainEnabled;
  final List<String> domainZones;
  final bool geositeEnabled;
  final List<String> geositeCodes;
  final bool adBlockEnabled;
  final bool sitesEnabled;
  final List<String> sites;
  final bool ruServicesEnabled;

  const RoutingSettings({
    this.direction = RoutingDirection.global,
    this.bypassLocal = false,
    this.geoEnabled = false,
    this.geoCodes = const [],
    this.domainEnabled = false,
    this.domainZones = const [],
    this.geositeEnabled = false,
    this.geositeCodes = const [],
    this.adBlockEnabled = false,
    this.sitesEnabled = false,
    this.sites = const [],
    this.ruServicesEnabled = false,
  });

  bool get isActive => direction != RoutingDirection.global;

  RoutingSettings copyWith({
    RoutingDirection? direction,
    bool? bypassLocal,
    bool? geoEnabled,
    List<String>? geoCodes,
    bool? domainEnabled,
    List<String>? domainZones,
    bool? geositeEnabled,
    List<String>? geositeCodes,
    bool? adBlockEnabled,
    bool? sitesEnabled,
    List<String>? sites,
    bool? ruServicesEnabled,
  }) => RoutingSettings(
    direction: direction ?? this.direction,
    bypassLocal: bypassLocal ?? this.bypassLocal,
    geoEnabled: geoEnabled ?? this.geoEnabled,
    geoCodes: geoCodes ?? this.geoCodes,
    domainEnabled: domainEnabled ?? this.domainEnabled,
    domainZones: domainZones ?? this.domainZones,
    geositeEnabled: geositeEnabled ?? this.geositeEnabled,
    geositeCodes: geositeCodes ?? this.geositeCodes,
    adBlockEnabled: adBlockEnabled ?? this.adBlockEnabled,
    sitesEnabled: sitesEnabled ?? this.sitesEnabled,
    sites: sites ?? this.sites,
    ruServicesEnabled: ruServicesEnabled ?? this.ruServicesEnabled,
  );

  Map<String, dynamic> toJson() => {
    'direction': direction.name,
    'bypassLocal': bypassLocal,
    'geoEnabled': geoEnabled,
    'geoCodes': geoCodes,
    'domainEnabled': domainEnabled,
    'domainZones': domainZones,
    'geositeEnabled': geositeEnabled,
    'geositeCodes': geositeCodes,
    'adBlockEnabled': adBlockEnabled,
    'sitesEnabled': sitesEnabled,
    'sites': sites,
    'ruServicesEnabled': ruServicesEnabled,
  };

  static RoutingSettings fromJson(Map<String, dynamic> json) => RoutingSettings(
    direction: RoutingDirection.values.firstWhere(
      (e) => e.name == json['direction'],
      orElse: () => RoutingDirection.global,
    ),
    bypassLocal: json['bypassLocal'] as bool? ?? false,
    geoEnabled: json['geoEnabled'] as bool? ?? false,
    geoCodes: (json['geoCodes'] as List<dynamic>?)?.cast<String>() ?? [],
    domainEnabled: json['domainEnabled'] as bool? ?? false,
    domainZones: (json['domainZones'] as List<dynamic>?)?.cast<String>() ?? [],
    geositeEnabled: json['geositeEnabled'] as bool? ?? false,
    geositeCodes: (json['geositeCodes'] as List<dynamic>?)?.cast<String>() ?? [],
    adBlockEnabled: json['adBlockEnabled'] as bool? ?? false,
    sitesEnabled: json['sitesEnabled'] as bool? ?? false,
    sites: (json['sites'] as List<dynamic>?)?.cast<String>() ?? [],
    ruServicesEnabled: json['ruServicesEnabled'] as bool? ?? false,
  );
}
