import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/models/core_kind.dart';
import 'package:teapodstream/itest/itest_agent.dart';
import 'package:teapodstream/providers/config_provider.dart';
import 'package:teapodstream/providers/settings_provider.dart';

import '../helpers/ui_harness.dart';

const _vless = 'vless://11111111-2222-3333-4444-555555555555@v.example:443?security=tls&type=tcp#V1';
const _hy2 = 'hysteria2://secretpass@h.example:8443?sni=h.example#H1';
const _ssh = 'ssh://user:sshpass@s.example:22#S1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNative native;
  late ProviderContainer container;
  late ItestAgent agent;

  setUp(() async {
    native = await setUpScreenTest();
    container = ProviderContainer();
    agent = ItestAgent(container);
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    container.dispose();
  });

  test('import + list exposes configs without secrets', () async {
    final imp = await agent.handle({'id': '1', 'op': 'import', 'uris': [_vless, _hy2, 'garbage://x']});
    expect(imp['ok'], isTrue);
    expect((imp['data'] as Map)['imported'], 2);
    expect((imp['data'] as Map)['failed'], ['garbage']);

    final list = await agent.handle({'id': '2', 'op': 'list'});
    final rows = (list['data'] as List).cast<Map>();
    expect(rows.map((r) => r['name']), containsAll(['V1', 'H1']));
    final v1 = rows.firstWhere((r) => r['name'] == 'V1');
    expect(v1['host'], 'v.example');
    expect(v1['port'], 443);
    expect(v1['cores'], contains('go'));
    expect(list.toString(), isNot(contains('11111111')));
    expect(list.toString(), isNot(contains('secretpass')));
  });

  test('connect refuses a core that cannot run the profile', () async {
    await agent.handle({'id': '1', 'op': 'import', 'uris': [_ssh]});
    final id = ((await agent.handle({'id': '2', 'op': 'list'}))['data'] as List).first['id'];
    final r = await agent.handle({'id': '3', 'op': 'connect', 'configId': id, 'core': 'go'});
    expect(r['ok'], isFalse);
    expect(native.named('connect'), isEmpty);
  });

  test('connect pins the core, activates the profile and calls native connect', () async {
    await agent.handle({'id': '1', 'op': 'import', 'uris': [_vless, _hy2]});
    final rows = ((await agent.handle({'id': '2', 'op': 'list'}))['data'] as List).cast<Map>();
    final id = rows.firstWhere((r) => r['name'] == 'H1')['id'] as String;
    final r = await agent.handle({'id': '3', 'op': 'connect', 'configId': id, 'core': 'box'});
    expect(r['ok'], isTrue, reason: '$r');
    final state = container.read(configProvider).value!;
    expect(state.activeConfigId, id);
    expect(state.activeSubscriptionId, isNull);
    expect(state.activeConfig!.core, CoreKind.singBox);
    expect(native.named('connect'), hasLength(1));
  });

  test('reset clears configs unless keepConfigs and applies settings', () async {
    await agent.handle({'id': '1', 'op': 'import', 'uris': [_vless]});
    await agent.handle({'id': '2', 'op': 'reset', 'keepConfigs': true, 'settings': {'mtu': 1280}});
    expect(container.read(configProvider).value!.configs, hasLength(1));
    expect(container.read(settingsProvider).value!.mtu, 1280);
    expect(container.read(settingsProvider).value!.logsEnabled, isTrue);

    await agent.handle({'id': '3', 'op': 'reset'});
    expect(container.read(configProvider).value!.configs, isEmpty);
    expect(container.read(settingsProvider).value!.mtu, 1500);
  });

  test('settings patch deep-merges into current settings', () async {
    await agent.handle({'id': '1', 'op': 'settings', 'patch': {'routing': {'bypassLocal': true}}});
    await agent.handle({'id': '2', 'op': 'settings', 'patch': {'routing': {'sitesEnabled': true}}});
    final r = container.read(settingsProvider).value!.routing;
    expect(r.bypassLocal, isTrue);
    expect(r.sitesEnabled, isTrue);
  });

  test('unknown op answers ok:false with the same id', () async {
    final r = await agent.handle({'id': '9', 'op': 'nope'});
    expect(r, containsPair('id', '9'));
    expect(r['ok'], isFalse);
  });
}
