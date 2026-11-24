import 'dart:convert';

import 'app_settings.dart';

/// Imported settings that change how traffic leaves the device.
enum TrafficSetting { killSwitch, dns, splitTunneling, routing, tethering, ipv6, logLevel }

/// What an import or a profile refresh would change, shown to the user before it is applied: the traffic settings
/// that differ and the hosts of subscriptions it adds (the app fetches them later on its own).
class ImportReview {
  final List<TrafficSetting> changes;
  final List<String> subscriptionHosts;

  const ImportReview({this.changes = const [], this.subscriptionHosts = const []});

  bool get isEmpty => changes.isEmpty && subscriptionHosts.isEmpty;

  /// Hosts of [urls] not among [known] (a subscription already present is not added again).
  static List<String> newHosts(Iterable<String> urls, Iterable<String> known) {
    final skip = known.toSet();
    return {
      for (final url in urls)
        if (!skip.contains(url)) Uri.tryParse(url)?.host.nullIfEmpty ?? url,
    }.toList();
  }

  /// Traffic settings that differ between [a] (in force now) and [b] (what the import applies).
  static List<TrafficSetting> trafficChanges(AppSettings a, AppSettings b) => [
    if (a.killSwitchEnabled != b.killSwitchEnabled) TrafficSetting.killSwitch,
    if (a.dnsMode != b.dnsMode ||
        a.dnsPreset != b.dnsPreset ||
        a.customDnsAddress != b.customDnsAddress ||
        a.customDnsType != b.customDnsType ||
        a.dnsQueryStrategy != b.dnsQueryStrategy)
      TrafficSetting.dns,
    if (a.splitTunnelingEnabled != b.splitTunnelingEnabled ||
        a.vpnMode != b.vpnMode ||
        !_sameSet(a.excludedPackages, b.excludedPackages) ||
        !_sameSet(a.includedPackages, b.includedPackages))
      TrafficSetting.splitTunneling,
    if (jsonEncode(a.routing.toJson()) != jsonEncode(b.routing.toJson())) TrafficSetting.routing,
    if (a.allowTethering != b.allowTethering) TrafficSetting.tethering,
    if (a.ipv6Enabled != b.ipv6Enabled) TrafficSetting.ipv6,
    if (a.logLevel != b.logLevel) TrafficSetting.logLevel,
  ];

  static bool _sameSet(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
