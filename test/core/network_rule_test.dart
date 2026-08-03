import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/models/network_rule.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/providers/config_provider.dart';

VpnConfig cfg(String id, String name, {String? subId}) => VpnConfig(
      id: id,
      name: name,
      protocol: VpnProtocol.vless,
      address: 'a.example',
      port: 443,
      uuid: 'u',
      security: VpnSecurity.none,
      transport: VpnTransport.tcp,
      createdAt: DateTime(2026),
      subscriptionId: subId,
    );

void main() {
  test('правило резолвится по (subId, name) после смены id конфига', () {
    const rule = NetworkRule(
        transport: NetTransport.wifi, subscriptionId: 's1', name: 'Amsterdam');
    final before = ConfigState(
        configs: [cfg('old', 'Amsterdam', subId: 's1')],
        networkRules: const [rule]);
    expect(before.configForTransport(NetTransport.wifi)!.id, 'old');
    // после обновления подписки конфиг пересоздан с новым id
    final after = ConfigState(
        configs: [cfg('new', 'Amsterdam', subId: 's1')],
        networkRules: const [rule]);
    expect(after.configForTransport(NetTransport.wifi)!.id, 'new');
  });

  test('исчезнувшее имя -> null, правило сохраняется', () {
    const rule = NetworkRule(
        transport: NetTransport.cellular, subscriptionId: 's1', name: 'Gone');
    final st = ConfigState(
        configs: [cfg('x', 'Other', subId: 's1')], networkRules: const [rule]);
    expect(st.configForTransport(NetTransport.cellular), isNull);
    expect(st.networkRules.single, rule);
  });

  test('правила разных транспортов независимы', () {
    final st = ConfigState(
      configs: [cfg('a', 'WiFi srv', subId: 's1'), cfg('b', 'LTE srv', subId: 's1')],
      networkRules: const [
        NetworkRule(
            transport: NetTransport.wifi, subscriptionId: 's1', name: 'WiFi srv'),
        NetworkRule(
            transport: NetTransport.cellular, subscriptionId: 's1', name: 'LTE srv'),
      ],
    );
    expect(st.configForTransport(NetTransport.wifi)!.id, 'a');
    expect(st.configForTransport(NetTransport.cellular)!.id, 'b');
  });

  test('transportsFor — бейджи в списке', () {
    final st = ConfigState(
      configs: [cfg('a', 'NL', subId: 's1'), cfg('b', 'DE', subId: 's1')],
      networkRules: const [
        NetworkRule(transport: NetTransport.wifi, subscriptionId: 's1', name: 'NL'),
        NetworkRule(
            transport: NetTransport.cellular, subscriptionId: 's1', name: 'NL'),
      ],
    );
    expect(st.transportsFor(st.configs[0]),
        {NetTransport.wifi, NetTransport.cellular});
    expect(st.transportsFor(st.configs[1]), isEmpty);
  });

  test('одинаковые имена в разных подписках не путаются', () {
    const rule = NetworkRule(
        transport: NetTransport.wifi, subscriptionId: 's2', name: 'NL');
    final st = ConfigState(
      configs: [cfg('a', 'NL', subId: 's1'), cfg('b', 'NL', subId: 's2')],
      networkRules: const [rule],
    );
    expect(st.configForTransport(NetTransport.wifi)!.id, 'b');
  });

  test('json roundtrip', () {
    const rule = NetworkRule(
        transport: NetTransport.cellular, subscriptionId: null, name: 'Local');
    expect(NetworkRule.fromJson(rule.toJson()), rule);
  });

  test('неизвестный транспорт в json -> null (правило отбрасывается)', () {
    expect(NetworkRule.fromJson({'transport': 'ethernet', 'name': 'X'}), isNull);
    expect(NetTransport.parse(''), isNull);
    expect(NetTransport.parse(null), isNull);
  });
}
