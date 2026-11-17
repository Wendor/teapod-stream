import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/services/update_service.dart';

import '../helpers/local_server.dart';

Map<String, dynamic> _release(
  String tag, {
  bool draft = false,
  bool prerelease = false,
  String? body = '  notes  ',
  List<String>? assets,
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': prerelease,
  'body': body,
  'assets': [
    for (final a in assets ?? ['teapod-stream-arm64-v8a-release-$tag.apk', 'teapod-stream-x86_64-release-$tag.apk'])
      {'name': a, 'browser_download_url': 'https://dl/$a', 'size': 100},
  ],
};

List<String> _versions(UpdateInfo u) => [for (final n in u.notes) n.version];

void main() {
  late LocalServer server;
  final svc = UpdateService();

  setUp(() async => server = await LocalServer.start());
  tearDown(() => server.close());

  group('checkForUpdate', () {
    Future<UpdateInfo?> check(
      String current, {
      String abi = 'arm64-v8a',
      UpdateChannel channel = UpdateChannel.stable,
      bool force = false,
    }) => HttpOverrides.runWithHttpOverrides(
      () => svc.checkForUpdate(current, abi, channel: channel, force: force),
      RedirectHttpOverrides(server.port),
    );

    test('newer stable release picks the APK for the ABI', () async {
      server.serve(jsonEncode([_release('v1.8.0')]));
      final u = (await check('1.7.3', abi: 'x86_64'))!;
      expect(u.version, '1.8.0');
      expect(u.downloadUrl, 'https://dl/teapod-stream-x86_64-release-v1.8.0.apk');
      expect(u.totalBytes, 100);
      expect(u.notes.single.body, 'notes');
      expect(server.paths.single, '/repos/Wendor/teapod-stream/releases?per_page=30');
      expect(server.requests.single.value('accept'), 'application/vnd.github+json');
    });

    test('versions compare numerically', () async {
      server.serve(jsonEncode([_release('v1.10.0')]));
      expect(await check('1.9.9'), isNotNull);
      expect(await check('1.10.0'), isNull);
      expect(await check('1.10'), isNull);
      expect(await check('2.0.0'), isNull);
    });

    test('force returns the current release with its own notes', () async {
      server.serve(jsonEncode([_release('1.7.3', body: 'current'), _release('1.7.2')]));
      final u = (await check('1.7.3', force: true))!;
      expect(u.version, '1.7.3');
      expect(_versions(u), ['1.7.3']);
      expect(u.notes.single.body, 'current');
    });

    test('empty body gives no notes', () async {
      server.serve(jsonEncode([_release('1.7.3', body: '   ')]));
      expect((await check('1.7.3', force: true))!.notes, isEmpty);
    });

    test('no matching asset, empty tag, no releases or error status give null', () async {
      server.serve(
        jsonEncode([
          _release('v9.0.0', assets: ['app-arm64-v8a.aab', 'app-x86.apk']),
        ]),
      );
      expect(await check('1.0.0'), isNull);
      server.serve(jsonEncode([_release('')]));
      expect(await check('1.0.0'), isNull);
      server.serve(jsonEncode(<Object>[]));
      expect(await check('1.0.0'), isNull);
      server.serve('{}', status: 403);
      expect(await check('1.0.0'), isNull);
    });

    test('an error whose body never ends gives null', () async {
      server.handler = (r) async {
        r.response
          ..statusCode = 403
          ..contentLength = 1000
          ..write('x');
        await r.response.flush();
        await Completer<void>().future; // the body never completes
      };
      expect(await check('1.0.0').timeout(const Duration(seconds: 5)), isNull);
    });

    test('stable skips drafts and prereleases', () async {
      server.serve(
        jsonEncode([_release('v2.0.0', draft: true), _release('v1.9.0', prerelease: true), _release('v1.8.0')]),
      );
      final u = (await check('1.7.3'))!;
      expect(u.version, '1.8.0');
      expect(_versions(u), ['1.8.0']);
    });

    test('stable falls back to the latest release when the page holds prereleases only', () async {
      server.handler = (r) async {
        r.response.write(
          jsonEncode(
            r.uri.path.endsWith('/latest')
                ? _release('v1.8.0')
                : [for (var i = 30; i > 0; i--) _release('v1.9.$i', prerelease: true)],
          ),
        );
        await r.response.close();
      };
      final u = (await check('1.7.3'))!;
      expect(u.version, '1.8.0');
      expect(_versions(u), ['1.8.0']);
      expect(server.paths, [
        '/repos/Wendor/teapod-stream/releases?per_page=30',
        '/repos/Wendor/teapod-stream/releases/latest',
      ]);
    });

    test('a prerelease suffix keeps its number', () async {
      server.serve(jsonEncode([_release('v1.9.2-beta', prerelease: true), _release('v1.9.1'), _release('v1.8.0')]));
      final u = (await check('1.8.0', channel: UpdateChannel.beta))!;
      expect(_versions(u), ['1.9.2-beta', '1.9.1']);
      expect(await check('1.9.2', channel: UpdateChannel.beta), isNull);
    });

    test('beta takes the newest non-draft release', () async {
      server.serve(
        jsonEncode([_release('v2.0.0', draft: true), _release('v1.9.0-beta', prerelease: true), _release('v1.8.0')]),
      );
      final u = (await check('1.7.3', channel: UpdateChannel.beta))!;
      expect(u.version, '1.9.0-beta');
    });

    test('beta with only drafts gives null', () async {
      server.serve(jsonEncode([_release('v2.0.0', draft: true)]));
      expect(await check('1.0.0', channel: UpdateChannel.beta), isNull);
    });

    test('notes of every version after the installed one, highest first', () async {
      server.serve(
        jsonEncode([
          _release('v1.9.0', prerelease: true),
          _release('v1.8.1'),
          _release('v1.8.0', body: ''),
          _release('v1.7.10'),
          _release('v1.7.9', draft: true),
          _release('v1.7.8'),
          _release('v1.7.7'),
        ]),
      );
      expect(_versions((await check('1.7.7'))!), ['1.8.1', '1.7.10', '1.7.8']);
      expect(_versions((await check('1.7.7', channel: UpdateChannel.beta))!), ['1.9.0', '1.8.1', '1.7.10', '1.7.8']);
    });
  });

  group('ReleaseNotes.forLanguage', () {
    const body = '### English\r\n\r\n- one\r\n- two\r\n\r\n### Русский\r\n\r\n- раз\r\n- два\r\n';

    test('takes the section of the language', () {
      expect(const ReleaseNotes('1.8.0', body).forLanguage('ru'), '- раз\n- два');
      expect(const ReleaseNotes('1.8.0', body).forLanguage('en'), '- one\n- two');
    });

    test('falls back to English', () {
      expect(const ReleaseNotes('1.8.0', body).forLanguage('de'), '- one\n- two');
      expect(const ReleaseNotes('1.8.0', '### English\n- one\n### Русский\n').forLanguage('ru'), '- one');
    });

    test('only a language name starts a section', () {
      const notes = ReleaseNotes('1.8.0', '### English\n- one\n### Fixes\n- two\n### Русский\n- раз\n');
      expect(notes.forLanguage('en'), '- one\n### Fixes\n- two');
      expect(notes.forLanguage('ru'), '- раз');
    });

    test('a body without language sections is shown whole', () {
      expect(const ReleaseNotes('1.7.8', ' - старый\n- список \n').forLanguage('en'), '- старый\n- список');
      expect(const ReleaseNotes('1.7.8', '### Other\n- x').forLanguage('ru'), '### Other\n- x');
    });
  });

  group('downloadApk', () {
    late Directory dir;
    final payload = List<int>.generate(4000, (i) => i % 251);

    setUp(() => dir = Directory.systemTemp.createTempSync('apk'));
    tearDown(() => dir.deleteSync(recursive: true));

    /// Answers Range with partial content if [honorRange].
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
      expect(
        svc.downloadApk(server.url(), '${dir.path}/a.apk').toList(),
        throwsA(predicate((e) => e.toString().contains('HTTP 500'))),
      );
    });
  });
}
