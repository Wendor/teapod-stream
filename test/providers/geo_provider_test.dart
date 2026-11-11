import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teapodstream/core/constants/app_constants.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/providers/geo_provider.dart';
import 'package:teapodstream/providers/vpn_provider.dart';

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
    SharedPreferences.setMockInitialValues({'storage_migrated_v2': true});
    FlutterSecureStorage.setMockInitialValues({});
    await SettingsService().save(const AppSettings(geoipUrl: 'https://g/ip.dat', geositeUrl: 'https://g/site.dat'));
    c = ProviderContainer(overrides: [tunnelSocksProvider.overrideWithValue(null)]);
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

  group('check', () {
    test('missing files ask native to extract the bundled copy', () async {
      expect(await start(), isA<GeoMissing>());
      expect(calls, ['getFilesDir', 'prepareBinaries']);
    });

    test('present files are ready with the last update time', () async {
      File('${dir.path}/geoip.dat').writeAsStringSync('ip');
      File('${dir.path}/geosite.dat').writeAsStringSync('site');
      SharedPreferences.setMockInitialValues({'storage_migrated_v2': true, 'geo_last_updated': 1700000000000});
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
    Future<void> download(MockClientHandler handler) async {
      await start();
      await http.runWithClient(() => c.read(geoProvider.notifier).download(), () => MockClient(handler));
    }

    test('downloads both files from the configured URLs', () async {
      final requested = <String>[];
      final states = <GeoState>[];
      c.listen(geoProvider, (_, s) => states.add(s));
      await download((req) async {
        requested.add('${req.method} ${req.url}');
        final body = req.url.path.endsWith('ip.dat') ? 'IPDATA' : 'SITEDATA!';
        return http.Response(req.method == 'HEAD' ? '' : body, 200,
            headers: {'content-length': '${body.length}'});
      });
      expect(requested, [
        'HEAD https://g/ip.dat',
        'HEAD https://g/site.dat',
        'GET https://g/ip.dat',
        'GET https://g/site.dat',
      ]);
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
      await download((req) async => http.Response('', req.method == 'HEAD' ? 200 : 404));
      final s = c.read(geoProvider);
      expect(s, isA<GeoError>());
      expect((s as GeoError).message, 'HTTP 404');
      expect(File('${dir.path}/geoip.dat').readAsStringSync(), 'old');
    });

    test('unknown sizes still download', () async {
      await download((req) async => http.Response(req.method == 'HEAD' ? '' : 'x', 200));
      expect(c.read(geoProvider), isA<GeoReady>());
    });

    test('no files dir is an error', () async {
      filesDir = '';
      await download((_) async => http.Response('', 200));
      expect(c.read(geoProvider), isA<GeoError>());
    });
  });
}
