# VpnProvider — connection lifecycle

**Files:** `lib/providers/vpn_provider.dart`, `lib/providers/core_provider.dart`, `lib/core/cores/`

`VpnNotifier` orchestrates the connection on the Flutter side: picks the config and the core, builds the options,
calls the native service through [XrayEngine](xray_engine.md), and turns native events into state. Reconnects on
network change and heartbeat failure happen **natively** ([android_native](android_native.md)); Flutter only mirrors
them.

## State: `VpnState2`

| Field | Meaning |
|---|---|
| `connectionState` | `VpnState`: `disconnected`, `connecting`, `connected`, `disconnecting`, `error`, `blocked` |
| `stats` | `VpnStats`: traffic, speed, duration, history for the chart |
| `error` | reason for `error`/`blocked`: from Flutter (`_failConnect`, timeout) or from native (`error` field of the state event); shown on Home |
| `activeSocksPort/User/Password` | the tunnel's local SOCKS; `tunnelSocks` exposes it for the app's own downloads ([services](services.md#tunnelsocks)) |
| `appliedFingerprint` | `connectionFingerprint(settings, core:)` the session was started with |

`blocked` — the kill switch keeps the TUN sink after a drop. It is terminal like `error`; `connect()` from it is
allowed, `disconnect()` closes the sink. Native `reconnecting` maps to `connecting`.

Derived providers: `vpnConnectionStateProvider`, `vpnStatsProvider`, `pendingReconnectProvider` — `connected` and the
fingerprint of the current settings differs from `appliedFingerprint` → `ReconnectBanner`. Only connection-relevant
settings are fingerprinted (ports, credentials, proxy-only, UDP/ICMP/QUIC, MTU, IPv6, TLS fingerprint, logging,
sniffing, DNS, routing, split tunneling, kill switch, notification, core) — not theme, auto-connect, subscription or
geo settings. `tunnelSocksProvider` is not derived: `VpnNotifier` fills it ([services](services.md#tunnelsocks)).

## Choosing the core

`CoreResolver.resolve(config)` (`lib/core/cores/core_resolver.dart`) walks `[pinned VpnConfig.core,
...AppSettings.coreOrder]` and takes the first core that loads on the device (`availableCoresProvider`), isn't in
`disabledCores`, accepts the config (`CoreBackend.checkConfig`) and isn't blocked by the options
(`checkOptions(...).blocking`, e.g. xray-rust + proxy-only). Warnings don't affect the choice — otherwise enabling
Mux would silently move configs to another core. `CoreResolution` carries `backend` (null — no core can run it),
per-core `verdicts`, `pinned` and `reason`. Results are cached per `VpnConfig` instance (`Expando`): list rows call
`resolve` on every rebuild.

`activeCoreProvider` reports the core of the active config. When it changes while connected (order, disabling,
pinning, profile switch) `coreSwitchAction` decides: the config can't run any more → disconnect with an error;
it can → reconnect banner; disconnected → refresh or clear the saved quick-connect parameters.

## `connect({switching})`

1. Sets `connecting` synchronously (the button reacts in the same frame) and starts a **45 s** timeout → `error`.
2. Resolves the config: `effectiveConfigProvider` (the active config, or the best-latency config of the active
   subscription in auto mode — [config_provider](config_provider.md)); `config.validate()`.
3. Waits for the geosite index (`geositeIndexProvider`, which `coreResolverProvider` watches) and resolves the
   core (above); no core → `_failConnect(reason)`, native is not called. The choice and the skipped
   cores are logged with `source: core`.
4. `buildEngineOptions(settings, config, backend, …, geosite:)` (`lib/core/cores/engine_options.dart`, shared with
   quick-connect) with the resolver's geosite index ([geo_provider](geo_provider.md#geosite-index)): geosite codes
   missing from the file are left out and logged as a warning → `checkOptions`: `blocking` fails the connect,
   `warnings` go to the log.
5. `XrayEngine.connect(config, backend, options)`; stores the SOCKS credentials and `appliedFingerprint`.

**Attempt ownership.** A `connect()` that passes its entry guard (not busy, not connected unless switching) takes a
new attempt number; a later such `connect()`, any `disconnect()` or the 45 s connect timeout makes it stale. After
each await of the attempt
(notification permission, available cores, the native call) a stale attempt returns without calling native and
without writing `_connectedConfig`, SOCKS credentials, `appliedFingerprint` or an `error`. The attempt number goes
to native with `connect`; state events of the session it starts carry it back (`attempt`), and `getState` reports
it. Numbers start at the notifier's creation time (µs) and are raised above the native session's on every state
sync, so a notifier recreated with the UI never reuses one. While a Flutter connect waits for its outcome
(`_awaiting`, cleared by a settled state, a failure, the timeout or a disconnect), a state event tagged with another
attempt — an old session's start failing late — is dropped. A `getState` snapshot (startup or resume sync) not
tagged with the pending attempt is dropped too: another attempt's session, the service before the connect reached
it (a resume after the notification-permission dialog), or a natively started session the connect replaces; a
dropped snapshot re-arms the 45 s timeout if a reconnect report cancelled it. Untagged events (sessions started natively: tile, boot,
restart) and events outside a pending connect (native reconnects, a session surviving a UI restart) apply as they
come.

SOCKS credentials are random when `randomCredentials` is on **or** when the manual login is empty in TUN mode —
a password-less SOCKS on localhost would be an open proxy for every app. In proxy-only mode empty credentials
(noauth) are the user's choice.

**Hot switch.** `reconnectWithNewConfig()` while `connected` calls `connect(switching: true)`: native receives a
normal `ACTION_CONNECT` and rebuilds the session without closing TUN, so there is no leak window with the kill
switch. A failure before native is called keeps the old session running and shows the error. Used by the reconnect
banner, the config switch below and `selectConfig(config)` — the one rule for a picked config (configs list, server
picker): refused with the reason when no enabled core runs it; otherwise it becomes active, and a running or starting
session switches to it unless it already runs it. That decision is queued with the profile switches below and taken
when its turn comes, against what runs then, so overlapping selections end on the last one. `reconnectIfStale()` calls it only when needed: while
`connecting`, or when `connected` and the effective config isn't the running one (`runsConfig`) or the settings
fingerprint changed. A profile switch runs inside `duringProfileSwitch`: it changes settings and the server one
after the other, and the core resolved in between belongs to neither profile, so core changes are ignored while it
runs. Profile switches (body and reconciliation) and selections' reconciliations go through one queue, so a later one
never starts while the earlier one's connect is in flight; a selection's save itself isn't queued. After each switch the VPN follows the final state: a profile no core runs disconnects
with the error, as a core change does; otherwise a live tunnel goes through `reconnectIfStale`, an idle one through
the core-change handling if the core differs ([profiles](profiles.md#selected-server)).

`disconnect()` sets `disconnecting` with a **10 s** timeout that forces `disconnected`.

## Native events (`_handleEvent`)

All Dart code listens to one broadcast stream, `XrayEngine.events`: a second `receiveBroadcastStream()` on the same
channel would replace the first one's handler.

| `type` | Handling |
|---|---|
| `state` | `_onNativeState`; `connected` carries `socksPort/socksUser/socksPassword/connectedAtMs`, `error`/`blocked` carry `error` |
| `log` | `LogService` |
| `stats`, `statsHistory` | `VpnStats`; ignored outside `connected` so a late answer doesn't clear an error |
| `tunnel_dead` | `_runConfigSwitch` (only with `heartbeat.failAction = switchConfig`) |

A repeated `error`/`blocked` with a reason updates `state.error`: Flutter's timeout may fire before the native reason
arrives.

## Switching config on a dead tunnel (`_runConfigSwitch`)

The native heartbeat ran out of `failureThreshold` and sent `tunnel_dead`. Candidates come from
`heartbeat.switchSource` (`subscription` / `pinned` / `all`) without the current config, filtered to those some core
can run (`supportedCandidates`). Each is measured in parallel on its own core with `measureOutbound`: a temporary
core instance makes a real request to `heartbeat.url`. That is much stronger than the TCP ping, which reports
"alive" for a server whose port is open but whose protocol is blocked. No live candidate → only a log entry; the
service keeps reconnecting on its own cooldown. Otherwise → `setActiveConfig(best)` + `reconnectWithNewConfig()`.
Guarded by `_urltestRunning`; logged with `source: urltest`.

## Lifecycle

- **Start (`build`)** — `_syncOnStartup`: native state, credentials and `connectedAtMs` (the duration timer keeps the
  real start), the log file (`getLogs`), `appliedFingerprint` once profiles and cores are loaded (otherwise the
  banner would show falsely), then `refreshStaleSubscriptionsIfDue()`.
- **Resume** (`app.dart`) — `syncNativeState()` → restarts the stats poller, then `refreshStaleSubscriptionsIfDue()`
  (only now `tunnelSocksProvider` knows a VPN started from the tile, so subscriptions go through the tunnel).
- **Pause** — `pauseStatsPolling()`: no per-second channel calls in the background.
- **Stats** — `getStats` every second while connected; `getStatsHistory` only while the Home tab is visible
  (`setChartVisible`), incrementally by `(epoch, seq)`: a continuation is appended, anything else reloads the buffer.
- **Duration** — `_connectedAt ??= connectedAtMs`; reconnects keep it, an explicit disconnect resets it.

## Ping

`pingAllConfigs()` (button) and `pingStaleConfigs()` (on start; never pinged or older than 1 h) ping each
`address:port` once (`XrayEngine.pingConfig`: ICMP, then TCP) and store the results in one batch
(`batchUpdatePingResults`). Pings go directly, not through the tunnel.

## Related

[XrayEngine](xray_engine.md) · [ConfigProvider](config_provider.md) · [SettingsProvider](settings_provider.md) ·
[Android native](android_native.md) · [Architecture](../architecture.md#cores)
