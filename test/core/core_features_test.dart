import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/constants/core_features.dart';
import 'package:teapodstream/core/models/heartbeat_settings.dart';

void main() {
  test('Go keeps all existing feature flags enabled', () {
    expect(CoreFeature.values.every(CoreFeatures.go.supports), isTrue);
  });

  test('Rust keeps routing and gates only its unsupported features', () {
    for (final feature in [
      CoreFeature.geoip,
      CoreFeature.geosite,
      CoreFeature.appRouting,
      CoreFeature.directDns,
      CoreFeature.adBlocking,
      CoreFeature.passiveHeartbeat,
      // xray-rust 0.8.1: blackhole routing, FinalMask fragment and noise.
      CoreFeature.quicBlocking,
      CoreFeature.udpToggle,
      CoreFeature.fragmentation,
      CoreFeature.noise,
      // xray-rust 0.8.1: probeOutboundUrl, temporary candidate cores, TUN admission.
      CoreFeature.coreDelayProbe,
      CoreFeature.outboundDelayProbe,
      CoreFeature.tetheringControl,
    ]) {
      expect(CoreFeatures.rust.supports(feature), isTrue, reason: feature.name);
      expect(CoreFeatures.rust.unavailableReason(feature), isNull);
    }
    for (final feature in [
      CoreFeature.proxyOnly,
      CoreFeature.mux,
      CoreFeature.socksAuthentication,
      CoreFeature.customMtu,
      CoreFeature.icmpToggle,
      CoreFeature.observatory,
      CoreFeature.rawConfig,
    ]) {
      expect(CoreFeatures.rust.supports(feature), isFalse);
      expect(CoreFeatures.rust.unavailableReason(feature), isNotEmpty);
    }
  });

  test('Go blocks QUIC on the TUN side for every Vision flow', () {
    const go = CoreFeatures.go;
    for (final flow in ['xtls-rprx-vision', 'xtls-rprx-vision-udp443']) {
      expect(go.effectiveQuicBlock(requested: false, flow: flow), isTrue);
    }
    for (final flow in [null, '']) {
      expect(go.effectiveQuicBlock(requested: false, flow: flow), isFalse);
      expect(go.effectiveQuicBlock(requested: true, flow: flow), isTrue);
    }
  });

  test('Rust leaves plain-Vision UDP/443 to the core\'s ICMP reply', () {
    const rust = CoreFeatures.rust;
    // The core answers plain Vision UDP/443 with ICMP port unreachable; a
    // blackhole rule would turn that into a silent drop.
    expect(
      rust.effectiveQuicBlock(requested: false, flow: 'xtls-rprx-vision'),
      isFalse,
    );
    // -udp443 is blocked as in Go.
    expect(
      rust.effectiveQuicBlock(
        requested: false,
        flow: 'xtls-rprx-vision-udp443',
      ),
      isTrue,
    );
    for (final flow in [null, '']) {
      expect(rust.effectiveQuicBlock(requested: false, flow: flow), isFalse);
    }
    // The user's toggle blocks QUIC for any profile.
    for (final flow in [null, 'xtls-rprx-vision', 'xtls-rprx-vision-udp443']) {
      expect(rust.effectiveQuicBlock(requested: true, flow: flow), isTrue);
    }
  });

  test('Go keeps every heartbeat probe exactly as stored', () {
    expect(CoreFeatures.go.heartbeatProbes, HeartbeatProbe.values);
    for (final probe in HeartbeatProbe.values) {
      expect(CoreFeatures.go.supportsHeartbeatProbe(probe), isTrue);
      expect(CoreFeatures.go.effectiveHeartbeatProbe(probe), probe);
    }
  });

  test('Rust offers every heartbeat probe and keeps it as stored', () {
    expect(CoreFeatures.rust.heartbeatProbes, HeartbeatProbe.values);
    expect(CoreFeatures.heartbeatProbeFeature(HeartbeatProbe.socks), isNull);
    for (final probe in HeartbeatProbe.values) {
      expect(CoreFeatures.rust.supportsHeartbeatProbe(probe), isTrue);
      expect(CoreFeatures.rust.effectiveHeartbeatProbe(probe), probe);
    }
  });

  test('the Rust ICMP note covers the drop under the owner check', () {
    expect(
      CoreFeatures.rust.unavailableReason(CoreFeature.icmpToggle),
      contains('отбрасывается'),
    );
  });

  test('availability and its explanation agree for every feature and core', () {
    for (final features in [CoreFeatures.go, CoreFeatures.rust]) {
      for (final feature in CoreFeature.values) {
        if (features.supports(feature)) {
          expect(
            features.unavailableReason(feature),
            isNull,
            reason: feature.name,
          );
        } else {
          expect(
            features.unavailableReason(feature),
            isNotEmpty,
            reason: feature.name,
          );
        }
      }
    }
  });

  test('the build uses the requested core flag, defaulting to Go', () {
    const expected = String.fromEnvironment('TEAPOD_CORE', defaultValue: 'go');
    expect(CoreFeatures.current.isRust, expected == 'rust');
  });
}
