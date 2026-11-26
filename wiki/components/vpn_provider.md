# VpnProvider — connection lifecycle

**Files:** `lib/providers/vpn_provider.dart`, `lib/providers/vpn_session.dart`, `lib/providers/core_provider.dart`,
`lib/core/cores/`; around the connection: `vpn_stats_provider.dart`, `auto_switch_provider.dart`, `ping_provider.dart`,
`native_logs_provider.dart`

`VpnNotifier` orchestrates the connection on the Flutter side: picks the config and the core, builds the options,
calls the native service through [XrayEngine](xray_engine.md), and turns native events into state; it only connects,
disconnects and mirrors the session (stats, the config switch, pings and native logs live in their own providers,
below). Reconnects on
network change and heartbeat failure happen **natively** ([android_native](android_native.md)); Flutter only mirrors
them.

## State: `VpnState2`

| Field | Meaning |
|---|---|
| `connectionState` | `VpnState`: `disconnected`, `connecting`, `connected`, `disconnecting`, `error`, `blocked` |
| `connectedAt` | when the running session connected (native's `connectedAtMs`, else the first `connected` seen); reconnects keep it, an explicit disconnect or a switch resets it |
| `error` | `AppMessage` ([localization](localization.md)), the reason for `error`/`blocked` (or a refused switch over a running session): a Flutter failure (a code, or a core's or validation's reason) or native's `error` as text (below); Home localizes it |
| `activeSocksPort/User/Password` | the tunnel's local SOCKS from the `connected` snapshot; `tunnelSocks` exposes it for the app's own downloads ([services](services.md#tunnelsocks)) |
| `appliedFingerprint` | `connectionFingerprint(settings, core:)` the session was started with |

`blocked` — the kill switch keeps the TUN sink after a drop. It is terminal like `error`; `connect()` from it is
allowed, `disconnect()` closes the sink. Native `reconnecting` maps to `connecting`.

## Session (`VpnSession`)

`lib/providers/vpn_session.dart`. The notifier keeps one immutable `VpnSession`: the last native snapshot
(`NativeSession`, [xray_engine](xray_engine.md)), what Flutter waits for (`PendingConnect(attempt)` or
`PendingDisconnect`) and a `SessionFailure(reason, attempt)` Flutter found itself (a connect refused before native,
rejected by it or timed out; a session stopped because no core runs its config). `connectionState` and `error` are
its pure `view`; `_setSession` is the only writer, and derives the rest (SOCKS login, `connectedAt`).
A refusal (before native, or rejected by it) leaves native as it is; a *stopping* failure (the connect timeout, a
session no core runs) asks native to stop that session.

- **`onNative(snapshot, poll:)`** (pure). Every snapshot becomes native's latest state, but while a connect waits a
  `foreign` one doesn't settle it: another attempt's (an old session's late report — also what a refused switch leaves
  running) or an untagged poll (`getState` may predate the connect reaching the service); an untagged event is a
  natively started session that replaced the connect. A connect waits through `connecting`/`disconnecting` of its
  attempt, a disconnect through `disconnecting`. A refusal stays while native reports the same snapshot. A stopping
  failure stays through the stop (its reports carry native's last Flutter connect, not the stopped session's tag) and
  the stopped session's own reports, even a late `connected`; another session or the kill switch's sink replaces it.
- **`view`**: a pending connect → `connecting`, a pending disconnect → `disconnecting` (with a failure's reason);
  a failure → `error` with it (native's own reason wins when native is in `error`), or `connected` with it when a
  refusal leaves the old session running; otherwise native's state, `error` with native's reason or the generic one.
- **One deadline** for what is pending: 45 s for a connect (→ failure `vpnConnectTimeout`, a new attempt id so its late
  answer is stale, native `disconnect`), 10 s for a disconnect (→ taken as off). A `reconnecting` report of the
  pending connect drops the deadline (a native restart can outlast it; the service ends it itself); its `connecting`
  (the start after a switch's stop) and a foreign poll arm it again.

Derived providers: `vpnConnectionStateProvider`, `pendingReconnectProvider` — `connected` and the
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

`activeCoreProvider` reports the core of the active config. The notifier listens to one derived value of what
would run now: the effective config (its ping results aside), the connection settings (`connectionFingerprint`) and
that core. Whenever it changes, `coreSwitchAction` decides: while connected or connecting, a config no core can run
anymore → disconnect with an error; otherwise the session keeps running what it started with (the reconnect banner
shows only for changed connection settings or core, `pendingReconnectProvider`); while off → save the quick-connect
parameters, or clear them when no core runs the config or `validate()` refuses it. The tile, boot and automation start from those, so they follow every change of the
effective config — a selection, a link edit, a subscription refresh, auto mode, a ping that changes the best
config — and of the connection settings. They are built as a connect builds them (after the geosite index is
loaded). A session that ends saves again (it may have run older settings); native refuses while a session runs, so
native's own off report saves again too: a timed-out connect shows `error` before native stops.

## `connect({switching})`

1. Sets `PendingConnect` synchronously (the button reacts in the same frame) with the **45 s** deadline.
2. Resolves the config: `effectiveConfigProvider` (the active config, or the best-latency config of the active
   subscription in auto mode — [config_provider](config_provider.md)); `config.validate()`.
3. Waits for the geosite index (`geositeIndexProvider`, which `coreResolverProvider` watches) and resolves the
   core (above); no core → `_failConnect(reason)`, native is not called. The choice and the skipped
   cores are logged with `source: core`.
4. `buildEngineOptions(settings, config, backend, …, geosite:)` (`lib/core/cores/engine_options.dart`, shared with
   quick-connect) with the resolver's geosite index ([geo_provider](geo_provider.md#geosite-index)): geosite codes
   missing from the file are left out and logged as a warning → `checkOptions`: `blocking` fails the connect,
   `warnings` go to the log.
5. `XrayEngine.connect(config, backend, options)`; stores `appliedFingerprint`.

**Attempt ownership.** `connect()` is refused while `disconnecting`, and while `connected` or `connecting` unless it
switches (`reconnectWithNewConfig`). One that passes takes a new attempt id; a later such `connect()`, any `disconnect()` or the 45 s deadline makes it stale. After each await of
the attempt (notification permission, available cores, the native call) a stale attempt returns without calling native
and without writing `_connectedConfig`, `appliedFingerprint` or a failure. The id goes to native with `connect`, and
the session's snapshots carry it back (`attempt`), so `onNative` can tell a connect's own outcome. Ids are random and
only compared for equality: native keeps a session's id for the life of the process, and a notifier recreated with
the UI must not reuse it.

SOCKS credentials are random when `randomCredentials` is on **or** when the manual login is empty in TUN mode —
a password-less SOCKS on localhost would be an open proxy for every app. In proxy-only mode empty credentials
(noauth) are the user's choice.

**Hot switch.** `reconnectWithNewConfig()` while `connected` or `connecting` calls `connect(switching: true)`: native
receives a normal `ACTION_CONNECT` and replaces the running or starting session ([android_native](android_native.md#session-lifecycle)),
a running one without closing TUN, so there is no leak window with the kill switch. A failure before native is
called keeps the old session running and shows the error. Used by the reconnect
banner, the config switch below and `selectConfig(config)` — the one rule for a picked config (configs list, server
picker): refused with the reason when no enabled core runs it; otherwise it becomes active, and a running or starting
session switches to it unless it already runs it (with the VPN off the change reaches quick connect, above). Adding a
config selects it the same way. That decision is queued with the profile switches below and taken
when its turn comes, against what runs then, so overlapping selections end on the last one. `reconnectIfStale()` calls it only when needed: while
`connecting`, or when `connected` and the effective config isn't the running one (`runsConfig`) or the settings
fingerprint changed. A profile switch runs inside `duringProfileSwitch`: it changes settings and the server one
after the other, and what is resolved in between belongs to neither profile, so the listener above ignores changes
while it runs. Profile switches (body and reconciliation) and selections' reconciliations go through one queue, so a later one
never starts while the earlier one's connect is in flight; a selection's save itself isn't queued. After each switch the VPN follows the final state: a profile no core runs disconnects
with the error, as a core change does; otherwise a live tunnel goes through `reconnectIfStale`, an idle one saves the
new profile's server and settings for quick connect ([profiles](profiles.md#selected-server)).

`disconnect()` sets `PendingDisconnect` with the **10 s** deadline, after which the session is taken as off.

## Native events (`_handleEvent`)

All Dart code listens to one broadcast stream, `XrayEngine.events`: a second `receiveBroadcastStream()` on the same
channel would replace the first one's handler.

| `type` | Handling |
|---|---|
| `state` | `NativeSession.parse` → `onNative` (above); `connected` carries `socksPort/socksUser/socksPassword/connectedAtMs`, `error`/`blocked` carry `error` |
| `log` | `LogService` |
| `statsHistory` | `vpnStatsProvider` (below) |
| `tunnel_dead` | `autoSwitchProvider` (below; only with `heartbeat.failAction = switchConfig`) |

A repeated `error`/`blocked` with a reason updates `state.error`: Flutter's timeout may fire before the native reason
arrives.

## Switching config on a dead tunnel (`autoSwitchProvider`)

The native heartbeat ran out of `failureThreshold` and sent `tunnel_dead`. Candidates come from
`heartbeat.switchSource` (`subscription` / `pinned` / `all`) without the failed config — the one the session runs
(`runningConfig`: in auto mode a ping may have moved the effective config meanwhile), filtered to those some core
can run (`supportedCandidates`). Each is measured in parallel on its own core with `measureOutbound`: a temporary
core instance makes a real request to `heartbeat.url`, with the options a connect builds (`buildEngineOptions`).
That is much stronger than the TCP ping, which reports "alive" for a server whose port is open but whose protocol is
blocked. No live candidate → only a log entry; the service keeps reconnecting on its own cooldown. Otherwise
`VpnNotifier.switchDeadTunnel` applies the switch in the queue of selections and profile switches; it is dropped when
by then the session runs another config. In auto mode with the best candidate in the auto subscription,
auto mode stays: the subscription's ping results become the measurement, by config (`setLatencies`) — a config that
didn't answer or wasn't probed (the dead one, other configs with the `pinned` source) has none until the next ping —
so its best is the live config. Otherwise the best becomes the active config, as a selection makes it. A live session is
then rebuilt on the chosen config. One run at a time; logged with `source: urltest`. The app shell creates it at start; it listens to the events itself.

## Lifecycle

- **Sync** — `syncNativeState()`, the one path for start and resume: `getState` → `onNative(poll: true)`; a
  `connected` session without a Flutter connect (tile, boot, a UI restart) takes the current settings as
  `appliedFingerprint` once profiles and cores are loaded (otherwise the banner would show falsely). The SOCKS login
  and `connectedAtMs` (the duration timer keeps the real start) come with the snapshot; `ipInfoProvider` reads them
  from the notifier.
- **Start** — `build` runs the sync (`synced` completes after it, also on failure); the app shell restores the log
  file (`nativeLogsProvider.restore`: resyncs `logsEnabled`, `getLogs`) and, after `synced`, runs
  `ConfigNotifier.refreshStaleIfDue()`.
- **Resume** (`app.dart`) — the sync, then `refreshStaleIfDue()` (only now `tunnelSocksProvider` knows a VPN started
  from the tile, so subscriptions go through the tunnel); the stats polling resumes.

## Stats (`vpnStatsProvider`)

`VpnStatsNotifier` follows `connected`: `getStats` every second while connected, the duration from `connectedAt`;
reset when the session ends; a late answer after a drop is ignored. `pause()` / `resume()` from the app's lifecycle
(no per-second channel calls in the background). The chart's `getStatsHistory` is pulled only while the Home tab is
visible (`setChartVisible`), incrementally by `(epoch, seq)`: a continuation is appended, anything else reloads the
buffer (at most 300 points); `statsHistory` events go the same way.

## Ping

`pingProvider` (its state: a ping is running; one at a time): `pingAll()` (the configs screen's button) and
`pingStale()` (on start and after configs are added; never pinged or older than 1 h) ping each `address:port` once
(`XrayEngine.pingConfig`: ICMP, then TCP) and store the results in one batch (`batchUpdatePingResults`). Pings go
directly, not through the tunnel.

## Native logs

`nativeLogsProvider` (`NativeLogs`): the native log file — `restore()` at start, `setLogsEnabled`, `getLogFilePath`
(export), `clear`, `dumpTunnelDiag` (a tun2socks snapshot into the app log) for the logs screen.

## Related

[XrayEngine](xray_engine.md) · [ConfigProvider](config_provider.md) · [SettingsProvider](settings_provider.md) ·
[Android native](android_native.md) · [Architecture](../architecture.md#cores)
