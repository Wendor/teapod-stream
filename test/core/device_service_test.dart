import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/constants/app_constants.dart';
import 'package:teapodstream/core/services/device_service.dart';

const _channel = MethodChannel(AppConstants.methodChannel);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  Object? Function(MethodCall) reply = (_) => null;

  setUp(() async {
    calls.clear();
    reply = (_) => null;
    FlutterSecureStorage.setMockInitialValues({});
    await DeviceService.clearCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call.method);
      return reply(call);
    });
  });

  test('device id is fetched once, then cached in memory and storage', () async {
    reply = (_) => 'dev-1';
    expect(await DeviceService.getDeviceId(), 'dev-1');
    expect(await DeviceService.getDeviceId(), 'dev-1');
    expect(calls, ['getDeviceId']);
    expect(await const FlutterSecureStorage().read(key: 'cached_device_id'), 'dev-1');
  });

  test('stored device id is used without native call', () async {
    FlutterSecureStorage.setMockInitialValues({
      'cached_device_id': 'stored',
      'cached_device_info': '{"model":"Pixel","osVersion":35}',
    });
    expect(await DeviceService.getDeviceId(), 'stored');
    expect((await DeviceService.getDeviceInfo())['model'], 'Pixel');
    expect(calls, isEmpty);
  });

  test('device info falls back when native fails', () async {
    reply = (_) => throw PlatformException(code: 'X');
    expect(await DeviceService.getDeviceId(), '');
    expect(await DeviceService.getDeviceInfo(), {'model': 'Unknown', 'osVersion': 0});
  });

  test('corrupt stored info is refetched', () async {
    FlutterSecureStorage.setMockInitialValues({'cached_device_info': '{bad'});
    reply = (_) => {'model': 'M', 'osVersion': 30};
    expect(await DeviceService.getDeviceInfo(), {'model': 'M', 'osVersion': 30});
    expect(calls, ['getDeviceInfo']);
  });

  test('hwid info combines id and device info', () async {
    reply = (c) => c.method == 'getDeviceId' ? 'id' : {'model': 'X1', 'osVersion': 34};
    final h = (await DeviceService.getHwidInfo())!;
    expect(h.toJson(), {'deviceId': 'id', 'deviceModel': 'X1', 'osVersion': 34});
  });

  test('no device id means no hwid', () async {
    expect(await DeviceService.getHwidInfo(), isNull);
  });

  test('clearCache forgets everything', () async {
    reply = (_) => 'first';
    await DeviceService.getDeviceId();
    await DeviceService.clearCache();
    reply = (_) => 'second';
    expect(await DeviceService.getDeviceId(), 'second');
  });
}
