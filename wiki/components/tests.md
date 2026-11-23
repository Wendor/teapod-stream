# Tests

Dart tests cover models, services, providers, protocol builders and screens; JVM tests cover the Kotlin logic that
doesn't need Android (`ConnectionParams`, `PrefixTcpProxy`, `SocksHttpProbe`, `SessionCommands`, `TunOwnerPolicy`, `SpeedHistory`, utilities). The
`VpnService`, the cores and TUN are verified on a device — by hand or with the integration tests below.

```bash
flutter test                                       # all Dart tests (~20 s)
flutter test --coverage                            # + coverage/lcov.info (not committed)
(cd android && ./gradlew :app:testDebugUnitTest)   # JVM tests (needs the AAR: ./build.sh binaries)
(cd core && ./build.sh prepare && go test ./...)  # Go tests of the engines and tun2socks (host)
```

A fix comes with a test that fails without it; a logic change comes with tests of the new behaviour.

## Layout

| Directory | What |
|---|---|
| `test/core/` | models, bundles, `AppSettings`/`SettingsService`, storage, migration, subscriptions, updates and release notes, `changelog/` files, deep links, logs, `DeviceService` |
| `test/protocols/` | link parsers, Go/Rust/sing-box builders, `XrayEngine` (MethodChannel) |
| `test/providers/` | `ConfigNotifier`, profiles/settings, `VpnNotifier`, update/geo/ipInfo and small providers |
| `test/ui/` | smoke of every screen (empty / with data), interactions, deep link dialogs, settings |
| `test/l10n/` | ARB key and placeholder parity |
| `test/itest/`, `test/tool/itest/` | logic of the integration-test agent and runner |
| `test/helpers/` | `local_server.dart` (HTTP(S) server, `RedirectHttpOverrides`), `ui_harness.dart` (`setUpScreenTest`, `pumpScreen` with localization delegates and locale `en`, `settle`, `unmount`, `FakeNative`) |
| `test/fixtures/` | a self-signed certificate for `127.0.0.1`/`localhost` (TOFU pin tests only) |
| `android/app/src/test/` | JVM tests |

## Techniques and pitfalls

- **Storage:** `SharedPreferences.setMockInitialValues({'storage_migrated_v2': true})` +
  `FlutterSecureStorage.setMockInitialValues({})`. `StorageMigrationService` runs once per process — the migration
  scenario lives in its own file.
- **Network without mocks:** `LocalServer` on 127.0.0.1. `TestWidgetsFlutterBinding` replaces `HttpClient` with a stub
  (always 400): use a file without the binding, `HttpOverrides.global = null`, or a `RedirectHttpOverrides(port)` zone
  (also redirects hard-coded URLs such as api.github.com).
- **App requests** go through `AppHttp` (`dart:io`), so `LocalServer` with `RedirectHttpOverrides` covers them;
  `package:http`'s `MockClient` doesn't reach them. A widget test that needs a real response sets
  `HttpOverrides.global` and lets the IO run in short `tester.runAsync` delays between pumps (`flows_test.dart`).
- **Native:** `setMockMethodCallHandler` for `com.teapodstream/vpn`, `setMockStreamHandler(MockStreamHandler.inline(...))`
  for events. `XrayEngine.events` is a static broadcast stream — install the handler before building `vpnProvider`.
- **fakeAsync:** EventChannel events aren't delivered in the fake zone (they go through the root zone); MethodChannel
  calls are. Test `VpnNotifier` timeouts through `syncNativeState()`, not events.
- **Riverpod 3:** `ref.read(p.future)` inside a listener of `p` returns the **previous** value — use
  `ref.read(p).value`. A fire-and-forget `syncActiveSettings` outlives the test — let the queue drain before disposing
  the container.
- **Widget tests:** no `runAsync` (google_fonts would hit the network). The test font is wider than the real one — use
  a 600 px viewport to avoid false overflows. Config groups in `ConfigsScreen` start collapsed.
- **HTTP progress:** `dart:io` buffers small chunks until the response ends — use ~64 KB chunks to observe progress.
- **Kotlin:** `unitTests.isReturnDefaultValues = true` — stubs like `android.util.Log` don't throw.

Not covered by unit tests: `QrScanScreen` (camera), `main.dart`, `XrayVpnService`, `MainActivity`, and the cores running
on Android with a real TUN (the Go engines have host unit tests; on-device behaviour needs the integration tests).

## Integration tests on a device (`tool/itest/`)

A runner on the computer drives a separate `…itest` build on a USB-connected phone through real providers and checks
real traffic.

```bash
cp tool/itest/secrets.example.json tool/itest/secrets.json   # your servers; the file is gitignored
dart run tool/itest/main.dart                                # build and install …itest, matrix + soak
dart run tool/itest/main.dart --skip-install --phase matrix --core sing-box --config 'name*'
dart run tool/itest/main.dart --skip-install --phase soak --core xray-core --fault offline-1m --repeat 5 --duration 2h
dart run tool/itest/main.dart --skip-install --list          # which cases would run
```

Filters: `--phase matrix|soak|all`, `--config` / `--core` / `--case` (glob), `--fault
wifi-lte|offline-10s|offline-1m|offline-5m|doze|kill|idle`, `--repeat`, `--duration`, `--probe-interval`.

**How it works.**
- `./build.sh itest` builds `com.teapodstream.teapodstream.itest` (`TEAPOD_ITEST=1` → `applicationIdSuffix`,
  `--dart-define=ITEST=true` → `kItest`), installed next to the normal app without touching its data. Normal builds
  are unchanged.
- Commands: `am start … -a com.teapodstream.ITEST --es cmd '<json>'` → `ItestBridge` (Kotlin, buffers until Dart is
  ready) → MethodChannel `com.teapodstream/itest` → `ItestAgent` (`lib/itest/`). Operations: `ping`, `reset`, `import`,
  `list`, `settings`, `connect {configId, core}`, `disconnect`, `state`, `drop` (unexpected drop, for the kill switch),
  `goroutines`.
- Replies are `TEAPOD_ITEST {json}` lines in logcat; replies over 900 characters go to a file read with `run-as`
  (Flutter splits log lines at ~1024).
- Traffic is checked from `adb shell` (`curl`): the shell UID goes through TUN like a normal app and works for split
  tunneling; the app itself is excluded from the tunnel.

**Through the tunnel or not.** A baseline without VPN records each echo service's answer. The expected exit is the
config's `egressIp` from secrets, or the server host's IPv4 as a hint. A service is "distinguishable" if its direct IP
differs from the exit; a leak is a distinguishable service seeing the direct IP. When the exit equals the provider's
IP (server in the same network) leak checks are skipped. DNS leaks are judged by the resolver's provider, not IP.

**Cases.** `base/<core>/<config>` — every config on every compatible core; `opt/<core>/<option>` — on a reference
config: routing (sites, zone, geoip, geosite, ad block), DNS modes, split tunneling, kill switch, ICMP, UDP, QUIC, Mux,
fragment, noise, sniffing, MTU, TLS fingerprint, proxy-only. **Soak**: per core, quiet interval → fault → recovery
until `--duration`; FAIL = no traffic 3 min after the network is back, ZOMBIE = `connected` without traffic ≥ 3 min.

**Logs:** `runs/<date_time>/` (gitignored): full logcat, baseline, per-case steps and logcat slices, on failure a Go
goroutine dump (`goroutines.txt`), connectivity and the app log; soak timelines; `report.md` / `report.json` (secrets
masked, raw logs not — never attach them to an issue unmasked).

**Pitfalls:** `adb shell` over USB sometimes hangs ~20 s — calls get 25 s and one retry. Starting the itest VPN stops
the main app's VPN (one VPN at a time). Finalization restores the phone (Wi-Fi, airplane mode, Doze, battery,
stay-awake) once, also on Ctrl+C or an unhandled error.

## Related

[CI](ci.md) · [VpnProvider](vpn_provider.md) · [Services](services.md)
