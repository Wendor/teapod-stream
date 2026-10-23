import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teapodstream/core/services/geodata_download.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('teapod-geodata-test-');
    await File('${directory.path}/geodata.active').writeAsString('previous');
  });
  tearDown(() => directory.delete(recursive: true));

  test('activates only after both databases are fully staged', () async {
    var calls = 0;
    await GeodataDownload.install(
      filesDir: directory,
      geoipUrl: 'https://test.invalid/geoip',
      geositeUrl: 'https://test.invalid/geosite',
      onProgress: (_) {},
      client: MockClient(
        (request) async => http.Response(request.url.path, 200),
      ),
      activate: (revision) async {
        expect(
          await File(
            '${directory.path}/geodata/$revision/geoip.dat',
          ).readAsString(),
          '/geoip',
        );
        expect(
          await File(
            '${directory.path}/geodata/$revision/geosite.dat',
          ).readAsString(),
          '/geosite',
        );
        calls++;
      },
    );
    expect(calls, 1);
  });

  test('a failed second download keeps the active pair untouched', () async {
    var activated = false;
    await expectLater(
      GeodataDownload.install(
        filesDir: directory,
        geoipUrl: 'https://test.invalid/geoip',
        geositeUrl: 'https://test.invalid/geosite',
        onProgress: (_) {},
        client: MockClient(
          (request) async =>
              http.Response('data', request.url.path == '/geoip' ? 200 : 503),
        ),
        activate: (_) async {
          activated = true;
        },
      ),
      throwsA(isA<HttpException>()),
    );
    expect(activated, isFalse);
    expect(
      await File('${directory.path}/geodata.active').readAsString(),
      'previous',
    );
    expect(
      await Directory('${directory.path}/geodata').list().toList(),
      isEmpty,
    );
  });

  test('native validation rejection discards the candidate', () async {
    await expectLater(
      GeodataDownload.install(
        filesDir: directory,
        geoipUrl: 'https://test.invalid/geoip',
        geositeUrl: 'https://test.invalid/geosite',
        onProgress: (_) {},
        client: MockClient(
          (_) async => http.Response('<html>broken database</html>', 200),
        ),
        activate: (_) async {
          throw const FormatException('invalid protobuf');
        },
      ),
      throwsFormatException,
    );
    expect(
      await File('${directory.path}/geodata.active').readAsString(),
      'previous',
    );
    expect(
      await Directory('${directory.path}/geodata').list().toList(),
      isEmpty,
    );
  });
}
