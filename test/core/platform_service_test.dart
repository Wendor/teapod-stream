import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/constants/app_constants.dart';
import 'package:teapodstream/core/services/platform_service.dart';
import 'package:teapodstream/core/models/core_kind.dart';
import 'package:teapodstream/providers/core_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _channel = MethodChannel(AppConstants.methodChannel);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  Object? Function(MethodCall) reply = (_) => null;

  setUp(() {
    calls.clear();
    reply = (_) => null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return reply(call);
    });
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null),
  );

  const p = PlatformService();

  test('sends the native method names and arguments', () async {
    await p.appIcon('a.b');
    await p.installApk('/f/app.apk');
    await p.prepareBinaries();
    await p.abi();
    await p.deviceId();
    await p.deviceInfo();
    expect(
      [for (final c in calls) c.method],
      ['getAppIcon', 'installApk', 'prepareBinaries', 'getAbi', 'getDeviceId', 'getDeviceInfo'],
    );
    expect(calls[0].arguments, {'packageName': 'a.b'});
    expect(calls[1].arguments, {'filePath': '/f/app.apk'});
  });

  test('typed results, with empty values for a null reply', () async {
    reply = (c) => switch (c.method) {
      'getBinaryVersions' => {'xray': '26', 'tun2socks': 1, 'box': null},
      'getAvailableEngines' => ['go', 'box'],
      'getInstalledApps' => [
        {'packageName': 'a.b', 'appName': 'A', 'isSystem': false},
      ],
      'getFilesDir' => '/data/files',
      _ => null,
    };
    expect(await p.binaryVersions(), {'xray': '26', 'tun2socks': '1'});
    expect(await p.availableEngines(), ['go', 'box']);
    expect(await p.installedApps(), [
      {'packageName': 'a.b', 'appName': 'A', 'isSystem': false},
    ]);
    expect(await p.filesDir(), '/data/files');

    reply = (_) => null;
    expect(await p.binaryVersions(), isEmpty);
    expect(await p.availableEngines(), isEmpty);
    expect(await p.installedApps(), isEmpty);
    expect(await p.filesDir(), '');
  });

  test('channel errors reach the caller', () async {
    reply = (_) => throw PlatformException(code: 'X');
    expect(p.binaryVersions(), throwsA(isA<PlatformException>()));
    expect(p.abi(), throwsA(isA<PlatformException>()));
  });

  test('providers read the service through its provider', () async {
    Future<Set<CoreKind>> cores(Future<List<String>> Function() engines) async {
      final c = ProviderContainer(overrides: [platformServiceProvider.overrideWithValue(_FakePlatform(engines))]);
      addTearDown(c.dispose);
      return c.read(availableCoresProvider.future);
    }

    expect(await cores(() async => ['box', 'rust']), {CoreKind.singBox, CoreKind.xrayRust});
    expect(await cores(() => Future.error(PlatformException(code: 'X'))), {CoreKind.xrayGo});
    expect(calls, isEmpty);
  });
}

class _FakePlatform extends PlatformService {
  _FakePlatform(this.engines);
  final Future<List<String>> Function() engines;

  @override
  Future<List<String>> availableEngines() => engines();
}
