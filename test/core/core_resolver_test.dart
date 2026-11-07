import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/cores/core_backend.dart';
import 'package:teapodstream/core/cores/core_resolver.dart';
import 'package:teapodstream/core/models/core_kind.dart';
import 'package:teapodstream/core/models/protocol_settings.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/services/settings_service.dart';
import 'package:teapodstream/protocols/xray/xray_rust_backend.dart';
import 'package:teapodstream/providers/core_provider.dart';

VpnConfig _cfg({VpnProtocol protocol = VpnProtocol.vless, ProtocolSettings? settings, CoreKind? core}) =>
    VpnConfig(
      id: 'c', name: 'c', protocol: protocol, address: '1.2.3.4', port: 443,
      uuid: '11111111-2222-4333-8444-555555555555', security: VpnSecurity.tls,
      transport: VpnTransport.tcp, createdAt: DateTime(2026), protocolSettings: settings, core: core,
    );

const _wg = WireGuardSettings(privateKey: 'k', addresses: ['10.0.0.2/32'], peerPublicKey: 'p');
const _rustFirst = [CoreKind.xrayRust, CoreKind.xrayGo, CoreKind.singBox];
final _all = CoreKind.values.toSet();

CoreResolver _resolver({
  List<CoreKind> order = CoreKind.defaultOrder,
  Set<CoreKind> disabled = const {},
  Set<CoreKind>? available,
  bool proxyOnly = false,
}) =>
    CoreResolver(AppSettings(coreOrder: order, disabledCores: disabled, proxyOnly: proxyOnly),
        available ?? _all, coreBackendFor);

void main() {
  test('first core by priority that supports the profile wins', () {
    final r = _resolver().resolve(_cfg(protocol: VpnProtocol.wireguard, settings: _wg));
    expect(r.backend!.kind, CoreKind.singBox);
    expect(r.reason, isNull);
    expect(r.verdicts.first.kind, CoreKind.xrayGo);
    expect(r.verdicts.first.reason, VpnProtocol.wireguard.singBoxOnlyReason);
    expect(r.verdicts.last.reason, VpnProtocol.wireguard.singBoxOnlyReason);
  });

  test('disabled and unavailable cores are skipped with a reason', () {
    final r = _resolver(order: _rustFirst, disabled: {CoreKind.xrayRust}, available: {CoreKind.xrayRust, CoreKind.singBox})
        .resolve(_cfg());
    expect(r.backend!.kind, CoreKind.singBox);
    expect([for (final v in r.verdicts) v.reason],
        [CoreResolver.disabledReason, CoreResolver.unavailableReason, null]);
  });

  test('a blocking setting skips the core, warnings do not', () {
    expect(_resolver(order: _rustFirst, proxyOnly: true).resolve(_cfg()).backend!.kind, CoreKind.xrayGo);
    final rustOnly = _resolver(proxyOnly: true, available: {CoreKind.xrayRust}).resolve(_cfg());
    expect(rustOnly.backend, isNull);
    expect(rustOnly.reason, const XrayRustBackend().unavailableReason(CoreFeature.proxyOnly));
  });

  test('pinned core goes first; an unusable pin falls back', () {
    final pinned = _resolver().resolve(_cfg(core: CoreKind.singBox));
    expect(pinned.backend!.kind, CoreKind.singBox);
    expect(pinned.pinned, isTrue);
    expect(pinned.verdicts.map((v) => v.kind), [CoreKind.singBox, CoreKind.xrayGo, CoreKind.xrayRust]);

    final fallback = _resolver(disabled: {CoreKind.singBox}).resolve(_cfg(core: CoreKind.singBox));
    expect(fallback.backend!.kind, CoreKind.xrayGo);
    expect(fallback.pinned, isFalse);
  });

  test('nothing can run the profile — first reason is reported', () {
    final r = _resolver(disabled: {CoreKind.singBox}).resolve(_cfg(protocol: VpnProtocol.wireguard, settings: _wg));
    expect(r.backend, isNull);
    expect(r.reason, VpnProtocol.wireguard.singBoxOnlyReason);
  });

  test('usable and primary follow order, switches and device', () {
    final r = _resolver(order: _rustFirst, disabled: {CoreKind.xrayRust}, available: {CoreKind.xrayRust, CoreKind.singBox});
    expect(r.usable, [CoreKind.singBox]);
    expect(r.primary, CoreKind.singBox);
  });
}
