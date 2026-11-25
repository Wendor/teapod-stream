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

/// One `GeoSite` record of geosite.dat: the code and [domains] plain domains, padded to [padding] extra bytes.
List<int> _entry(String code, int domains, {int padding = 0}) => _field(1, [
  ..._field(1, utf8.encode(code)),
  for (var i = 0; i < domains; i++) ..._field(2, [..._varint(2 << 3), 2, ..._field(2, utf8.encode('d$i.example'))]),
  if (padding > 0) ..._field(3, Uint8List(padding)),
]);

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

  test('indexes codes and domains, keeps an xray-rust copy without oversized entries', () {
    final huge = _entry('RU-BLOCKED-ALL', 1, padding: GeositeIndex.rustMaxEntryBytes);
    final small = [..._entry('YOUTUBE', 3), ..._entry('CATEGORY-ADS-ALL', 2)];
    File('${dir.path}/geosite.dat').writeAsBytesSync([..._entry('WIN-SPY', 1), ...huge, ...small]);

    final index = GeositeIndex.load(dir.path)!;
    expect(index['youtube']?.domains, 3);
    expect(index['Category-Ads-All@ads']?.domains, 2);
    expect(index.has('ru-blocked-all'), isTrue);
    expect(GeositeIndex.fitsRust(index['ru-blocked-all']!), isFalse);
    expect(index.rustFile, GeositeIndex.rustFileName);
    expect(File('${dir.path}/${GeositeIndex.rustFileName}').readAsBytesSync(), [..._entry('WIN-SPY', 1), ...small]);

    // A second load reads the cache; a new file version rebuilds it and drops the copy no longer needed.
    expect(GeositeIndex.load(dir.path)!.entries.keys, index.entries.keys);
    File('${dir.path}/geosite.dat').writeAsBytesSync(small);
    final updated = GeositeIndex.load(dir.path)!;
    expect(updated.entries.keys, unorderedEquals(['youtube', 'category-ads-all']));
    expect(updated.rustFile, isNull);
    expect(File('${dir.path}/${GeositeIndex.rustFileName}').existsSync(), isFalse);
  });

  test('without geosite.dat there is no index', () {
    expect(GeositeIndex.load(dir.path), isNull);
  });

  test('codes missing from geosite.dat are left out of every core\'s rules', () {
    // v2fly's dlc.dat has no win-spy; a typo'd code is missing everywhere.
    const geosite = GeositeIndex({'category-ads-all': (bytes: 1, domains: 1), 'youtube': (bytes: 1, domains: 1)});
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
  });
}
