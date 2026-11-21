import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/services/ip_lookup.dart';

void main() {
  final ipApi = IpLookupSource.ipApi;
  final ipInfo = IpLookupSource.ipInfo;
  final ipify = IpLookupSource.ipify;

  group('parsers', () {
    test('ip-api: success with country, fail without', () {
      final r = ipApi.parse(
        jsonEncode({'status': 'success', 'query': '203.0.113.7', 'country': 'Netherlands', 'countryCode': 'NL'}),
      )!;
      expect((r.ip, r.country, r.countryCode), ('203.0.113.7', 'Netherlands', 'NL'));
      expect(ipApi.parse(jsonEncode({'status': 'fail', 'query': '203.0.113.7'})), isNull);
    });

    test('ipinfo: country code only, upper-cased', () {
      final r = ipInfo.parse(jsonEncode({'ip': '198.51.100.2', 'country': 'de'}))!;
      expect((r.ip, r.country, r.countryCode), ('198.51.100.2', null, 'DE'));
    });

    test('ipify: IP only', () {
      final r = ipify.parse(jsonEncode({'ip': '2001:db8::1'}))!;
      expect((r.ip, r.countryCode), ('2001:db8::1', null));
    });

    test('garbage, an empty IP or a non-object gives null', () {
      for (final s in IpLookupSource.all) {
        expect(s.parse('<html>blocked</html>'), isNull);
        expect(s.parse('[]'), isNull);
        expect(s.parse(jsonEncode({'ip': '', 'query': '', 'status': 'success'})), isNull);
      }
    });

    test('hosts of every service', () {
      expect(IpLookupSource.hosts, ['ip-api.com', 'ipinfo.io', 'api.ipify.org']);
    });
  });

  group('order', () {
    var now = DateTime(2026, 11, 21, 12);
    late IpLookup lookup;
    final asked = <String>[];

    /// Answers with a valid body for hosts in [alive], fails for the rest.
    Future<String> Function(Uri) answer(Set<IpLookupSource> alive) => (url) async {
      asked.add(url.host);
      final s = IpLookupSource.all.singleWhere((s) => s.host == url.host);
      if (!alive.contains(s)) throw Exception('down');
      return s == ipApi ? jsonEncode({'status': 'success', 'query': '1.1.1.1'}) : jsonEncode({'ip': '1.1.1.1'});
    };

    setUp(() {
      now = DateTime(2026, 11, 21, 12);
      lookup = IpLookup(now: () => now);
      asked.clear();
    });

    test('falls through to the next service; the one that answered goes first next time', () async {
      expect((await lookup.lookup('a', answer({ipInfo})))?.ip, '1.1.1.1');
      expect(asked, ['ip-api.com', 'ipinfo.io']);
      expect(lookup.orderFor('a'), [ipInfo, ipify, ipApi]); // ip-api failed: last for an hour

      asked.clear();
      await lookup.lookup('a', answer({ipInfo}));
      expect(asked, ['ipinfo.io']);
    });

    test('a failed service returns to its place after the penalty', () async {
      await lookup.lookup('a', answer({ipInfo}));
      now = now.add(const Duration(minutes: 59));
      expect(lookup.orderFor('a').last, ipApi);
      now = now.add(const Duration(minutes: 2));
      expect(lookup.orderFor('a'), [ipInfo, ipApi, ipify]);
    });

    test('the order is kept per config', () async {
      await lookup.lookup('a', answer({ipify}));
      expect(lookup.orderFor('a').first, ipify);
      expect(lookup.orderFor('b'), IpLookupSource.all);
    });

    test('every service down gives null and all go to the end in their order', () async {
      expect(await lookup.lookup('a', answer({})), isNull);
      expect(asked, ['ip-api.com', 'ipinfo.io', 'api.ipify.org']);
      expect(lookup.orderFor('a'), IpLookupSource.all);
    });
  });

  group('timeouts', () {
    test('a hanging service is skipped after the per-service timeout', () async {
      final lookup = IpLookup(perService: const Duration(milliseconds: 50), total: const Duration(seconds: 5));
      final r = await lookup.lookup('a', (url) {
        if (url.host == 'ip-api.com') return Completer<String>().future; // never answers
        return Future.value(jsonEncode({'ip': '1.1.1.1'}));
      });
      expect(r?.ip, '1.1.1.1');
      expect(lookup.orderFor('a').first, ipInfo);
    });

    test('the whole chain stops at the total timeout', () async {
      final lookup = IpLookup(perService: const Duration(milliseconds: 80), total: const Duration(milliseconds: 120));
      final asked = <String>[];
      final watch = Stopwatch()..start();
      final r = await lookup.lookup('a', (url) {
        asked.add(url.host);
        return Completer<String>().future;
      });
      expect(r, isNull);
      expect(asked, ['ip-api.com', 'ipinfo.io']); // the second gets only what is left of the total
      expect(watch.elapsedMilliseconds, lessThan(1000));
    });
  });
}
