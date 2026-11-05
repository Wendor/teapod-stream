import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/models/pinned_ref.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/providers/config_provider.dart';

VpnConfig cfg(String id, String name, {String? subId, int port = 443}) => VpnConfig(
      id: id,
      name: name,
      protocol: VpnProtocol.vless,
      address: 'a.example',
      port: port,
      uuid: 'u',
      security: VpnSecurity.none,
      transport: VpnTransport.tcp,
      createdAt: DateTime(2026),
      subscriptionId: subId,
    );

void main() {
  test('пин резолвится по (subId, name) после смены id конфига', () {
    const pin = PinnedRef(subscriptionId: 's1', name: 'Amsterdam');
    final before = ConfigState(
        configs: [cfg('old', 'Amsterdam', subId: 's1')], pins: const [pin]);
    expect(before.resolvedPins.single.$2!.id, 'old');
    // после обновления подписки конфиг пересоздан с новым id
    final after = ConfigState(
        configs: [cfg('new', 'Amsterdam', subId: 's1')], pins: const [pin]);
    expect(after.resolvedPins.single.$2!.id, 'new');
  });

  test('исчезнувшее имя -> null, пин сохраняется', () {
    const pin = PinnedRef(subscriptionId: 's1', name: 'Gone');
    final st =
        ConfigState(configs: [cfg('x', 'Other', subId: 's1')], pins: const [pin]);
    expect(st.resolvedPins.single.$1, pin);
    expect(st.resolvedPins.single.$2, isNull);
  });

  test('одинаковые имена в разных подписках не путаются', () {
    const pin = PinnedRef(subscriptionId: 's2', name: 'NL');
    final st = ConfigState(
      configs: [cfg('a', 'NL', subId: 's1'), cfg('b', 'NL', subId: 's2')],
      pins: const [pin],
    );
    expect(st.resolvedPins.single.$2!.id, 'b');
  });

  test('standalone-пин (subscriptionId == null)', () {
    const pin = PinnedRef(subscriptionId: null, name: 'Local');
    final st = ConfigState(
      configs: [cfg('a', 'Local', subId: 's1'), cfg('b', 'Local')],
      pins: const [pin],
    );
    expect(st.resolvedPins.single.$2!.id, 'b');
  });

  test('isPinned', () {
    const pin = PinnedRef(subscriptionId: 's1', name: 'NL');
    final st = ConfigState(
      configs: [cfg('a', 'NL', subId: 's1'), cfg('b', 'NL', subId: 's2')],
      pins: const [pin],
    );
    expect(st.isPinned(st.configs[0]), isTrue);
    expect(st.isPinned(st.configs[1]), isFalse);
  });

  test('json roundtrip', () {
    const pin = PinnedRef(subscriptionId: null, name: 'Local');
    expect(PinnedRef.fromJson(pin.toJson()), pin);
    const pin2 = PinnedRef(subscriptionId: 's1', name: 'NL');
    expect(PinnedRef.fromJson(pin2.toJson()), pin2);
  });

  test('одноимённые конфиги различаются по endpoint', () {
    final configs = [
      cfg('a', 'VLESS Server', subId: 's1', port: 443),
      cfg('b', 'VLESS Server', subId: 's1', port: 4446),
    ];
    final pin = PinnedRef.of(configs[1]);
    final st = ConfigState(configs: configs, pins: [pin]);
    expect(st.resolvedPins.single.$2!.id, 'b');
    expect(st.isPinned(configs[0]), isFalse);
    // endpoint исчез — фоллбэк на одноимённый
    final st2 = ConfigState(configs: [configs[0]], pins: [pin]);
    expect(st2.resolvedPins.single.$2!.id, 'a');
    expect(PinnedRef.fromJson(pin.toJson()), pin);
  });
}
