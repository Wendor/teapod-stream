import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/models/app_settings.dart';
import 'package:teapodstream/core/models/dns_config.dart';
import 'package:teapodstream/core/models/import_review.dart';
import 'package:teapodstream/core/models/routing_settings.dart';
import 'package:teapodstream/core/models/vpn_log_entry.dart';

void main() {
  test('each traffic setting is reported once, in a fixed order', () {
    const base = AppSettings(excludedPackages: {'a', 'b'});
    expect(ImportReview.trafficChanges(base, base.copyWith(excludedPackages: {'b', 'a'}, mtu: 1280)), isEmpty);
    expect(
      ImportReview.trafficChanges(
        base,
        base.copyWith(
          logLevel: LogLevel.debug,
          ipv6Enabled: true,
          allowTethering: true,
          routing: const RoutingSettings(direction: RoutingDirection.bypass),
          includedPackages: {'x'},
          vpnMode: VpnMode.allExcept,
          customDnsAddress: '9.9.9.9',
          dnsMode: DnsMode.direct,
          killSwitchEnabled: true,
        ),
      ),
      TrafficSetting.values,
    );
    expect(ImportReview.trafficChanges(base, base.copyWith(excludedPackages: {'a'})), [TrafficSetting.splitTunneling]);
    expect(ImportReview.trafficChanges(base, base.copyWith(routing: const RoutingSettings(sites: ['x.example']))), [
      TrafficSetting.routing,
    ]);
  });

  test('new subscription hosts: known URLs skipped, hosts deduplicated', () {
    expect(
      ImportReview.newHosts(
        ['https://a.example/1', 'https://a.example/2?t=x', 'https://known.example/s', 'https://b.example:8443/s'],
        ['https://known.example/s'],
      ),
      ['a.example', 'b.example'],
    );
    expect(const ImportReview().isEmpty, isTrue);
    expect(const ImportReview(subscriptionHosts: ['a']).isEmpty, isFalse);
  });
}
