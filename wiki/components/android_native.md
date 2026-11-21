# Android native layer

**Directory:** `android/app/src/main/kotlin/com/teapodstream/teapodstream/`

Receives commands from Flutter, owns the `VpnService` and TUN, runs the cores, reconnects on its own and sends events
back. It keeps working when the Flutter UI is gone (tile, boot, Tasker, service restart).

| File | Role |
|---|---|
| `MainActivity.kt` | MethodChannel handler (`com.teapodstream/vpn`), VPN permission, deep link intents |
| `PendingVpnStart.kt` | the connect waiting for the VPN-permission dialog: a newer connect replaces it (one dialog), `disconnect` cancels it; the dropped call is answered `SUPERSEDED` / `CANCELLED`. A dialog stays open until it answers, and its answer goes to the latest request |
| `XrayVpnService.kt` | the `VpnService`: session lifecycle, TUN, kill switch, network-change reconnect, heartbeat, stats, notification, log file |
| `core/` | `VpnCore` and its implementations (below), `TunOwnerPolicy`, `SocksCredentials`, `ProxyRedirect` |
| `VpnEventStreamHandler.kt` | EventChannel (`com.teapodstream/vpn/events`) singleton |
| `ConnectionParams.kt` | the session parameters (everything but the config and the SOCKS login): one JSON form for the `ACTION_CONNECT` Intent (`EXTRA_PARAMS`) and `last_connection_meta.json`; `fromJson` holds every default and limit (MTU 576–9000, heartbeat threshold 1–10), `fromArgs` maps Flutter's `connect` / `saveQuickConnect` arguments through it |
| `VpnTileService.kt` | Quick Settings tile |
| `BootReceiver.kt` | auto-start after boot (`autoStartOnBoot`, a saved config, not after an explicit disconnect) |
| `VpnCommandReceiver.kt` | Tasker/automation broadcasts `com.teapodstream.CONNECT` / `DISCONNECT`; ignored unless `automationEnabled` |
| `PrefixTcpProxy.kt` | local TCP proxy for Shadowsocks `?prefix=` (Outline) |
| `SocksHttpProbe.kt` | the heartbeat's `socks` probe: SOCKS5 handshake and an HTTP GET over raw sockets, probe-URL parsing |
| `SpeedHistory.kt` | ring buffer for the speed chart (`(epoch, seq)` increments) |
| `AppLocale.kt` | `Context.appString()` — native strings in the app's chosen language ([localization](localization.md)) |
| `ItestBridge.kt` | integration-test bridge, only in the `…itest` build ([tests](tests.md)) |
| `src/main/cpp/vpn_helper.cpp` | `nativeSetMaxFds`: raises `RLIMIT_NOFILE` before the cores start (not reachable from the public SDK) |

## Cores (`core/`)

The service never calls an engine directly — only `VpnCore`. TUN, kill switch, reconnect, heartbeat, notification and
split tunneling are shared.

| Core | Inside |
|---|---|
| `GoCore` | xray-core (`teapodcore.Teapodcore`) + teapod-tun2socks, local SOCKS5, UID filter `TunValidator` |
| `BoxCore` | sing-box (`startBox`) + teapod-tun2socks, like `GoCore` |
| `RustCore` | xray-rust (`org.xrayrust.mobile.XrayCore`) reads the TUN fd itself; UID filter via TUN admission |

`Tun2SocksCore` is the shared base of `GoCore`/`BoxCore` (tun2socks start/stop with 5/3 s deadlines, validator,
counters, log listener, `awaitStart` 30 s); subclasses only start/stop the engine. Per-core helpers: SOCKS credentials
from the saved config (`SocksCredentials.xray` / `.singBox`), the `?prefix=` address rewrite (`ProxyRedirect`).
`VpnCores.active` is the core of the current/last session. The core is picked by the `engine` extra (`go`, `rust`,
`box`; unknown → `go`). `getBinaryVersions` returns all core versions.

## Session lifecycle

All starts and stops run under `sessionLock`.

- **`ACTION_CONNECT`** (from Flutter): parameters → `ConnectionParams.save`; if a session is running this is a **hot
  switch** — `stopVpn(reconnecting=true)` keeps TUN as a sink until the new session is up, no leak window.
- **`ACTION_CONNECT_QUICK`** (tile, notification, boot, `reconnectInternal`, START_STICKY restart): parameters from
  `last_connection_meta.json`. Ignored while a session is running. Without a config or VPN permission
  (`abortQuickConnect`) the state is finished properly: kill switch → `blocked`, otherwise TUN is closed →
  `disconnected`, and the app opens.
- **`ACTION_DISCONNECT`**: `userRequestedDisconnect` (+ `user_disconnected.flag` on disk, so a restarted process doesn't
  reconnect), stop, close TUN (also an existing kill-switch sink), `disconnected`. Calls `ensureForeground()` first —
  it may arrive via `startForegroundService` into a fresh process.

**Starting.** `Builder.establish()` → TUN (random `10.x.x.x/32`, IPv4 default route; IPv6 only with `ipv6Enabled`;
MTU from settings) → `VpnCore.start` → `setConnected()`: atomic SOCKS credentials, `connectedAtMs`, connected event,
notification.

**Failure reason.** A failed start stores `lastError`; the `error`/`blocked` state event carries it as `error` and
`onListen` replays it.

## Kill switch and reconnect

- **TUN fd reuse.** `stopVpn(reconnecting=true)` keeps TUN open, and `startVpn(isReconnect=true)` passes the **same fd**
  to the core instead of a new `establish()` (tun2socks works on its own `dup`). No new VPN network agent, so no
  system "VPN active" notification on Android 15/16 and no connectivity flap for apps; traffic during the reconnect
  goes into the sink — no leak even without the kill switch. A user `ACTION_CONNECT` always establishes anew.
- **Retries.** A failed reconnect retries `CONNECT_QUICK` up to `MAX_RECONNECT_ATTEMPTS` (3) with linear backoff
  (5 s × attempt); the old fd survives the retries. Final failure with kill switch → sink stays, state `blocked`.
  A failed manual connect keeps a sink only if there already was one — a broken config must not lock the network.
- **`blocked`.** The kill switch keeps TUN with `setUnderlyingNetworks(emptyArray())` after an unexpected drop: traffic
  enters TUN and nobody reads it. Notification and tile show it; tapping the tile reconnects.

## Network changes

A `NetworkCallback` tracks the physical network (`findPhysicalNetwork`: the process's own network, since the app is
excluded from TUN; otherwise VALIDATED first, then Wi-Fi) and sets it as the underlying network.

- A change of the physical network (`onAvailable`/`onLost` compare the snapshot before and after
  `updateUnderlyingNetworks`, both event orders) → `scheduleNetworkChanged(switched=true)` → 2 s debounce →
  `reconnectInternal()`: `stopVpn(reconnecting=true)`, state `reconnecting`, wait up to 30 s for direct internet
  (`hasDirectInternet`: TCP to 8.8.8.8:53 bound to the physical network), then `CONNECT_QUICK`. A timed wakelock
  (40 s) covers the cycle. Takes ~3–5 s.
- Back on the network the session was connected on → no reconnect (the core's sockets are still alive).
- Loss of `VALIDATED` without a network change (captive portal, outage) forces a reconnect.
- **First 5 s after connecting:** Android briefly drops VALIDATED on mobile data when a VPN comes up. Events in this
  window aren't acted on immediately; when it ends the physical network is compared with the connect network.
- **`onLost`** immediately calls `forceTunCloseAllConnections()`: stale gVisor TCP connections survived short blips
  and froze apps (Telegram) in a way the heartbeat can't see.
- Reconnects are bound to their session (`lastConnectedMs`): a late timer never touches a newer session.

## Heartbeat

A background thread probes every 15 s (60 s with the screen off; skipped in deep Doze) and acts after
`heartbeatThreshold` failures in a row.

- **Probe** (`runProbe`): `socks` — HTTP through the local SOCKS to `heartbeatUrl`, any 2xx (`SocksHttpProbe`; it
  offers user/password only when the session has SOCKS credentials, and fails at once if the inbound demands them
  without any); `xrayDelay` — measured
  inside the core (also used for a custom `https://` URL); `passive` — none.
- **Passive success:** if TUN received data within the interval, the tunnel is alive and the radio isn't woken.
- **Warm-up** after a reconnect: probes every 15 s, failures don't count until the first success, hard limit 30 s
  (outbounds connect lazily; DNS + TLS on fresh LTE can be slow).
- **Exhausted** (`handleHeartbeatExhausted`): `reconnect` → `reconnectInternal()`; `switchConfig` → `tunnel_dead`
  event to Flutter ([vpn_provider](vpn_provider.md)); if nothing happens within 45 s (app killed, no live candidate) →
  plain reconnect.
- **Watchdogs:** no TUN RX for 120 s with ≥ 2 active connections → reconnect; more than 200 active tun2socks
  connections (a gVisor state leak) → reconnect; on screen-on / Doze exit a TUN idle ≥ 120 s triggers a probe, not a
  blind reconnect (idle ≠ dead); ≥ 3 skipped probes for lack of internet, then a failure → reconnect at once.
- The SOCKS probe bypasses gVisor, so it can pass while app connections hang — that's what the watchdogs and the
  `onLost` force-close are for.

## Split tunneling and owner validation

`allExcept` → `addDisallowedApplication`, `onlySelected` → `addAllowedApplication` (the app itself is always outside
the tunnel). On top, tun2socks checks each new flow's owner UID (`getConnectionOwnerUid`) via `TunOwnerPolicy`
(shared by all cores): UID `-1` is either tethering or an excluded app that bound a socket to `tun0`
(`SO_BINDTODEVICE`) — indistinguishable. So `-1` is always blocked in `onlySelected`, and in `allExcept` when the
exclusion list is non-empty and `allowTethering` is off. Exception: DNS to the TUN DNS address on port 53 (on Android
10 resolver sockets belong to netd). A failing lookup allows. [security](../security.md)

## Stats, notification, logs

- **Stats** thread: every 1 s with the screen on (counters, history for the chart, notification), every 10 s with it
  off (counters only — the chart shows a gap). Flutter polls `getStats` / `getStatsHistory`.
- **Notification** is always present while the service lives (otherwise Android kills the process); `showNotification`
  chooses full (`vpn_service`) or minimal (`vpn_service_minimal`). Updates are deduplicated, at most every 5 s, not with
  the screen off. All notifications come from `baseNotification()` (`setOnlyAlertOnce`, fixed `when`,
  `FOREGROUND_SERVICE_IMMEDIATE`). Intermediate "Connecting…/Disconnecting…" only once per state.
- **Log file** `filesDir/vpn_log.txt`, lines `epochMs|level|message`, buffered (flush at 8 KB, every 5 s, immediately
  for warnings/errors, before reads); cleared on a user connect, kept across reconnects (previous one in
  `vpn_log.prev.txt`). Core logs arrive through `registerLogListener`. With `logsEnabled` off only warnings and errors
  are written; the flag is mirrored in native `vpn_prefs` so it works without Flutter.

## EventChannel (`VpnEventStreamHandler`)

Holds the application context weakly. `onListen` replays the current state — with SOCKS credentials and
`connectedAtMs` for `connected`, with `error` for `error`/`blocked` — so a restarted UI catches up. State changes
also update the tile and intermediate notifications. Events: `state`, `log`, `stats` (replay only), `statsHistory`,
`tunnel_dead`, `deeplink`.

## Tile

Disconnected: label "TeapodStream", subtitle = the config the tile will connect (`tile_config_name` in `vpn_prefs`,
saved with the quick-connect parameters). Active / transition / kill switch: label = config name, subtitle = status.
Tap: disconnect when connected or connecting, otherwise `CONNECT_QUICK`; `unlockAndRun` on the lock screen.

## PrefixTcpProxy

Outline Shadowsocks servers expect each TCP connection to start with fixed bytes. The service starts a proxy on
loopback that connects to the server, sends the prefix and relays both ways; the core's config points at it
(`ProxyRedirect`). Accepts only its own UID (proxy-only mode, where the lookup throws `SecurityException`, is allowed);
server dial timeout 10 s.

## Manifest

`INTERNET`, `ACCESS_NETWORK_STATE`, `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_SPECIAL_USE` (service type
`specialUse`), `RECEIVE_BOOT_COMPLETED`, `POST_NOTIFICATIONS`, `CAMERA` (QR), `QUERY_ALL_PACKAGES`,
`REQUEST_INSTALL_PACKAGES`, `WAKE_LOCK`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`. `allowBackup=false` and
`dataExtractionRules` exclude everything. `FileProvider` for update APKs. The VPN service is not exported; the
activity, tile and command receiver are (the receiver checks `automationEnabled`).

## Related

[VpnProvider](vpn_provider.md) · [XrayEngine](xray_engine.md) · [teapod-core](teapod_core.md) ·
[teapod-tun2socks](teapod_tun2socks.md) · [Security](../security.md)
