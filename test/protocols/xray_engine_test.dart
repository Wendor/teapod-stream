import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/constants/app_constants.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/heartbeat_settings.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/models/vpn_log_entry.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/protocols/xray/xray_engine.dart';
import 'package:teapodstream/protocols/xray/xray_rust_backend.dart';

const _channel = MethodChannel(AppConstants.methodChannel);

VpnConfig _vless({String address = '1.2.3.4', String? ssPrefix}) => VpnConfig(
      id: 'v',
      name: 'v',
      protocol: VpnProtocol.vless,
      address: address,
      port: 443,
      uuid: '11111111-2222-4333-8444-555555555555',
      security: VpnSecurity.tls,
      transport: VpnTransport.tcp,
      createdAt: DateTime(2026),
      ssPrefix: ssPrefix,
    );

const _opts = VpnEngineOptions(
  socksPort: 1080,
  httpPort: 0,
  socksUser: 'u',
  socksPassword: 'p',
  excludedPackages: {'a'},
  includedPackages: {'b'},
  vpnMode: VpnMode.onlySelected,
  killSwitch: true,
  allowIcmp: true,
  blockQuic: true,
  ipv6Enabled: true,
  allowTethering: true,
  mtu: 1400,
  heartbeat: HeartbeatSettings(
      probe: HeartbeatProbe.xrayDelay,
      failAction: HeartbeatFailAction.switchConfig,
      failureThreshold: 4,
      target: HeartbeatTarget.google),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  Object? Function(MethodCall) reply = (_) => null;

  setUp(() {
    calls.clear();
    reply = (_) => null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return reply(call);
    });
  });

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null));

  group('connect', () {
    test('sends the built config and every option', () async {
      final engine = XrayEngine();
      await engine.connect(_vless(ssPrefix: '1603'), _opts);
      final call = calls.single;
      expect(call.method, 'connect');
      final args = Map<String, Object?>.from(call.arguments as Map);
      expect(args['engine'], 'go');
      expect(jsonDecode(args['xrayConfig'] as String), isA<Map<String, dynamic>>());
      expect(args, containsPair('socksPort', 1080));
      expect(args, containsPair('socksUser', 'u'));
      expect(args, containsPair('socksPassword', 'p'));
      expect(args['excludedPackages'], ['a']);
      expect(args['includedPackages'], ['b']);
      expect(args, containsPair('vpnMode', 'onlySelected'));
      expect(args, containsPair('killSwitch', true));
      expect(args, containsPair('allowIcmp', true));
      expect(args, containsPair('blockQuic', true));
      expect(args, containsPair('ipv6Enabled', true));
      expect(args, containsPair('allowTethering', true));
      expect(args, containsPair('mtu', 1400));
      expect(args, containsPair('heartbeatProbe', 'xrayDelay'));
      expect(args, containsPair('heartbeatAction', 'switchConfig'));
      expect(args, containsPair('heartbeatThreshold', 4));
      expect(args, containsPair('heartbeatUrl', HeartbeatTarget.google.url));
      expect(args, containsPair('ssPrefix', '1603'));
    });

    test('rust backend sets engine id', () async {
      final engine = XrayEngine()..backend = const XrayRustBackend();
      await engine.connect(_vless(), _opts);
      final args = calls.single.arguments as Map;
      expect(args['engine'], 'rust');
      expect(args.containsKey('ssPrefix'), isFalse);
      expect(engine.supportsConfig(_vless()), isTrue);
    });

    test('config that cannot be built becomes UNSUPPORTED_CONFIG', () async {
      final bad = VpnConfig.fromJson({..._vless().toJson(), 'rawXrayConfig': '{broken'});
      await expectLater(
        XrayEngine().connect(bad, _opts),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'UNSUPPORTED_CONFIG')),
      );
      expect(calls, isEmpty);
    });

    test('quick-connect save and clear', () async {
      final engine = XrayEngine();
      await engine.saveQuickConnect(_vless(), _opts);
      await engine.clearQuickConnect();
      await engine.disconnect();
      expect(calls.map((c) => c.method), ['saveQuickConnect', 'clearQuickConnect', 'disconnect']);
      expect((calls.first.arguments as Map)['socksPort'], 1080);
    });
  });

  group('ping and measure', () {
    test('ping sends address and port', () async {
      reply = (_) => 42;
      expect(await XrayEngine().pingConfig(_vless()), 42);
      expect(calls.single.arguments, {'address': '1.2.3.4', 'port': 443});
    });

    test('managed or empty address is not pinged', () async {
      expect(await XrayEngine().pingConfig(_vless(address: 'managed')), isNull);
      expect(await XrayEngine().pingConfig(_vless(address: '')), isNull);
      expect(calls, isEmpty);
    });

    test('native errors become null', () async {
      reply = (_) => throw PlatformException(code: 'X');
      expect(await XrayEngine().pingConfig(_vless()), isNull);
      expect(await XrayEngine().measureOutbound(_vless(), _opts, 'http://x'), isNull);
    });

    test('measureOutbound sends a probe config', () async {
      reply = (_) => 120;
      expect(await XrayEngine().measureOutbound(_vless(), _opts, 'http://probe'), 120);
      final args = calls.single.arguments as Map;
      expect(args['engine'], 'go');
      expect(args['url'], 'http://probe');
      expect(jsonDecode(args['config'] as String), isA<Map<String, dynamic>>());
    });
  });

  group('state and stats', () {
    test('getVpnState parses the native map', () async {
      reply = (_) => {
            'state': 'reconnecting',
            'socksPort': 5000,
            'socksUser': 'su',
            'socksPassword': 'sp',
            'connectedAtMs': 1700000000000,
          };
      final s = await XrayEngine().getVpnState();
      expect(s.state, VpnState.connecting);
      expect(s.socksPort, 5000);
      expect(s.socksUser, 'su');
      expect(s.socksPassword, 'sp');
      expect(s.connectedAtMs, 1700000000000);
    });

    test('getVpnState maps every state name', () async {
      const names = {
        'connecting': VpnState.connecting,
        'connected': VpnState.connected,
        'disconnecting': VpnState.disconnecting,
        'disconnected': VpnState.disconnected,
        'error': VpnState.error,
        'blocked': VpnState.blocked,
        'weird': VpnState.disconnected,
      };
      for (final e in names.entries) {
        reply = (_) => {'state': e.key};
        expect((await XrayEngine().getVpnState()).state, e.value, reason: e.key);
      }
    });

    test('getVpnState falls back on errors', () async {
      reply = (_) => throw PlatformException(code: 'X');
      final s = await XrayEngine().getVpnState();
      expect(s.state, VpnState.disconnected);
      expect(s.socksPort, 0);
    });

    test('getStats reads nums and defaults', () async {
      reply = (_) => {'upload': 1, 'download': 2.0, 'uploadSpeed': 3};
      final s = await XrayEngine().getStats();
      expect((s.upload, s.download, s.uploadSpeed, s.downloadSpeed), (1, 2, 3, 0));
      reply = (_) => throw PlatformException(code: 'X');
      expect((await XrayEngine().getStats()).upload, 0);
    });

    test('getStatsHistory passes epoch and since', () async {
      reply = (_) => {'epoch': 1};
      expect(await XrayEngine().getStatsHistory(3, 7), {'epoch': 1});
      expect(calls.single.arguments, {'epoch': 3, 'since': 7});
      reply = (_) => throw PlatformException(code: 'X');
      expect(await XrayEngine().getStatsHistory(0, 0), isNull);
    });
  });

  group('logs and misc', () {
    test('getLogs parses "ts|level|message" and skips junk', () async {
      reply = (_) => [
            '1700000000000|error|boom | with pipe',
            '1700000000001|bogus|m',
            'no pipes',
            'x|info|bad ts',
            42,
          ];
      final logs = await XrayEngine().getLogs();
      expect(logs, hasLength(2));
      expect(logs[0].level, LogLevel.error);
      expect(logs[0].message, 'boom | with pipe');
      expect(logs[0].timestamp, DateTime.fromMillisecondsSinceEpoch(1700000000000));
      expect(logs[0].source, 'xray');
      expect(logs[1].level, LogLevel.info);
    });

    test('getLogs returns empty on null or error', () async {
      expect(await XrayEngine().getLogs(), isEmpty);
      reply = (_) => throw PlatformException(code: 'X');
      expect(await XrayEngine().getLogs(), isEmpty);
    });

    test('simple getters with fallbacks', () async {
      reply = (c) => switch (c.method) {
            'getBinaryVersions' => {'xray': '26', 'tun2socks': '1'},
            'getTunnelDiag' => '{"a":1}',
            'getLogFilePath' => '/f/log.txt',
            _ => null,
          };
      final e = XrayEngine();
      expect(await e.getBinaryVersions(), {'xray': '26', 'tun2socks': '1'});
      expect(await e.getTunnelDiag(), '{"a":1}');
      expect(await e.getLogFilePath(), '/f/log.txt');
      await e.setLogsEnabled(false);
      await e.clearLogs();
      expect(calls.last.method, 'clearLogs');
      expect(calls[calls.length - 2].arguments, {'enabled': false});

      reply = (_) => throw PlatformException(code: 'X');
      expect(await e.getBinaryVersions(), {'xray': '—', 'tun2socks': '—'});
      expect(await e.getTunnelDiag(), '');
      expect(await e.getLogFilePath(), isNull);
      await e.setLogsEnabled(true);
      await e.clearLogs();
    });

    test('generated SOCKS credentials', () {
      final a = XrayEngine.generateSocksCredentials();
      final b = XrayEngine.generateSocksCredentials();
      expect(a.user, matches(RegExp(r'^u[a-zA-Z0-9]{8}$')));
      expect(a.password, matches(RegExp('^[a-zA-Z0-9]{${AppConstants.socksAuthPasswordLength}}\$')));
      expect(a.password, isNot(b.password));
      expect(XrayEngine().protocolName, 'xray');
    });
  });
}
