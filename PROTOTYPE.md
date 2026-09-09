# Teapod Rust Probe

Experimental Android fork using **xray-rust 0.6.0+geo.1** and its direct TUN file-descriptor backend.
Application ID: `com.teapodstream.rustprobe`. It installs alongside the original TeapodStream.
No live VPN profile or credentials are bundled.

## Supported configuration (1.6.3-rust.2)

- VLESS + XHTTP/SplitHTTP + REALITY, `encryption=none`, empty `flow`.
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

The first build requires MTU 1500, UDP enabled and QUIC blocking disabled.
Proxy-only mode, raw Xray JSON, legacy mux, fragmentation/noise and other proxy
protocols are rejected with an error before VPN startup. ICMP handling is the
Rust core's local synthetic behavior; it is not a remote ping measurement.

Packet path: Android TUN → Rust userspace stack → VLESS/XHTTP/REALITY.
A no-auth SOCKS listener on `127.0.0.1` supports the app's heartbeat and IP check.
Device TUN traffic does not traverse this listener. SOCKS credentials settings
do not apply to this experimental build. Traffic counters report core payload
accounting, rather than the original tun2socks IP-byte counters.

## Build

Requires Flutter/Dart compatible with `pubspec.yaml`, Android SDK/NDK
28.2.13676358, CMake 3.22.1, Python 3, rustup and JDK 17 (or a compatible JDK).
The first build installs Rust 1.96.0 and the two Android targets locally.
If Android Studio's JBR is too new for Gradle/Kotlin, set `JAVA_HOME` for this
command. This does not modify global Flutter settings.

```sh
JAVA_HOME=/path/to/jdk17 ./build.sh release
./build.sh test
flutter analyze
```

`scripts/fetch-rust-core.py` verifies the bundled databases and invokes the
native build. `scripts/build-rust-core.py` fetches the pinned upstream commit,
applies `third_party/xray-rust/geo-budgets.patch` and builds the native libraries.
Only geodata parsing budgets differ from upstream Rust 0.6.0. See
[the binding notes](android/xraymobile/README.md) for provenance and limits.
Generated APKs are in `build/app/outputs/flutter-apk/`:
`app-arm64-v8a-release.apk` for phones and `app-x86_64-release.apk` for emulators.
The prototype uses the local Android debug signing key even in release mode.

Automatic upstream APK updates are disabled. The original project's README
below describes upstream features, not the support boundary of this probe.

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
