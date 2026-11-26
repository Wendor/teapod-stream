import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:path_provider/path_provider.dart';

import '../core/constants/app_constants.dart';
import '../core/models/core_kind.dart';
import '../core/models/app_settings.dart';
import '../core/models/vpn_config.dart';
import '../protocols/xray/vless_parser.dart';
import '../providers/config_provider.dart';
import '../providers/core_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/vpn_provider.dart';
import 'itest_protocol.dart';

/// Integration test agent: executes `tool/itest` runner commands through
/// the same providers as the UI. Present only in the itest build ([kItest]).
class ItestAgent {
  final ProviderContainer container;

  ItestAgent(this.container);

  T read<T>(ProviderListenable<T> provider) => container.read(provider);

  static const _channel = MethodChannel('com.teapodstream/itest');

  /// Flutter on Android cuts a logcat line at ~1024 characters — a long response goes to a file.
  static const _maxInline = 900;

  static void start(ProviderContainer container) {
    final agent = ItestAgent(container);
    // The runner repeats `am start` with the same id if adb hung: the repeat must not
    // run the command (e.g. import) a second time — return the same response.
    final seen = <String, Future<Map<String, Object?>>>{};
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'command') return;
      final cmd = jsonDecode(call.arguments as String) as Map<String, dynamic>;
      final resp = await (seen['${cmd['id']}'] ??= agent.handle(cmd));
      if (seen.length > 64) seen.remove(seen.keys.first);
      final line = itestMarker(resp);
      if (utf8.encode(line).length <= _maxInline) {
        debugPrint(line);
        return;
      }
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/itest_${resp['id']}.json')..writeAsStringSync(jsonEncode(resp));
      debugPrint(itestMarker({'id': resp['id'], 'ok': resp['ok'], 'file': file.path}));
    });
    _channel.invokeMethod('ready');
  }

  Future<Map<String, Object?>> handle(Map<String, dynamic> cmd) async {
    final id = cmd['id'];
    try {
      await read(settingsProvider.future);
      await read(configProvider.future);
      await read(availableCoresProvider.future);
      final data = await switch (cmd['op']) {
        'ping' => _ping(),
        'reset' => _reset(cmd),
        'import' => _import(cmd),
        'list' => _list(),
        'settings' => _settings(cmd['patch'] as Map<String, dynamic>),
        'connect' => _connect(cmd['configId'] as String, cmd['core'] as String),
        'relay' => _relay(cmd['configId'] as String, cmd['port'] as int),
        'disconnect' => read(vpnProvider.notifier).disconnect().then((_) => null),
        'state' => _state(),
        final op => throw ArgumentError('unknown op: $op'),
      };
      return {'id': id, 'ok': true, 'data': ?data};
    } catch (e) {
      return {'id': id, 'ok': false, 'error': e.toString()};
    }
  }

  Future<Object?> _ping() async => {
    'version': AppConstants.appVersion,
    'cores': [for (final k in await read(availableCoresProvider.future)) k.nativeId],
  };

  Future<Object?> _reset(Map<String, dynamic> cmd) async {
    if (cmd['keepConfigs'] != true) {
      final configs = read(configProvider.notifier);
      final cs = read(configProvider).value!;
      for (final s in cs.subscriptions) {
        await configs.removeSubscription(s.id);
      }
      for (final c in cs.standaloneConfigs) {
        await configs.removeConfig(c.id);
      }
    }
    final base = const AppSettings(logsEnabled: true).toJson();
    final patch = (cmd['settings'] as Map<String, dynamic>?) ?? const {};
    await read(settingsProvider.notifier).save(AppSettings.fromJson(deepMerge(base, patch)));
    return null;
  }

  Future<Object?> _import(Map<String, dynamic> cmd) async {
    final parsed = <dynamic>[];
    final failed = <String>[];
    for (final uri in (cmd['uris'] as List? ?? const []).cast<String>()) {
      VpnConfig? c;
      try {
        c = VlessParser.parseUri(uri);
      } on FormatException {
        c = null;
      }
      c == null ? failed.add(Uri.tryParse(uri)?.scheme ?? '?') : parsed.add(c);
    }
    final configs = read(configProvider.notifier);
    if (parsed.isNotEmpty) await configs.addConfigs(parsed.cast());
    final subs = (cmd['subs'] as List? ?? const []).cast<String>();
    for (var i = 0; i < subs.length; i++) {
      try {
        await configs.addSubscriptionFromUrl(subs[i]);
      } catch (e) {
        failed.add('sub#$i: $e');
      }
    }
    return {'imported': parsed.length, 'failed': failed};
  }

  Future<Object?> _list() async {
    final cs = read(configProvider).value!;
    final resolver = read(coreResolverProvider);
    final subNames = {for (final s in cs.subscriptions) s.id: s.name};
    return [
      for (final c in cs.configs)
        {
          'id': c.id,
          'name': c.name,
          'protocol': c.protocol.name,
          if (c.rawXrayConfig != null) 'raw': true,
          'host': c.address,
          'port': c.port,
          'sub': subNames[c.subscriptionId],
          'cores': [
            for (final k in CoreKind.values)
              if (pickCoreError(resolver.resolve(c.copyWith(core: k)), k) == null) k.nativeId,
          ],
        },
    ];
  }

  Future<Object?> _settings(Map<String, dynamic> patch) async {
    final current = read(settingsProvider).value!;
    await read(settingsProvider.notifier).save(AppSettings.fromJson(deepMerge(current.toJson(), patch)));
    return null;
  }

  Future<Object?> _connect(String configId, String core) async {
    final kind = CoreKind.values.firstWhere(
      (k) => k.nativeId == core || k.displayName == core,
      orElse: () => throw ArgumentError('unknown core: $core'),
    );
    final configs = read(configProvider.notifier);
    final config = read(configProvider).value!.configs.firstWhere(
      (c) => c.id == configId,
      orElse: () => throw ArgumentError('unknown config: $configId'),
    );
    final pinned = config.copyWith(core: kind);
    final error = pickCoreError(read(coreResolverProvider).resolve(pinned), kind);
    if (error != null) throw StateError('core ${kind.displayName}: $error');
    await configs.updateConfig(pinned);
    await configs.setActiveSubscription(null);
    await configs.setActiveConfig(configId);
    // Over a live session — the hot switch the server list makes, not a refused connect().
    final vpn = read(vpnProvider.notifier);
    final s = read(vpnProvider);
    await (s.isConnected || s.isConnecting ? vpn.reconnectWithNewConfig() : vpn.connect());
    return null;
  }

  /// A copy of [configId] that dials `127.0.0.1:[port]` — the runner's relay to the real server
  /// (`adb reverse`), which it can cut to make the server dead. The SNI stays the real host.
  Future<Object?> _relay(String configId, int port) async {
    final config = read(configProvider).value!.configs.firstWhere(
      (c) => c.id == configId,
      orElse: () => throw ArgumentError('unknown config: $configId'),
    );
    // A managed config's raw JSON carries its own endpoint: the copy would dial the real server.
    if (config.rawXrayConfig != null) throw ArgumentError('config $configId has a raw xray config');
    final id = '$configId-relay';
    final configs = read(configProvider.notifier);
    if (read(configProvider).value!.configs.any((c) => c.id == id)) await configs.removeConfig(id);
    await configs.addConfig(
      VpnConfig.fromJson({
        ...config.toJson(),
        'id': id,
        'name': '${config.name} (relay)',
        'address': '127.0.0.1',
        'port': port,
        'sni': (config.sni?.isNotEmpty ?? false) ? config.sni : config.address,
        'subscriptionId': null,
      }),
    );
    return {'id': id};
  }

  Future<Object?> _state() async {
    final s = read(vpnProvider);
    return {'state': s.connectionState.name, 'error': ?s.error?.toString()};
  }
}
