import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teapodstream/core/models/app_message.dart';
import 'package:teapodstream/core/constants/app_constants.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/core/models/app_settings.dart';
import 'package:teapodstream/providers/geo_provider.dart';

import '../helpers/local_server.dart';

const _channel = MethodChannel(AppConstants.methodChannel);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory dir;
  late String? filesDir;
  late ProviderContainer c;
  final calls = <String>[];

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('geo');
    filesDir = dir.path;
    calls.clear();
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call.method);
      return call.method == 'getFilesDir' ? filesDir : null;
    });
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SettingsService().save(const AppSettings(geoipUrl: 'https://g/ip.dat', geositeUrl: 'https://g/site.dat'));
    c = ProviderContainer();
    addTearDown(() {
      c.dispose();
      dir.deleteSync(recursive: true);
    });
  });

  Future<GeoState> start() async {
    c.listen(geoProvider, (_, _) {});
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return c.read(geoProvider);
  }

  test('an unreadable geosite.dat fails the index at once, without retries', () async {
    File('${dir.path}/geosite.dat').writeAsStringSync('not a geosite file');
    await expectLater(
      c.read(geositeIndexProvider.future).timeout(const Duration(seconds: 3)),
      throwsA(isA<FormatException>()),
    );
  });

  group('check', () {
    test('missing files ask native to extract the bundled copy', () async {
      expect(await start(), isA<GeoMissing>());
      expect(calls, ['getFilesDir', 'prepareBinaries']);
    });

    test('present files are ready with the last update time', () async {
      File('${dir.path}/geoip.dat').writeAsStringSync('ip');
      File('${dir.path}/geosite.dat').writeAsStringSync('site');
      SharedPreferences.setMockInitialValues({'geo_last_updated': 1700000000000});
      final s = await start();
      expect(s, isA<GeoReady>());
      expect((s as GeoReady).lastUpdated, DateTime.fromMillisecondsSinceEpoch(1700000000000));
      expect(calls, ['getFilesDir']);
    });

    test('no files dir keeps the initial state', () async {
      filesDir = null;
      expect(await start(), isA<GeoMissing>());
    });
  });

  group('download', () {
    late LocalServer server;
    setUp(() async => server = await LocalServer.start());
    tearDown(() => server.close());

    /// Every request goes to [server].
    Future<void> download() async {
      await start();
      await HttpOverrides.runWithHttpOverrides(
        () => c.read(geoProvider.notifier).download(),
        RedirectHttpOverrides(server.port),
      );
    }

    test('downloads both files from the configured URLs', () async {
      final requested = <String>[];
      final states = <GeoState>[];
      c.listen(geoProvider, (_, s) => states.add(s));
      server.handler = (r) async {
        requested.add('${r.method} ${r.uri}');
        final body = r.uri.path.endsWith('ip.dat') ? 'IPDATA' : 'SITEDATA!';
        r.response.contentLength = body.length;
        if (r.method != 'HEAD') r.response.write(body);
        await r.response.close();
      };
      await download();
      expect(requested, ['HEAD /ip.dat', 'HEAD /site.dat', 'GET /ip.dat', 'GET /site.dat']);
      expect(File('${dir.path}/geoip.dat').readAsStringSync(), 'IPDATA');
      expect(File('${dir.path}/geosite.dat').readAsStringSync(), 'SITEDATA!');
      expect(File('${dir.path}/geoip.dat.tmp').existsSync(), isFalse);
      expect(c.read(geoProvider), isA<GeoReady>());
      final progress = states.whereType<GeoDownloading>().toList();
      expect(progress.last.total, 15);
      expect(progress.last.downloaded, 15);
      expect((await SharedPreferences.getInstance()).getInt('geo_last_updated'), isNotNull);
    });

    test('HTTP error keeps the old file and reports it', () async {
      File('${dir.path}/geoip.dat').writeAsStringSync('old');
      server.handler = (r) async {
        r.response.statusCode = r.method == 'HEAD' ? 200 : 404;
        await r.response.close();
      };
      await download();
      final s = c.read(geoProvider);
      expect(s, isA<GeoError>());
      expect((s as GeoError).message, const AppMessage.text('HTTP 404'));
      expect(File('${dir.path}/geoip.dat').readAsStringSync(), 'old');
    });

    test('files over the default body limit report their size', () async {
      const big = 20 * 1024 * 1024;
      final states = <GeoState>[];
      c.listen(geoProvider, (_, s) => states.add(s));
      server.handler = (r) async {
        if (r.method == 'HEAD') {
          r.response.contentLength = big;
        } else {
          r.response.write('x');
        }
        await r.response.close();
      };
      await download();
      expect(states.whereType<GeoDownloading>().last.total, 2 * big);
      expect(c.read(geoProvider), isA<GeoReady>());
    });

    test('unknown sizes still download', () async {
      server.handler = (r) async {
        if (r.method != 'HEAD') r.response.write('x');
        await r.response.close();
      };
      await download();
      expect(c.read(geoProvider), isA<GeoReady>());
    });

    test('no files dir is an error', () async {
      filesDir = '';
      server.serve('');
      await download();
      expect(c.read(geoProvider), isA<GeoError>());
    });
  });
}
