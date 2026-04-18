enum RoutingDirection { global, bypass, onlySelected }

class RoutingSettings {
  final RoutingDirection direction;
  final bool bypassLocal;
  final bool geoEnabled;
  final List<String> geoCodes;
  final bool domainEnabled;
  final List<String> domainZones;

  const RoutingSettings({
    this.direction = RoutingDirection.global,
    this.bypassLocal = false,
    this.geoEnabled = false,
    this.geoCodes = const [],
    this.domainEnabled = false,
    this.domainZones = const [],
  });

  bool get isActive => direction != RoutingDirection.global;

  RoutingSettings copyWith({
    RoutingDirection? direction,
    bool? bypassLocal,
    bool? geoEnabled,
    List<String>? geoCodes,
    bool? domainEnabled,
    List<String>? domainZones,
  }) =>
      RoutingSettings(
        direction: direction ?? this.direction,
        bypassLocal: bypassLocal ?? this.bypassLocal,
        geoEnabled: geoEnabled ?? this.geoEnabled,
        geoCodes: geoCodes ?? this.geoCodes,
        domainEnabled: domainEnabled ?? this.domainEnabled,
        domainZones: domainZones ?? this.domainZones,
      );

  String get summary {
    if (direction == RoutingDirection.global) return 'Глобальный';
    final parts = <String>[];
    if (geoEnabled && geoCodes.isNotEmpty) {
      parts.add(geoCodes.take(2).join(', ') + (geoCodes.length > 2 ? '…' : ''));
    }
    if (domainEnabled && domainZones.isNotEmpty) {
      parts.add(domainZones
              .take(2)
              .map((z) => '.${z == 'xn--p1ai' ? 'рф' : z}')
              .join(', ') +
          (domainZones.length > 2 ? '…' : ''));
    }
    if (bypassLocal) parts.add('LAN');
    final prefix = direction == RoutingDirection.bypass ? 'Обход' : 'Только';
    return parts.isEmpty ? prefix : '$prefix: ${parts.join(', ')}';
  }
}
