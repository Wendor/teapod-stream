import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/cores/engine_options.dart';
import 'package:teapodstream/core/models/app_settings.dart';
import 'package:teapodstream/core/models/routing_settings.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/services/geosite_index.dart';
import 'package:teapodstream/protocols/singbox/singbox_backend.dart';
import 'package:teapodstream/protocols/xray/xray_go_backend.dart';

List<int> _varint(int v) => [for (; v >= 0x80; v >>= 7) (v & 0x7f) | 0x80, v];

List<int> _field(int number, List<int> bytes) => [..._varint(number << 3 | 2), ..._varint(bytes.length), ...bytes];

/// A plain `Domain` field of a `GeoSite` body.
Uint8List _domain(String value) =>
    Uint8List.fromList(_field(2, [..._varint(1 << 3), 2, ..._field(2, utf8.encode(value))]));

/// One `GeoSite` record of geosite.dat: the code and the domains.
Uint8List _entry(String code, Iterable<Uint8List> domains) {
  final body = BytesBuilder(copy: false)..add(_field(1, utf8.encode(code)));
  domains.forEach(body.add);
  final bytes = body.takeBytes();
  return (BytesBuilder(copy: false)
        ..add(_varint(1 << 3 | 2))
        ..add(_varint(bytes.length))
        ..add(bytes))
      .takeBytes();
}

Iterable<Uint8List> _domains(int n, {int length = 0}) =>
    Iterable.generate(n, (i) => _domain('d$i.example'.padLeft(length, 'x')));

VpnConfig _config() => VpnConfig(
  id: 'v',
  name: 'v',
  protocol: VpnProtocol.vless,
  address: '1.2.3.4',
  port: 443,
  uuid: '11111111-2222-4333-8444-555555555555',
  security: VpnSecurity.tls,
  transport: VpnTransport.tcp,
  createdAt: DateTime(2026),
  encryption: 'none',
  sni: 's',
);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('geosite'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('indexes codes and domains, keeps an xray-rust copy with the entries over its limits trimmed', () {
    final small = [_entry('YOUTUBE', _domains(3)), _entry('CATEGORY-ADS-ALL', _domains(2))];
    final file =
        (BytesBuilder(copy: false)
              ..add(_entry('WIN-SPY', _domains(1)))
              // Over 200k domains, and over 32 MiB in nine 4 MiB domains.
              ..add(_entry('MANY', _domains(GeositeIndex.rustMaxDomains + 3)))
              ..add(_entry('LONG', _domains(9, length: 4 * 1024 * 1024)))
              ..add(small[0])
              ..add(small[1]))
            .takeBytes();
    File('${dir.path}/geosite.dat').writeAsBytesSync(file);

    final index = GeositeIndex.load(dir.path)!;
    expect(index['youtube'], (domains: 3, rustDomains: 3));
    expect(index['Category-Ads-All@ads'], (domains: 2, rustDomains: 2));
    expect(index['many'], (domains: GeositeIndex.rustMaxDomains + 3, rustDomains: GeositeIndex.rustMaxDomains));
    expect(index['long'], (domains: 9, rustDomains: 7));
    expect(index.rustFile, GeositeIndex.rustFileName);

    // The copy has the same codes, each within the limits, and its first domains.
    final copyDir = Directory('${dir.path}/copy')..createSync();
    File('${dir.path}/${GeositeIndex.rustFileName}').copySync('${copyDir.path}/geosite.dat');
    final copy = GeositeIndex.load(copyDir.path)!;
    expect(copy.entries, {
      for (final MapEntry(:key, :value) in index.entries.entries)
        key: (domains: value.rustDomains, rustDomains: value.rustDomains),
    });
    final copyBytes = File('${copyDir.path}/geosite.dat').readAsBytesSync();
    expect(copyBytes.sublist(copyBytes.length - small[0].length - small[1].length), [...small[0], ...small[1]]);
    expect(copyBytes.length, lessThan(file.length));

    // A second load reads the cache; a new file version rebuilds it. The copy stays, as is when nothing
    // needs trimming: saved quick-connect configs reference it.
    expect(GeositeIndex.load(dir.path)!.entries, index.entries);
    File('${dir.path}/geosite.dat').writeAsBytesSync([...small[0], ...small[1]]);
    final updated = GeositeIndex.load(dir.path)!;
    expect(updated.entries.keys, unorderedEquals(['youtube', 'category-ads-all']));
    expect(updated.rustFile, GeositeIndex.rustFileName);
    expect(File('${dir.path}/${GeositeIndex.rustFileName}').readAsBytesSync(), [...small[0], ...small[1]]);
  });

  test('without geosite.dat there is no index', () {
    expect(GeositeIndex.load(dir.path), isNull);
  });

  test('codes missing from geosite.dat are left out of every core\'s rules', () {
    // v2fly's dlc.dat has no win-spy; a typo'd code is missing everywhere.
    const geosite = GeositeIndex({
      'category-ads-all': (domains: 1, rustDomains: 1),
      'youtube': (domains: 1, rustDomains: 1),
    });
    const settings = AppSettings(
      routing: RoutingSettings(
        direction: RoutingDirection.bypass,
        geositeEnabled: true,
        geositeCodes: ['youtube', 'no-such-code'],
        adBlockEnabled: true,
      ),
    );
    expect(missingGeositeCodes(settings.routing, geosite), ['no-such-code', 'win-spy']);
    expect(missingGeositeCodes(settings.routing, null), isEmpty);
    for (final backend in const [XrayGoBackend(), SingBoxBackend()]) {
      final options = buildEngineOptions(settings, _config(), backend, geosite: geosite);
      expect(options.routing.geositeCodes, ['youtube']);
      expect(options.adBlockCodes, ['category-ads-all']);
      final json = backend.buildConfig(_config(), options);
      expect(json, allOf(contains('youtube'), contains('category-ads-all')));
      expect(json, isNot(anyOf(contains('win-spy'), contains('no-such-code'))));
    }

    final noAds = buildEngineOptions(settings, _config(), const XrayGoBackend(), geosite: const GeositeIndex({}));
    expect(noAds.routing.adBlockEnabled, isFalse);
    expect(noAds.routing.geositeCodes, isEmpty);
    // No geosite rule left: no FakeDNS or forced sniffing for it on xray-rust.
    expect(noAds.routing.geositeEnabled, isFalse);
  });
}
