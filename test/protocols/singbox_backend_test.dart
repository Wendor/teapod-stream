import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/cores/core_backend.dart';
import 'package:teapodstream/core/interfaces/vpn_engine.dart';
import 'package:teapodstream/core/models/core_kind.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/core/models/xray_tuning.dart';
import 'package:teapodstream/protocols/singbox/singbox_backend.dart';

VpnConfig _vless({String? flow, VpnTransport transport = VpnTransport.tcp, String? pqv}) => VpnConfig(
  id: 'v',
  name: 'v',
  protocol: VpnProtocol.vless,
  address: 'h.example',
  port: 443,
  uuid: '11111111-2222-4333-8444-555555555555',
  security: pqv == null ? VpnSecurity.tls : VpnSecurity.reality,
  publicKey: pqv == null ? null : 'PK',
  postQuantumKey: pqv,
  transport: transport,
  createdAt: DateTime(2026),
  encryption: 'none',
  flow: flow,
);

VpnEngineOptions _opts({
  NoiseSettings noise = const NoiseSettings(),
  MuxSettings mux = const MuxSettings(),
  FragmentSettings fragment = const FragmentSettings(),
}) => VpnEngineOptions(socksPort: 1, socksUser: 'u', socksPassword: 'p', noise: noise, mux: mux, fragment: fragment);

void main() {
  const CoreBackend box = SingBoxBackend();

  test('kind and unsupported features', () {
    expect(box.kind, CoreKind.singBox);
    const off = {CoreFeature.noise, CoreFeature.mux, CoreFeature.observatory, CoreFeature.rawConfig};
    for (final f in CoreFeature.values) {
      expect(box.supports(f), !off.contains(f), reason: f.name);
      expect(box.unavailableReason(f) == null, !off.contains(f), reason: f.name);
    }
  });

  test('checkOptions warns about settings the core ignores and never blocks', () {
    final check = box.checkOptions(
      _vless(),
      _opts(
        noise: const NoiseSettings(enabled: true),
        mux: const MuxSettings(enabled: true),
        fragment: const FragmentSettings(enabled: true, packets: '1-3'),
      ),
    );
    expect(check.blocking, isNull);
    expect(check.warnings.map((w) => '$w'), [
      "Noise isn't available in the sing-box core and is not applied.",
      'Xray Mux is incompatible with the sing-box core and is not applied.',
      'Fragmentation in the sing-box core covers only the TLS ClientHello; mode "1-3" is not applied.',
    ]);
    expect(box.checkOptions(_vless(), _opts()).warnings, isEmpty);
  });

  test('Reality pqv: profile runs, ML-DSA check skipped with a warning', () {
    final pqv = _vless(pqv: 'k');
    expect(box.checkConfig(pqv), isNull);
    expect(box.checkOptions(pqv, _opts()).warnings.map((w) => '$w'), [
      "Reality: the sing-box core doesn't verify the ML-DSA signature (pqv) — the server is verified by the Reality key only.",
    ]);
  });

  test('QUIC block follows tun2socks rules of the Go core', () {
    expect(box.effectiveQuicBlock(requested: false, flow: 'xtls-rprx-vision'), isTrue);
    expect(box.effectiveQuicBlock(requested: false, flow: null), isFalse);
    expect(box.effectiveQuicBlock(requested: true, flow: null), isTrue);
  });

  test('checkConfig delegates to the sing-box builder', () {
    expect(box.checkConfig(_vless()), isNull);
    expect(box.checkConfig(_vless(transport: VpnTransport.xhttp)), isNotNull);
  });
}
