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
  }) =>
      RoutingSettings(
        direction: direction ?? this.direction,
        bypassLocal: bypassLocal ?? this.bypassLocal,
        geoEnabled: geoEnabled ?? this.geoEnabled,
        geoCodes: geoCodes ?? this.geoCodes,
        domainEnabled: domainEnabled ?? this.domainEnabled,
        domainZones: domainZones ?? this.domainZones,
        geositeEnabled: geositeEnabled ?? this.geositeEnabled,
        geositeCodes: geositeCodes ?? this.geositeCodes,
        adBlockEnabled: adBlockEnabled ?? this.adBlockEnabled,
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
  );

  String get summary {
    if (direction == RoutingDirection.global && !adBlockEnabled) return 'Глобальный';
    final parts = <String>[];
    if (geoEnabled && geoCodes.isNotEmpty) {
      parts.add(geoCodes.take(2).join(', ') + (geoCodes.length > 2 ? '…' : ''));
    }
    if (domainEnabled && domainZones.isNotEmpty) {
      parts.add(domainZones
              .take(2)
              .map((z) {
                if (z == 'xn--p1ai') return '.рф';
                return z.split('.').length > 2 ? z : '.$z';
              })
              .join(', ') +
          (domainZones.length > 2 ? '…' : ''));
    }
    if (geositeEnabled && geositeCodes.isNotEmpty) {
      parts.add('geosite:${geositeCodes.length}');
    }
    if (bypassLocal) parts.add('LAN');
    if (adBlockEnabled) parts.add('Ads✗');
    if (direction == RoutingDirection.global) return parts.join(', ');
    final prefix = direction == RoutingDirection.bypass ? 'Обход' : 'Только';
    return parts.isEmpty ? prefix : '$prefix: ${parts.join(', ')}';
  }
}
