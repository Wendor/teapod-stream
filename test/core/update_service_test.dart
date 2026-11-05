import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/services/update_service.dart';

import '../helpers/local_server.dart';

Map<String, dynamic> _release(String tag,
        {bool draft = false, String? body = '  notes  ', List<String>? assets}) =>
    {
      'tag_name': tag,
      'draft': draft,
      'body': body,
      'assets': [
        for (final a in assets ??
            ['teapod-stream-arm64-v8a-release-$tag.apk', 'teapod-stream-x86_64-release-$tag.apk'])
          {'name': a, 'browser_download_url': 'https://dl/$a', 'size': 100},
      ],
    };

void main() {
  late LocalServer server;
  final svc = UpdateService();

  setUp(() async => server = await LocalServer.start());
  tearDown(() => server.close());

  group('checkForUpdate', () {
    Future<UpdateInfo?> check(String current,
            {String abi = 'arm64-v8a', UpdateChannel channel = UpdateChannel.stable, bool force = false}) =>
        HttpOverrides.runWithHttpOverrides(
            () => svc.checkForUpdate(current, abi, channel: channel, force: force), RedirectHttpOverrides(server.port));

    test('newer stable release picks the APK for the ABI', () async {
      server.serve(jsonEncode(_release('v1.8.0')));
      final u = (await check('1.7.3', abi: 'x86_64'))!;
      expect(u.version, '1.8.0');
      expect(u.downloadUrl, 'https://dl/teapod-stream-x86_64-release-v1.8.0.apk');
      expect(u.totalBytes, 100);
      expect(u.changelog, 'notes');
      expect(server.paths.single, '/repos/Wendor/teapod-stream/releases/latest');
      expect(server.requests.single.value('accept'), 'application/vnd.github+json');
    });

    test('versions compare numerically', () async {
      server.serve(jsonEncode(_release('v1.10.0')));
      expect(await check('1.9.9'), isNotNull);
      expect(await check('1.10.0'), isNull);
      expect(await check('1.10'), isNull);
      expect(await check('2.0.0'), isNull);
    });

    test('force returns the current release', () async {
      server.serve(jsonEncode(_release('1.7.3', body: '   ')));
      final u = (await check('1.7.3', force: true))!;
      expect(u.version, '1.7.3');
      expect(u.changelog, isNull);
    });

    test('no matching asset, empty tag or error status give null', () async {
      server.serve(jsonEncode(_release('v9.0.0', assets: ['app-arm64-v8a.aab', 'app-x86.apk'])));
      expect(await check('1.0.0'), isNull);
      server.serve(jsonEncode(_release('')));
      expect(await check('1.0.0'), isNull);
      server.serve('{}', status: 403);
      expect(await check('1.0.0'), isNull);
    });

    test('beta takes the newest non-draft release', () async {
      server.serve(jsonEncode([
        _release('v2.0.0', draft: true),
        _release('v1.9.0-beta'),
        _release('v1.8.0'),
      ]));
      final u = (await check('1.7.3', channel: UpdateChannel.beta))!;
      expect(u.version, '1.9.0-beta');
      expect(server.paths.single, '/repos/Wendor/teapod-stream/releases?per_page=10');
    });

    test('beta with only drafts gives null', () async {
      server.serve(jsonEncode([_release('v2.0.0', draft: true)]));
      expect(await check('1.0.0', channel: UpdateChannel.beta), isNull);
    });
  });

  group('downloadApk', () {
    late Directory dir;
    final payload = List<int>.generate(4000, (i) => i % 251);

    setUp(() => dir = Directory.systemTemp.createTempSync('apk'));
    tearDown(() => dir.deleteSync(recursive: true));

    /// Отвечает на Range частичным содержимым, если [honorRange].
    void serveFile({bool honorRange = true}) {
      server.handler = (r) async {
        final range = r.headers.value('range');
        if (range != null && honorRange) {
          final from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
          if (from >= payload.length) {
            r.response.statusCode = 416;
          } else {
            r.response.statusCode = 206;
            r.response.contentLength = payload.length - from;
            r.response.add(payload.sublist(from));
          }
        } else {
          r.response.contentLength = payload.length;
          r.response.add(payload);
        }
        await r.response.close();
      };
    }

    test('fresh download reports progress and writes the file', () async {
      serveFile();
      final path = '${dir.path}/a.apk';
      final events = await svc.downloadApk(server.url('/a.apk'), path).toList();
      expect(events.last.done, isTrue);
      expect(events.last.downloaded, payload.length);
      expect(events.last.total, payload.length);
      expect(events.where((e) => !e.done), isNotEmpty);
      expect(File(path).readAsBytesSync(), payload);
      expect(server.requests.single.value('range'), isNull);
    });

    test('partial file is resumed with Range', () async {
      serveFile();
      final path = '${dir.path}/a.apk';
      File(path).writeAsBytesSync(payload.sublist(0, 1500));
      final events = await svc.downloadApk(server.url(), path).toList();
      expect(server.requests.single.value('range'), 'bytes=1500-');
      expect(events.last.total, payload.length);
      expect(events.last.downloaded, payload.length);
      expect(File(path).readAsBytesSync(), payload);
    });

    test('server ignoring Range restarts the file', () async {
      serveFile(honorRange: false);
      final path = '${dir.path}/a.apk';
      File(path).writeAsBytesSync([9, 9, 9]);
      await svc.downloadApk(server.url(), path).toList();
      expect(File(path).readAsBytesSync(), payload);
    });

    test('416 means the file is already complete', () async {
      serveFile();
      final path = '${dir.path}/a.apk';
      File(path).writeAsBytesSync(payload);
      final events = await svc.downloadApk(server.url(), path).toList();
      expect(events.single.done, isTrue);
      expect(events.single.downloaded, payload.length);
    });

    test('error status throws', () async {
      server.serve('', status: 500);
      expect(svc.downloadApk(server.url(), '${dir.path}/a.apk').toList(),
          throwsA(predicate((e) => e.toString().contains('HTTP 500'))));
    });
  });
}
