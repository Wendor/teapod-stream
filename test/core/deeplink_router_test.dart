import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teapodstream/core/models/connections_bundle.dart';
import 'package:teapodstream/core/models/profile.dart';
import 'package:teapodstream/core/models/profile_bundle.dart';
import 'package:teapodstream/core/services/deeplink_router.dart';
import 'package:teapodstream/core/services/settings_service.dart';

final _profileBundle = ProfileBundle(
  exportedAt: DateTime(2026),
  profile: Profile(id: 'p', name: 'P', settings: const AppSettings(), createdAt: DateTime(2026)),
  sourceUrl: 'https://origin/profile.json',
);
final _connections = ConnectionsBundle(exportedAt: DateTime(2026), label: 'L');

void main() {
  group('DeeplinkRouter.parse', () {
    test('inline profile', () {
      final r = DeeplinkRouter.parse('  ${_profileBundle.toDeeplink()}  ')!;
      expect(r.type, DeeplinkType.profile);
      expect(r.source, DeeplinkSource.data);
      expect(r.profileBundle!.profile.name, 'P');
      expect(r.urlValue, isNull);
      expect(r.effectiveSourceUrl, 'https://origin/profile.json');
    });

    test('inline connections', () {
      final r = DeeplinkRouter.parse(_connections.toCompactDeeplink())!;
      expect(r.type, DeeplinkType.connections);
      expect(r.connectionsBundle!.label, 'L');
      expect(r.effectiveSourceUrl, isNull);
    });

    test('url sources, type is case-insensitive', () {
      final p = DeeplinkRouter.parse('teapod://import/Profile?url=https%3A%2F%2Fx%2Fp.json')!;
      expect(p.source, DeeplinkSource.url);
      expect(p.urlValue, 'https://x/p.json');
      expect(p.effectiveSourceUrl, 'https://x/p.json');
      final c = DeeplinkRouter.parse('teapod://import/connections?url=https://x/c.json')!;
      expect(c.type, DeeplinkType.connections);
      expect(c.urlValue, 'https://x/c.json');
    });

    test('data wins over url', () {
      final r = DeeplinkRouter.parse(
          'teapod://import/profile?url=https://x&data=${_profileBundle.toBase64()}')!;
      expect(r.source, DeeplinkSource.data);
    });

    test('invalid links return null', () {
      for (final link in [
        'https://import/profile?data=x',
        'teapod://export/profile?url=https://x',
        'teapod://import/unknown?url=https://x',
        'teapod://import/profile',
        'teapod://import/profile?data=!!!notbase64',
        'teapod://import/connections?data=${base64Url.encode(utf8.encode('[]'))}',
        'teapod://import',
        '',
      ]) {
        expect(DeeplinkRouter.parse(link), isNull, reason: link);
      }
    });
  });

  group('DeeplinkRouter.fetchFromUrl', () {
    Future<Object?> fetch(DeeplinkParseResult r, MockClientHandler h) =>
        http.runWithClient(() => DeeplinkRouter.fetchFromUrl(r), () => MockClient(h));

    test('fetches a profile bundle', () async {
      final b = await fetch(DeeplinkParseResult.urlProfile('https://x/p'),
          (req) async => http.Response(jsonEncode(_profileBundle.toJson()), 200));
      expect((b as ProfileBundle).profile.name, 'P');
    });

    test('fetches a connections bundle', () async {
      final b = await fetch(DeeplinkParseResult.urlConnections('https://x/c'),
          (req) async => http.Response(jsonEncode(_connections.toJson()), 200));
      expect((b as ConnectionsBundle).label, 'L');
    });

    test('non-200, bad json and inline results give null', () async {
      expect(await fetch(DeeplinkParseResult.urlProfile('https://x'),
          (_) async => http.Response('', 404)), isNull);
      expect(await fetch(DeeplinkParseResult.urlProfile('https://x'),
          (_) async => http.Response('[1]', 200)), isNull);
      expect(await fetch(DeeplinkParseResult.urlConnections('https://x'),
          (_) async => throw http.ClientException('offline')), isNull);
      expect(await DeeplinkRouter.fetchFromUrl(DeeplinkParseResult.inlineProfile(_profileBundle)),
          isNull);
    });
  });
}
