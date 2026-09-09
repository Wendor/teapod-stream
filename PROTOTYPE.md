# TeapodStream: Go and experimental Rust builds

The default build uses Go/teapod-core. The separate Rust build uses
**xray-rust 0.6.0+geo.1** and its direct TUN file-descriptor backend.
Rust application ID: `com.teapodstream.rustprobe`. It installs alongside the original TeapodStream.
No live VPN profile or credentials are bundled.

## Rust support (1.6.3-rust.4)

- VLESS with `encryption=none` over TCP/RAW, WebSocket, HTTPUpgrade, gRPC,
  XHTTP/SplitHTTP. TLS is supported on all these carriers; REALITY on TCP/RAW,
  gRPC and XHTTP/SplitHTTP.
- `xtls-rprx-vision` and `xtls-rprx-vision-udp443` work over TCP/RAW + REALITY.
  With `encryption=none`, Vision is rejected on WS/HTTPUpgrade/gRPC/XHTTP.
- TLS + Vision is deliberately gated: the pinned native TLS transport retains
  outer TLS decoding in direct mode and the local reference test reproduces EOF
  after the inner TLS handshake. Ordinary TLS without Vision and REALITY + Vision
  passed the same payload test. No transport/crypto patch is applied here.
- TLS certificate verification remains enabled. `pinSHA256` accepts SHA-256 of
  the full DER certificate as hex (including colon-separated hex) or base64;
  the Rust config uses `pinnedPeerCertSha256`. `allowInsecure` and ECH are rejected.
- XHTTP `auto` / `packet-up` / `stream-up` / `stream-one`, host/path/extra,
  REALITY SNI, fingerprint, public key, short ID and spiderX.
- Direct TUN, TCP/UDP, DNS through the proxy, Android per-app inclusion/exclusion,
  existing reconnect and TUN-sink kill-switch paths.
- GeoIP, GeoSite, domain suffixes, individual sites and Russian-service lists.
  BYPASS sends matches directly; ONLY sends matches through VLESS. FULL disables
  destination rules. The app selection is applied by Android before these rules.
- The bundled Loyalsoldier databases are the checksum-pinned 202609082347 snapshot.
  The existing routing screen downloads updates. A complete candidate pair is
  validated through Rust before an atomic pointer selects it; failure retains
  the prior pair. Reconnect VPN to apply new rules or databases.
- Domain routing enables bounded FakeDNS automatically (4096 addresses, 300-second
  leases) to retain domain identity through TUN. Keep DNS through VPN and domain
  detection enabled. Applications using their own encrypted DNS or cached real IPs
  may evade GeoSite matching; turn off their secure-DNS override and restart them
  after changing routing. FakeDNS returns IPv4 and suppresses AAAA in this mode.
- Ad blocking remains unsupported in this build.

The Rust build requires MTU 1500, UDP enabled and QUIC blocking disabled.
Proxy-only mode, raw Xray JSON, legacy mux, fragmentation/noise and other proxy
protocols are rejected with an error before VPN startup. ICMP handling is the
Rust core's local synthetic behavior; it is not a remote ping measurement.

Packet path: Android TUN → Rust userspace stack → VLESS/XHTTP/REALITY.
A no-auth SOCKS listener on `127.0.0.1` supports the app's heartbeat and IP check.
Device TUN traffic does not traverse this listener. SOCKS credentials settings
do not apply to this experimental build. Traffic counters report core payload
accounting, rather than the original tun2socks IP-byte counters.

## Build selection and feature flags

`TEAPOD_CORE` is a compile-time flag, with `go` as the default. Flutter forwards
it to Gradle in `dart-defines`; Gradle selects exactly one native source set and
dependency. Native `getEngine` is checked before connecting, rejecting a stale or
mismatched frontend/native build. There is no runtime switch between engines.

```sh
# Original Go core; Rust/rustup is not needed.
JAVA_HOME=/path/to/jdk17 ./build.sh release
./build.sh test

# Experimental Rust core; installs alongside Go and upgrades earlier Rust Probe versions.
JAVA_HOME=/path/to/jdk17 ./build-rust.sh release
./build-rust.sh test
```

Artifacts are copied to `build/artifacts/go/` and `build/artifacts/rust/`.
Go builds include arm64, armv7 and x86_64; Rust builds include arm64 and x86_64.
Both are release builds with AOT/R8; they currently use the local Android debug
signing key. A published release signing setup is a separate task.

For direct Flutter commands, prepare dependencies first:

```sh
./build-rust.sh binaries
flutter build apk --release --dart-define=TEAPOD_CORE=rust \
  --target-platform android-arm64,android-x64 --split-per-abi \
  --build-name=1.6.3-rust.4 --build-number=10607

# Native Android binding tests use the same base64-encoded Flutter flag.
cd android
JAVA_HOME=/path/to/jdk17 ./gradlew :xraymobile:connectedDebugAndroidTest \
  -Pdart-defines=VEVBUE9EX0NPUkU9cnVzdA==
```

`lib/core/constants/core_features.dart` is the per-core feature matrix.
Unsupported controls remain visible inside `FeatureGate`, with interaction and
keyboard focus disabled and an explanation. Imported incompatible settings have
an explicit reset action. The config builder still rejects unsupported values;
a UI change alone cannot bypass validation. Go exposes its existing controls.
Rust's upstream update buttons are gated; its source link points at this fork.

Shared requirements: Flutter/Dart compatible with `pubspec.yaml`, Android SDK,
NDK 28.2.13676358, CMake 3.22.1, Python 3 and JDK 17 (or a compatible JDK).
Rust additionally needs rustup; its first build installs Rust 1.96.0 and the
Android targets. `JAVA_HOME` is honored without changing global Flutter settings.

`fetch-go-core.py` downloads checksum-pinned teapod-core 1.1.15. Both builds use
the same checksum-pinned geodata assets. `build-rust-core.py` builds the pinned
Rust source with the documented geodata budget patch. See
[Android binding notes](android/xraymobile/README.md).

The original Go service is preserved in `android/app/src/go/`; the tested Rust
service and geodata adapter are in `android/app/src/rust/`. Notifications and
service interfaces remain compatible with the shared UI. Future lifecycle fixes
must be evaluated for both implementations.

Battery savings have not been measured. These builds support comparison; the
Rust build is not presented as proven to consume less energy.

## Verification of additional VLESS transports (1.6.3-rust.4)

90 Flutter tests passed in each build mode. The local Android interoperability
campaign passed all 10 enabled combinations against Xray-core v26.7.28,
including both REALITY/Vision flows. Each combination transferred 128 KiB in
plain echo and another 128 KiB inside TLS, with byte-for-byte verification.
TLS/Vision was separately tested and failed after the inner handshake; its flag
remains disabled. The native core itself was not modified for this expansion.


The Dart tests check carrier/security/flow combinations, TCP/RAW and WebSocket
aliases, preservation of Vision flow/path/SNI, TLS certificate pin conversion,
unsupported combinations and the per-engine QUIC policy. Rust does not inherit
Go's automatic host-side QUIC toggle for Vision; the native core enforces the
selected Vision UDP policy.

The optional local interoperability campaign uses Xray-core v26.7.28, ephemeral
keys/certificates and echo endpoints bound to host loopback. Flutter exports
configs through the production parser and builder. Android native clients send
both plain payloads and an inner TLS session (4 × 32 KiB per stream) through each
supported combination. It requires a running Android emulator; no live VPN
profile is needed:

```sh
JAVA_HOME=/path/to/jdk17 ANDROID_SERIAL=emulator-5554 \
  python3 scripts/test-rust-transports.py
```

The default download is the checksum-pinned Linux x86_64 Xray reference binary;
other platforms can set `XRAY_REFERENCE` to a compatible local binary. The
harness uses emulator host alias `10.0.2.2`; physical-device battery and WAN
performance measurements are outside this test.

## Verification of separate builds (1.6.3-rust.3)

- 71 Flutter tests passed in each mode (`TEAPOD_CORE=go` and `rust`).
  Coverage includes unchanged Go feature availability, visible-but-disabled Rust
  controls, explicit reset of an imported unsupported value, per-core config and
  SOCKS credentials, and refusal to connect with a mismatched native engine.
- Release APKs were built for all three Go ABIs and both Rust ABIs. Archive
  inspection confirms exactly the selected core: `libgojni.so` in Go and
  `libxray_ffi.so` / `libxray_mobile_jni.so` in Rust.
- Both installed builds connected through their Flutter UI with the same separately
  imported VLESS/XHTTP/REALITY profile. A different application UID received HTTP
  204 through each VPN, followed by a successful explicit disconnect.
- The Go service source is byte-for-byte identical to the upstream baseline.
- The installed Rust network screen retains SOCKS authentication and proxy-only
  controls with disabled interaction and explanatory text.
- Static analysis has no new findings; three existing `onReorder` deprecation
  infos remain.

## Verification of routing (1.6.3-rust.2)

- 63 Flutter tests passed, including both routing modes and failed-download/failed-validation retention.
- 6 Android native tests passed: GeoSite match/non-match, GeoIP literal/domain matching,
  missing/corrupt databases, and simultaneous loading of bundled US/RU plus Cloudflare/YouTube sets.
- On the API 36 emulator, a separate application fetched an external-IP endpoint:
  baseline used the VPN IP; GeoSite BYPASS, GeoIP US BYPASS, and a combined GeoSite/GeoIP
  fallback used the physical connection's IP; GeoSite ONLY used the VPN IP for a match
  and the physical IP for a different domain.
- The same application used the physical IP when excluded by Android's app allowlist,
  and the VPN IP when selected. The test disconnected between cases.
- Updating databases through the app downloaded and validated a new pair, activated
  its generation, and retained the bundled pair. Combined GeoIP/GeoSite routing
  passed again after reconnecting against the downloaded generation.
- Native libraries packaged in both APKs match the patched build after Android's symbol stripping.

## Validation on a phone

The initial 1.6.3-rust.1 validation on 2026-09-09 passed 57 Flutter tests. An Android API 36 x86_64
emulator connected using a separately imported VLESS/XHTTP/REALITY profile.
A second application (a different UID) received valid DNS answers over UDP
through the TUN DNS endpoint and HTTP 204 through the tunnel. The same probes
passed after disconnecting and reconnecting. The native diagnostic snapshot
reported `tunBackend: fd` and no packet drops in the sampled run.
`flutter analyze` reports only three pre-existing `onReorder` deprecation infos.
Physical-device battery, Wi-Fi/cellular transitions and extended sleep tests
remain to be measured; the emulator result is a functional smoke test.

Import a VLESS share link in the app, approve the Android VPN request, and test
web browsing, DNS/UDP, screen-off resume, reconnect and disconnect. In the
diagnostic snapshot, `engine` must be `xray-rust 0.6.0+geo.1` and `tunBackend` must be
`fd`; incoming and outgoing packet counters should increase with app traffic.

Compare energy against the original app on the same phone, server, network and
workload. Desktop/emulator tests cannot establish a battery-life improvement.

## Dependencies

- [xray-rust source](https://github.com/aimalygin/xray-rust), MPL-2.0.
- [Pinned source](https://github.com/aimalygin/xray-rust/tree/8a86a7f762aba919ff75cad5980a28612ba2dfe8), with [local budget patch](third_party/xray-rust/geo-budgets.patch).
- [Bundled geodata snapshot](https://github.com/Loyalsoldier/v2ray-rules-dat/releases/tag/202609082347).
- Upstream TeapodStream retains its existing license.
