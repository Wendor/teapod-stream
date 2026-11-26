import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/models/app_message.dart';
import 'package:teapodstream/core/models/app_settings.dart';
import 'package:teapodstream/core/models/connections_bundle.dart';
import 'package:teapodstream/core/models/profile.dart';
import 'package:teapodstream/core/models/profile_bundle.dart';
import 'package:teapodstream/core/services/bundle_loader.dart';
import 'package:teapodstream/core/services/deeplink_router.dart';

import '../helpers/local_server.dart';

final _profileBundle = ProfileBundle(
  exportedAt: DateTime(2026),
  profile: Profile(id: 'p', name: 'P', settings: const AppSettings(), createdAt: DateTime(2026)),
  sourceUrl: 'https://origin/profile.json',
);
final _connections = ConnectionsBundle(exportedAt: DateTime(2026), label: 'L');

const _fetchFailed = AppMessage(MessageCode.bundleFetchFailed);

void main() {
  late LocalServer server;
  var socksReads = 0;
  final loader = BundleLoader(() {
    socksReads++;
    return null;
  });
  setUp(() async {
    server = await LocalServer.start();
    socksReads = 0;
  });
  tearDown(() => server.close());

  /// Every request goes to [server], whatever the host and scheme of the URL.
  Future<BundleLoad> run(Future<BundleLoad> Function() body) =>
      HttpOverrides.runWithHttpOverrides(body, RedirectHttpOverrides(server.port));

  AppMessage? reason(BundleLoad l) => l is BundleFailed ? l.reason : null;

  group('load', () {
    test('downloads a profile bundle; the URL is its source', () async {
      server.serve(jsonEncode(_profileBundle.toJson()));
      final l = await run(() => loader.load(DeeplinkParseResult.urlProfile('https://x/p'))) as ProfileLoaded;
      expect(l.bundle.profile.name, 'P');
      expect(l.sourceUrl, 'https://x/p');
      expect(server.paths.single, '/p');
      expect(socksReads, 1);
    });

    test('downloads a connections bundle', () async {
      server.serve(jsonEncode(_connections.toJson()));
      final l = await run(() => loader.load(DeeplinkParseResult.urlConnections('https://x/c')));
      expect((l as ConnectionsLoaded).bundle.label, 'L');
    });

    test('an inline bundle is returned as is, nothing downloaded', () async {
      final p = await loader.load(DeeplinkParseResult.inlineProfile(_profileBundle)) as ProfileLoaded;
      expect(p.sourceUrl, 'https://origin/profile.json');
      expect(await loader.load(DeeplinkParseResult.inlineConnections(_connections)), isA<ConnectionsLoaded>());
      expect(socksReads, 0);
    });

    test('non-200 is a fetch failure; a body that is no bundle is invalid', () async {
      server.serve('', status: 404);
      expect(reason(await run(() => loader.load(DeeplinkParseResult.urlProfile('https://x')))), _fetchFailed);
      server.serve('[1]');
      expect(
        reason(await run(() => loader.load(DeeplinkParseResult.urlProfile('https://x'))))?.code,
        MessageCode.bundleInvalid,
      );
      server.serve('{"profile": 1}');
      expect(
        reason(await run(() => loader.load(DeeplinkParseResult.urlProfile('https://x'))))?.code,
        MessageCode.bundleInvalid,
      );
    });

    test('plain http and a redirect to it are refused', () async {
      server.serve(jsonEncode(_profileBundle.toJson()));
      expect(reason(await run(() => loader.load(DeeplinkParseResult.urlProfile('http://x/p')))), _fetchFailed);
      expect(server.paths, isEmpty);
      server.serve('', status: 302, headers: {'location': 'http://x/p'});
      expect(reason(await run(() => loader.load(DeeplinkParseResult.urlProfile('https://x/start')))), _fetchFailed);
      expect(server.paths, ['/start']);
    });

    test('a bundle over the limit is a fetch failure', () async {
      server.serve('x' * (BundleLoader.maxBundleBytes + 1));
      expect(reason(await run(() => loader.load(DeeplinkParseResult.urlProfile('https://x')))), _fetchFailed);
    });
  });

  group('profileInput', () {
    test('a profile link, inline or by URL', () async {
      final inline = await loader.profileInput('  ${_profileBundle.toDeeplink()} ') as ProfileLoaded;
      expect(inline.bundle.profile.name, 'P');
      server.serve(jsonEncode(_profileBundle.toJson()));
      final fetched =
          await run(() => loader.profileInput('teapod://import/profile?url=https://x/p.json')) as ProfileLoaded;
      expect(fetched.sourceUrl, 'https://x/p.json');
    });

    test('pasted JSON is a bundle without a source URL', () async {
      final l = await loader.profileInput(jsonEncode(_profileBundle.toJson())) as ProfileLoaded;
      expect(l.bundle.profile.name, 'P');
      expect(l.sourceUrl, isNull);
    });

    test('anything else is invalid, with the reason', () async {
      final l = await loader.profileInput('{oops');
      expect(reason(l)?.code, MessageCode.bundleInvalid);
      expect(reason(l)?.arg, isNotEmpty);
      expect(reason(await loader.profileInput(_connections.toCompactDeeplink()))?.code, MessageCode.bundleInvalid);
    });
  });
}
