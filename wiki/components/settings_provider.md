# SettingsProvider — app settings

**Files:** `lib/providers/settings_provider.dart`, `lib/core/services/settings_service.dart` (`AppSettings`),
`lib/core/models/xray_tuning.dart`, `lib/core/models/heartbeat_settings.dart`, `lib/core/models/routing_settings.dart`

`SettingsNotifier` (`AsyncNotifier<AppSettings>`) loads `AppSettings` through `SettingsService` and saves every
change. `save()` waits for the active profile: a read-only profile ignores the change, otherwise the profile's
snapshot is updated too ([profiles](profiles.md)). `cleanGhostPackages` drops uninstalled apps from the split
tunneling lists.

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

**Invariant** (`test/core/app_settings_test.dart`): every field survives `toJson/fromJson` and
`SettingsService.save/load`, and an empty JSON or a fresh install gives the constructor defaults. A new field
without its storage key fails the test. Connection-relevant fields must also be added to `connectionFingerprint`
so a change on a live VPN shows the reconnect banner.

`coreOrder` is stored as `core_order`; `CoreKind.parseOrder` drops unknown names and appends missing cores.

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
