import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teapodstream/core/constants/app_constants.dart';
import 'package:teapodstream/core/services/update_service.dart';
import 'package:teapodstream/providers/update_provider.dart';

import '../helpers/local_server.dart';

const _channel = MethodChannel(AppConstants.methodChannel);
const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

Map<String, Object?> _release(String tag) => {
      'tag_name': 'v$tag',
      'body': 'notes',
      'assets': [
        {'name': 'teapod-arm64-v8a-$tag.apk', 'browser_download_url': 'https://dl/app.apk', 'size': 6},
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory support;
  late LocalServer server;
  late ProviderContainer c;
  late String abi;
  Object? Function(MethodCall)? onInstall;

  UpdateNotifier n() => c.read(updateProvider.notifier);
  UpdateState st() => c.read(updateProvider);
  Future<T> redirected<T>(Future<T> Function() body) =>
      HttpOverrides.runWithHttpOverrides(body, RedirectHttpOverrides(server.port));

  setUp(() async {
    abi = 'arm64-v8a';
    onInstall = null;
    support = Directory.systemTemp.createTempSync('support');
    server = await LocalServer.start();
    PackageInfo.setMockInitialValues(
        appName: 'a', packageName: 'p', version: '1.7.3', buildNumber: '1', buildSignature: '');
    messenger.setMockMethodCallHandler(_pathChannel, (call) async => support.path);
    messenger.setMockMethodCallHandler(_channel, (call) async => switch (call.method) {
          'getAbi' => abi,
          'installApk' => onInstall?.call(call),
          'getState' => {'state': 'disconnected'},
          _ => null,
        });
    messenger.setMockStreamHandler(const EventChannel('${AppConstants.methodChannel}/events'),
        MockStreamHandler.inline(onListen: (_, _) {}));
    SharedPreferences.setMockInitialValues({'storage_migrated_v2': true});
    FlutterSecureStorage.setMockInitialValues({});
    c = ProviderContainer();
    c.listen(updateProvider, (_, _) {});
    addTearDown(() async {
      c.dispose();
      await server.close();
      support.deleteSync(recursive: true);
    });
  });

  group('checkForUpdate', () {
    test('unsupported ABI is reported without a network call', () async {
      abi = 'armeabi-v7a';
      await n().checkForUpdate();
      expect((st() as UpdateError).message, contains('armeabi-v7a'));
      expect(server.paths, isEmpty);
    });

    test('newer release is available, old APKs are cleaned, partial one kept', () async {
      server.serve(jsonEncode(_release('1.8.0')));
      final stale = File('${support.path}/teapod-update-arm64-v8a-1.7.0.apk')..writeAsStringSync('x');
      final partial = File('${support.path}/teapod-update-arm64-v8a-1.8.0.apk')..writeAsStringSync('abc');
      final unrelated = File('${support.path}/other.apk')..writeAsStringSync('x');
      await redirected(() => n().checkForUpdate());
      final s = st() as UpdateAvailable;
      expect(s.info.version, '1.8.0');
      expect(s.resumableBytes, 3);
      expect(stale.existsSync(), isFalse);
      expect(partial.existsSync(), isTrue);
      expect(unrelated.existsSync(), isTrue);
    });

    test('same version is up to date', () async {
      server.serve(jsonEncode(_release('1.7.3')));
      await redirected(() => n().checkForUpdate());
      expect((st() as UpdateUpToDate).info.version, '1.7.3');
    });

    test('missing release data is an error', () async {
      server.serve('{}', status: 500);
      await redirected(() => n().checkForUpdate());
      expect((st() as UpdateError).message, 'Не удалось получить данные о релизе');
    });
  });

  group('download and install', () {
    const info = UpdateInfo(version: '1.8.0', downloadUrl: 'https://dl/app.apk', totalBytes: 6);
    String apkPath() => '${support.path}/teapod-update-arm64-v8a-1.8.0.apk';

    Future<void> waitFor(bool Function(UpdateState) done) async {
      for (var i = 0; i < 200 && !done(st()); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    test('download finishes with the file path', () async {
      server.serve('APKAPK');
      await redirected(() async {
        await n().startDownload(info);
        expect(st(), isA<UpdateDownloading>());
        await waitFor((s) => s is! UpdateDownloading);
      });
      final s = st() as UpdateDownloaded;
      expect(s.filePath, apkPath());
      expect(File(apkPath()).readAsStringSync(), 'APKAPK');
      expect(server.paths.single, '/app.apk');
    });

    test('download error keeps retry info', () async {
      server.serve('', status: 503);
      await redirected(() async {
        await n().startDownload(info);
        await waitFor((s) => s is! UpdateDownloading);
      });
      final s = st() as UpdateError;
      expect(s.message, contains('HTTP 503'));
      expect(s.retryInfo?.version, '1.8.0');
    });

    test('reinstall deletes the old file first', () async {
      File(apkPath()).writeAsStringSync('APK');
      server.serve('NEWAPK');
      await redirected(() async {
        await n().reinstall(info);
        await waitFor((s) => s is! UpdateDownloading);
      });
      expect(server.requests.single.value('range'), isNull);
      expect(File(apkPath()).readAsStringSync(), 'NEWAPK');
    });

    test('cancel returns to available with resumable bytes', () async {
      // Данные идут медленно (крупными чанками — мелкие сервер буферизует):
      // отмена async* срабатывает на следующем чанке.
      const chunk = 64 * 1024;
      server.handler = (r) async {
        r.response.contentLength = chunk * 50;
        try {
          for (var i = 0; i < 50; i++) {
            r.response.add(List<int>.filled(chunk, 65));
            await r.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          await r.response.close();
        } on HttpException {
          // Клиент отменил загрузку и закрыл соединение.
        }
      };
      await redirected(() async {
        await n().startDownload(info);
        await waitFor((s) => s is UpdateDownloading && s.downloaded >= chunk);
        await n().cancelDownload();
      });
      final s = st() as UpdateAvailable;
      expect(s.info.version, '1.8.0');
      expect(s.resumableBytes, inExclusiveRange(0, chunk * 50));
      expect(s.resumableBytes, File(apkPath()).lengthSync());
    });

    test('install success cleans other APKs, failure is reported', () async {
      final keep = File(apkPath())..writeAsStringSync('APK');
      final old = File('${support.path}/teapod-update-arm64-v8a-1.0.0.apk')..writeAsStringSync('x');
      await n().installApk(keep.path);
      expect(st(), isA<UpdateIdle>());
      expect(old.existsSync(), isFalse);
      expect(keep.existsSync(), isTrue);

      onInstall = (_) => throw PlatformException(code: 'X', message: 'blocked');
      await n().installApk(keep.path);
      expect((st() as UpdateError).message, 'blocked');
    });
  });
}
