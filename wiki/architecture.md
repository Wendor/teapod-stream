# Architecture

TeapodStream is an Android VPN client: a Flutter UI, a Kotlin `VpnService`, and three proxy cores in the native
`teapod-core` AAR.

```
┌──────────────────────────────────────────────────────────────┐
│ Flutter (Dart)                                               │
│  UI (screens, widgets) → Riverpod providers → services       │
│                        → core backends (config builders)     │
│                        → XrayEngine, PlatformService (native)│
├──────────────────────────────────────────────────────────────┤
│ Android (Kotlin)                                             │
│  MainActivity → channel handlers → XrayVpnService → VpnCore  │
├──────────────────────────────────────────────────────────────┤
│ teapod-core AAR (core/)                                      │
│  xray-core (Go) · sing-box (Go) · teapod-tun2socks · xray-rust│
└──────────────────────────────────────────────────────────────┘
```

Layering rule: widgets read providers and call notifiers; providers orchestrate; services do I/O and persistence and are
reached through their own providers (tests override them);
core backends build configs; only `XrayEngine` (the tunnel) and `PlatformService` (system calls) talk to native; only `XrayVpnService` and the classes it wires (`Heartbeat`, `NetworkWatcher`) talk to the cores.

## Traffic

```
xray-core (Go), sing-box:  apps → TUN → teapod-tun2socks (gVisor, owner check) → SOCKS5 127.0.0.1:<port> → core → server
xray-rust:                 apps → TUN fd → xray-rust (routing, outbounds) → server
proxy-only (xray Go, sing-box): no TUN; the core's SOCKS5 inbound only
```

The app's own process is excluded from the tunnel; its downloads use the tunnel's SOCKS explicitly
([TunnelSocks](components/services.md#tunnelsocks)).

## Cores

Three cores ship in one APK. Each config runs on the **first core by priority** (`AppSettings.coreOrder`, minus
`disabledCores` and cores that don't load on the device) that accepts it; a config can pin a core (`VpnConfig.core`).

| Layer | Abstraction | Implementations |
|---|---|---|
| Dart | `CoreBackend` (`lib/core/cores/core_backend.dart`): `supports(CoreFeature)`, `checkConfig`, `checkOptions` (blocking reason / warnings), `buildConfig`, `buildProbeConfig`, heartbeat and QUIC overrides | `XrayGoBackend`, `XrayRustBackend`, `SingBoxBackend` |
| Dart | `CoreResolver` picks the core; `buildEngineOptions` builds the options; `OptionsSanitizer` drops options a core ignores, with warnings | |
| Native | `VpnCore` (`core/VpnCore.kt`) | `GoCore`, `BoxCore` (both on `Tun2SocksCore`), `RustCore` |

**Adding an option or a protocol** means handling it in every backend — or refusing it there with a reason (an
`AppMessage`, [localization](components/localization.md); `checkConfig` disables the config,
`checkOptions(...).blocking` forbids connecting, `warnings` are logged, `CoreFeature` marks the setting in the UI). Never let a core silently ignore something that changes where traffic
goes. Details: [vpn_provider](components/vpn_provider.md#choosing-the-core),
[xray_config_builder](components/xray_config_builder.md), [singbox_config_builder](components/singbox_config_builder.md),
[android_native](components/android_native.md#cores-core).

| Protocols | xray Go | xray-rust | sing-box |
|---|---|---|---|
| VLESS, VMess, Trojan, Shadowsocks, Hysteria2 | ✓ | subset | ✓ (no XHTTP) |
| WireGuard, AmneziaWG, SSH, NaiveProxy | — | — | ✓ |
| Managed raw JSON configs | ✓ | — | — |

## Flutter ↔ native

| Channel | Direction | Content |
|---|---|---|
| `MethodChannel("com.teapodstream/vpn")` | Dart → native | `connect`, `disconnect`, `getState`, stats, ping, measure, logs ([XrayEngine](components/xray_engine.md); native `VpnChannelHandler`); versions, cores, apps, files, ABI, APK install, device info ([PlatformService](components/services.md#platformservice); native `PlatformChannelHandler`) |
| `EventChannel("com.teapodstream/vpn/events")` | native → Dart | `state` (+ SOCKS credentials and `connectedAtMs` on `connected`, `error` on `error`/`blocked`), `log`, `statsHistory`, `tunnel_dead`, `deeplink` |

One broadcast stream (`XrayEngine.events`) serves all Dart listeners. On `onListen` native replays the current state,
so a restarted UI catches up with a running service.

## Connecting

```
tap → VpnNotifier.connect()
    → effectiveConfigProvider → validate → CoreResolver → buildEngineOptions → checkOptions
    → XrayEngine.connect → backend.buildConfig → MethodChannel 'connect'
    → MainActivity → VpnChannelHandler: VPN permission → XrayVpnService ACTION_CONNECT
    → establish TUN → VpnCore.start → setConnected → event 'state: connected'
    → VpnNotifier: state, appliedFingerprint → vpnStatsProvider: stats polling
```

Safety timeouts in Flutter: 45 s for connecting, 10 s for disconnecting.

## Native autonomy

Reconnects after a network change or a dead tunnel run entirely in `XrayVpnService`, also when the UI is gone:
`reconnectInternal()` replaces the connected session's desired state in `SessionReconciler` with a new one that waits
for direct internet first (parameters from disk), reusing the TUN fd. The tile, boot receiver and automation broadcasts use the same quick-connect path. Flutter only mirrors state —
except `switchConfig`, where native asks Flutter (`tunnel_dead`) to pick another config.
[android_native](components/android_native.md#network-changes)

## Persistence

| Data | Where |
|---|---|
| Configs, subscriptions, profiles (the settings in force are the active profile's), pins | flutter_secure_storage (`StorageSecureService`) |
| Flags native reads (`auto_start_on_boot`, `automation_enabled`), app locale, active profile id | SharedPreferences |
| Core config, quick-reconnect parameters, logs | native `filesDir` |
| Geodata | `filesDir/geoip.dat`, `geosite.dat` (+ `.srs` for sing-box) |

[security](security.md#data-classification-and-storage)

## Source layout

```
lib/
├── app.dart, main.dart       shell (startup steps: providers/app_lifecycle_provider.dart)
├── core/
│   ├── constants/            channel names, ports, xray and routing defaults
│   ├── cores/                CoreBackend, CoreResolver, engine options, sanitizer, core switching
│   ├── interfaces/           VpnEngineOptions, VpnState
│   ├── models/               VpnConfig, AppSettings and its parts, subscriptions, profiles, bundles, stats, logs
│   └── services/             storage, subscriptions, tunnel SOCKS, updates, deep-link parsing, logs
├── protocols/
│   ├── xray/                 XrayEngine, Go/Rust backends and builders, VlessParser
│   ├── singbox/              sing-box backend, builder, outbounds, route
│   └── parsers/              WireGuard, AmneziaVPN, SSH, Naive
├── providers/                Riverpod notifiers and derived providers
├── itest/                    integration-test agent (…itest build only)
├── l10n/                     ARB files and generated localizations
└── ui/                       screens, widgets, theme, deep-link import dialogs
android/app/src/main/kotlin/com/teapodstream/teapodstream/   service, activity, cores, receivers, tile
tool/itest/                   on-device integration test runner
changelog/                    release notes, one file per language (CI/CD → release notes)
```

## Constraints

- Min SDK 29 (Android 10). ABIs: arm64-v8a, x86_64.
- `teapod-core.aar` is not in git: it is built from `core/` and identified by the `core/` tree hash
  ([teapod_core](components/teapod_core.md)). The app version (`./build.sh bump X.Y.Z`) is independent of it.
- Loyalsoldier geodata has no `geosite:ru` — Russian domains use `domain:ru`.
