# SettingsProvider — app settings

**Files:** `lib/providers/settings_provider.dart`, `lib/core/models/app_settings.dart` (`AppSettings`, its enums,
`GeoPresets`), `lib/core/models/setting_field.dart` (`SettingField`, `SettingFields`), `lib/core/services/settings_service.dart` (`SettingsService`),
`lib/core/models/xray_tuning.dart`, `lib/core/models/heartbeat_settings.dart`, `lib/core/models/routing_settings.dart`

The settings in force are the active profile's ([profiles](profiles.md)): stored once, inside the profile.
`SettingsNotifier` (`AsyncNotifier<AppSettings>`) derives them from `profileProvider` (synchronously once it is
loaded, so a reader right after a save sees the saved value) and writes through
`ProfileNotifier.updateActiveSettings`: one queue with the other profile writes, a read-only profile refuses there.
Every write is a change applied to the settings current when it runs, so a write queued in between (another
field, `cleanGhostPackages`) survives; it goes to the profile active when it was called. Screens name *which* setting
changes and never build settings objects:

- `set(field, value)` / `modify(field, change)` — one field of `SettingFields`, a `SettingField<T>` that reads and
  writes it, nested sections (`routing`, `heartbeat`, `mux`, `fragment`, `noise`) included. `modify` gets the field's
  current value: removing one item of a list keeps a removal queued before it.
- `commitInt(field, text)` — a numeric text field: unparsable or empty text changes nothing; an `IntSettingField`
  clamps to its limits.
- Writes of several fields or with a rule: `setSocksCredentials`, `setGeoSources`, `setDns` (an empty custom address
  becomes `1.1.1.1`), `togglePackage` (the list of the mode current at write time), `setCoreEnabled` (refuses to
  disable the last available core, checked on the settings it writes to), `moveCoreUp`, `cleanGhostPackages`.

Screens call these through `writeSettings(context, ref, write)` (`settings_shared.dart`: a read-only profile shows a
snackbar) or the notifier directly; a section widget gets a `SettingModify` callback from its screen. `edit(change)`
takes a raw change and `save(settings)` replaces them whole, for flows that built all of them (the itest agent).
Two quick writes both land.

**Text fields** (`SetNumField`, `SetCredField` in `settings_shared.dart`: network settings, the subscription User-Agent) save once per edit — on submit, on focus loss
and when the screen closes with the field focused — not per key: every write stores the whole profile list and mirrors
the native flags. **Limits** are named in the models (`SettingLimits`): `AppSettings.socksPortLimits` (1024–65535),
`mtuLimits` (576–9000, as native `ConnectionParams`), `obsProbeIntervalLimits` (0–86400 s),
`MuxSettings.concurrencyLimits` (1–1024), `HeartbeatSettings.failureThresholdLimits` (1–10); their fields clamp a
typed value to them and `fromJson` clamps a stored or imported one — except a Mux concurrency below 1, an xray sentinel
(negative: Mux off for TCP / UDP; `xudpConcurrency: 0`: UDP the TCP way), which is kept as stored.

**Native flags.** `BootReceiver` reads `flutter.auto_start_on_boot`, `XrayVpnService` `flutter.automation_enabled`
from SharedPreferences: `SettingsService.mirrorNative` writes both after every change of the active settings (a save,
a switch, a refresh of the active profile). `logsEnabled` reaches native through the `setLogsEnabled` channel call.

**Migration.** Before, every field had its own SharedPreferences key (`SettingsService.load`, SOCKS login in secure
storage), and the profile held a copy. On the first `profileProvider` build without the `settings_in_profile` flag
those per-key settings become the active profile's (or the new default profile's); then the flag is set and the old
keys are no longer read.

## `AppSettings`

| Group | Fields |
|---|---|
| Local proxy | `socksPort`, `randomPort`, `randomCredentials`, `socksUser`, `socksPassword` (secure storage), `proxyOnly` |
| Split tunneling | `splitTunnelingEnabled`, `vpnMode` (`allExcept` / `onlySelected`), `excludedPackages`, `includedPackages`, `allowTethering` |
| Network | `enableUdp`, `allowIcmp` (default off), `blockQuic`, `ipv6Enabled` (default off: IPv6 is blocked on TUN), `mtu` (576–9000, default 1500), `sniffingEnabled` |
| DNS | `dnsMode` (`proxy` / `direct`), `dnsPreset`, `customDnsAddress`, `customDnsType`, `dnsQueryStrategy` |
| Routing | `routing` — [RoutingSettings](models.md#routingsettings): direction, geo codes, domain zones, sites, ad blocking |
| Anti-censorship | `tlsFingerprint`, `fragment`, `noise`, `mux` |
| Reliability | `killSwitchEnabled`, `heartbeat`, `obsProbeIntervalSec` |
| Cores | `coreOrder` (default xray Go → sing-box → xray-rust), `disabledCores` |
| Subscriptions | `hwidEnabled` (default on: some panels return HTML without `X-Hwid`), `subAutoRefresh`, `subAutoRefreshHours`, `subUserAgent` (empty = `AppConstants.subscriptionUserAgent`) |
| App | `autoConnect`, `autoStartOnBoot`, `automationEnabled` (Tasker broadcasts, off by default — [security](../security.md)), `showNotification`, `logLevel`, `logsEnabled`, `updateChannel`, `fontScale`, `geoipUrl`, `geositeUrl` |

**Invariant** (`test/core/app_settings_test.dart`): every field survives `toJson/fromJson` (the profile's form), and
an empty JSON or a fresh install gives the constructor defaults; the per-key reader of the migration keeps reading
every field of before (`SettingsService.save` writes that format for tests). Connection-relevant fields must also be added to `connectionFingerprint`
so a change on a live VPN shows the reconnect banner.

`coreOrder` (per-key: `core_order`); `CoreKind.parseOrder` drops unknown names and appends missing cores.

## Tuning (`xray_tuning.dart`)

Fragment and noise values are typed in by hand and an invalid range would stop the core from starting, so each has
`isValid`: the builder skips an invalid block and the screen shows a warning.

| Setting | Default | Meaning |
|---|---|---|
| `fragment.packets` | `tlshello` | split only the ClientHello, or a range `1-3` of first packets |
| `fragment.length` / `interval` | `100-200` / `10-20` | chunk bytes / pause ms |
| `noise.type` / `packet` / `delay` | `rand` / `50-100` / `10-20` | `rand`, `str`, `hex`, `base64`; for `rand` the packet is a length range |
| `mux.concurrency` / `xudpConcurrency` | 8 / 16 | sub-streams; XTLS Vision forces `-1` ([xray_config_builder](xray_config_builder.md)) |
| `mux.xudpProxyUDP443` | `reject` | `reject` / `allow` / `skip` for QUIC |

## Heartbeat (`heartbeat_settings.dart`)

Three independent choices — how to probe, where, and what to do on failure:

| Field | Default | Meaning |
|---|---|---|
| `probe` | `socks` | `socks` — HTTP through the local SOCKS; `xrayDelay` — measured inside the core; `passive` — no probes, only tun2socks metrics |
| `target` / `customUrl` | `cloudflare` | `cloudflare` / `google` / `apple` / `custom`; `url` falls back to Cloudflare when custom is empty |
| `failureThreshold` | 3 | failures in a row before acting, 1–10 |
| `failAction` | `reconnect` | `reconnect` the same server, or `switchConfig` — native sends `tunnel_dead` and Flutter picks a live config ([vpn_provider](vpn_provider.md)) |
| `switchSource` | `subscription` | candidates for `switchConfig`: `subscription` / `pinned` / `all` |

Presets are plain-HTTP `generate_204`-style URLs so the same URL works for both the SOCKS probe and the in-core
measurement; any 2xx counts as success. The SOCKS probe speaks plain HTTP, so a custom `https://` URL is measured
in the core instead. A core can override the probe (`CoreBackend.effectiveHeartbeatProbe`).

## Related

[VpnProvider](vpn_provider.md) · [Profiles](profiles.md) · [XrayConfigBuilder](xray_config_builder.md) ·
[Services](services.md)
