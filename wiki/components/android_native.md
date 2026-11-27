# Android native layer

**Directory:** `android/app/src/main/kotlin/com/teapodstream/teapodstream/`

Receives commands from Flutter, owns the `VpnService` and TUN, runs the cores, reconnects on its own and sends events
back. It keeps working when the Flutter UI is gone (tile, boot, Tasker, service restart).

| File | Role |
|---|---|
| `MainActivity.kt` | wires the channels (`com.teapodstream/vpn` to both handlers below, the event channel, itest), deep link intents, the VPN-permission result |
| `VpnChannelHandler.kt` | the VPN methods of `com.teapodstream/vpn` (Dart `XrayEngine`): connect with the VPN permission, disconnect, quick-connect save / clear (`QuickConnectRequests`: in call order on one thread, dropped when a session started since the check — `XrayVpnService.sessionStarts`), state, stats, ping, `measureOutbound`, logs |
| `PlatformChannelHandler.kt` | the platform methods (Dart `PlatformService`): available cores, versions, binaries, apps and icons, files dir, ABI, IP country, device id / info, APK install; `BatteryOptimization` — the exemption prompt (once, on connect) and its settings |
| `ChannelWork.kt` | a channel method's blocking work runs on a pool (`io`; `ping` 8 and `measure` 4 threads bound the bursts; `quickConnect` — one thread, call order) and is answered on the main thread, a throw as `ERROR`; `ConnectArgs` — the parsed `connect` / `saveQuickConnect` arguments |
| `PendingVpnStart.kt` | the connect waiting for the VPN-permission dialog: a newer connect replaces it (one dialog), `disconnect` cancels it; the dropped call is answered `SUPERSEDED` / `CANCELLED`. A dialog stays open until it answers, and its answer goes to the latest request |
| `XrayVpnService.kt` | the `VpnService`: session lifecycle, TUN, kill switch, the stats thread; wires the classes below |
| `Heartbeat.kt` | the heartbeat thread and the probe on wake: probes the tunnel and applies `HeartbeatPolicy`'s actions |
| `NetworkWatcher.kt` | the physical network under the session: the `NetworkCallback`, the underlying network, reconnect plans of `NetworkChangePolicy` |
| `ScreenWatcher.kt` | screen and Doze state (the heartbeat and stats cadence), the wake callbacks |
| `ServiceNotifications.kt` | the notification: intermediate on a state change (also from the tile), foreground, speeds, the kill switch's block |
| `ServiceLog.kt` | the log file, its buffer and rotation, logcat and the Flutter log events |
| `SessionStats.kt` | the session's traffic totals, speeds and the chart history (`getStats`, `getStatsHistory`); a sample of a stopped session (its generation) is ignored |
| `SessionSnapshot.kt` | `SessionState` (the state names Flutter sees) and the immutable `SessionSnapshot`: its map for Flutter, the itest marker, the pure transition `moved` |
| `core/` | `VpnCore` and its implementations (below), `TunOwnerPolicy`, `SocksCredentials`, `ProxyRedirect` |
| `VpnEventStreamHandler.kt` | EventChannel (`com.teapodstream/vpn/events`) singleton |
| `ConnectionParams.kt` | the session parameters (everything but the config and the SOCKS login): one JSON form for the `ACTION_CONNECT` Intent (`EXTRA_PARAMS`) and the stored parameters; `fromJson` holds every default and limit (MTU 576–9000, heartbeat threshold 1–10) and parses the choices into enums once (`VpnMode`, `HeartbeatProbe`, `HeartbeatAction`, `CoreKind`; JSON keeps their ids; missing or unknown → the default, unknown with a logcat line), `fromArgs` maps Flutter's `connect` / `saveQuickConnect` arguments through it |
| `QuickConnectStore.kt` | the quick-reconnect data in `filesDir`, its only reader and writer: the core config (`xray_config.json`), `ConnectionParams` (`last_connection_meta.json`), the SOCKS login (`socks_creds.json`), the tile's config name (`tile_config_name.txt`) and the user-off flag (`user_disconnected.flag`); writes go through a temp file and a rename. `quickStart()` builds the `StartRequest` (config, params, SOCKS login — the stored one, else read from the config — the Flutter `attempt` it answers, 0 for a native start, `reconnect` and the tile's config name — Flutter's, or the stored one read with the config — which the session's save writes back with it) that `startVpn(request)` takes |
| `VpnTileService.kt` | Quick Settings tile; not an active tile — the system asks for its state whenever it is shown, so a force-stopped process leaves no stale "connected" |
| `BootReceiver.kt` | auto-start after boot (`autoStartOnBoot`, a saved config, not after an explicit disconnect) |
| `VpnCommandReceiver.kt` | Tasker/automation broadcasts `com.teapodstream.CONNECT` / `DISCONNECT`; ignored unless `automationEnabled` |
| `PrefixTcpProxy.kt` | local TCP proxy for Shadowsocks `?prefix=` (Outline) |
| `SessionReconciler.kt` | the one desired session state (`Desired.Off(attempt)` / `Desired.On(request, id)`) and the thread that brings the session to it: commands, `onRevoke`, reconnects and retries only replace it (`set`, or `replace` while an expected state is still wanted); a run loops the pure `nextAction(desired, actual)` (stop / close the sink / start / settled) through `SessionDriver` |
| `HeartbeatPolicy.kt` | the heartbeat's decisions, pure and JVM-tested: observations (probe ok / failed, no direct internet, dead or leaking tun2socks, TUN idle, warm-up deadline) → an action (none, log, retry now, reconnect, ask Flutter to switch); the thread in `Heartbeat` only probes and applies it |
| `NetworkChangePolicy.kt` | network-change scheduling, pure and JVM-tested: an event and the time since connect → a plan (delay, check the network or reconnect); when the plan fires → reconnect or not |
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
The session's core rides in `SessionSnapshot.core` (kept through the stop until the next session): the service runs that session on it, tunnel diagnostics and the `xray` version read it; there is no global active core. The core is picked by `ConnectionParams.engine` (`go`, `rust`, `box`; unknown → `go`). `getBinaryVersions` returns all core versions.

## Session lifecycle

The service keeps one desired state, `SessionReconciler.desired`: `Off(attempt)` or `On(request, id)` (a retry or a
reconnect of the same config is a new `id`). `ACTION_CONNECT`, `ACTION_DISCONNECT`, the quick starts, `onRevoke`,
the network-change reconnect and the start retries only replace it; one thread brings the session to it by looping
`nextAction(desired, actual)`: stop the running session (for a new one: TUN stays a sink), close a sink, start, or
settled. A command replaced before its turn never acts — only the latest state exists — and a long start isn't
interrupted: the loop then stops it and starts what is wanted now. A reconnect or a retry applies only while the
state it was made for is still the desired one (`replace`). Before a stop or a start, `sessionAttempt` takes the
desired state's attempt (`own`); an `Off` that is reached reports `disconnected` under its attempt (`settled`). A reconnect replaces only the
desired state its session was started for (`connectedDesired`), and a start replaced before it began does nothing.

- **`ACTION_CONNECT`** (from Flutter): only the notification type is taken before the state is set (when no session runs);
  `startVpn(StartRequest)` takes the parameters (`useParams`: the heartbeat, tethering and notification settings are
  read from them) once it owns the session, and stores them, the config it runs and its SOCKS login together with the
  tile's config name, then refreshes the tile (`QuickConnectStore.save`: one step under a lock shared with the activity's save and the quick-start read; the old login and
  config are removed first, so an interrupted save leaves nothing to quick-start rather than a mix of two connections; a failed save is logged
  and costs only the quick start, not the session). Before the old session stops, `sessionAttempt` takes Flutter's
  connect attempt (`EXTRA_ATTEMPT`), and every snapshot the session
  publishes carries it as `attempt` (quick starts reset it to 0 — untagged); if a session is running this is a **hot
  switch** — `stopVpn(reconnecting=true)` keeps TUN as a sink until the new session is up, no leak window.
- **`ACTION_CONNECT_QUICK`** (tile, the `blocked` notification, boot) and the START_STICKY restart
  start from one request, `QuickConnectStore.quickStart()` (so do reconnects and retries; without a stored one they
  reuse the session's own request). `ACTION_CONNECT_QUICK` is ignored while a session is wanted and running or being
  started (a wanted one that failed or ended can be started again). The restart starts nothing while any session is
  wanted (also a failed one) or after the user turned the VPN off. Without a config or VPN permission
  (`abortQuickConnect`) the state is finished properly: the kill switch of the session holding the sink (not the
  stored params, which a failed save may have removed) → `blocked`, otherwise TUN is closed →
  `disconnected`, and the app opens.
- **`ACTION_DISCONNECT`**: `setUserOff(true)` — the store's flag on disk, so a restarted process doesn't reconnect;
  publishes `disconnecting` and sets `Off`: stop, close TUN (also an existing kill-switch sink), `disconnected`. A
  connect or quick start received after it replaces it, and its session owns the state. If the stop hasn't finished in
  5 s while this `Off` is still wanted, the main thread closes the sink and reports anyway. Its states carry the attempt
  of the last `ACTION_CONNECT` received (`SessionReconciler.lastAttempt`): a connect Flutter still waits
  for, cancelled from the notification or the tile, gets its answer. Calls `ServiceNotifications.foreground()` first —
  it may arrive via `startForegroundService` into a fresh process.

**Starting.** `Builder.establish()` → TUN (random `10.x.x.x/32`, IPv4 default route; IPv6 only with `ipv6Enabled`;
MTU from settings) → `VpnCore.start` → `setConnected()`: publishes the `connected` snapshot (SOCKS credentials,
`connectedAtMs`), notification.

**Failure reason.** A failed start passes its reason to `stopVpn(error = …)`; the `error`/`blocked` snapshot carries it
as `error` until the session moves to another state.

## Session snapshot

The state is one immutable `SessionSnapshot` in the service's companion (`XrayVpnService.snapshot`): `SessionState`,
`attempt`, SOCKS port and login, `connectedAtMs`, `error`. Only `publish()` changes it, and it reports every change
in one place: the `state` event, the itest marker, the tile, the intermediate notification and the automation
broadcast (`com.teapodstream.STATE_CHANGED`, only with `automationEnabled`, without the SOCKS port). A new snapshot
comes from `SessionSnapshot.moved` (any state but `connected`: drops the SOCKS login, keeps `error` only for
`error`/`blocked`) or `SessionSnapshot.connected`. Reading it has no side effects: `getState`, the `onListen` replay,
the tile and the `saveQuickConnect` / `clearQuickConnect` guards read the same snapshot.

The `state` event (`toMap`): `type: state`, `value` (the wire name), `attempt` only when Flutter started the session,
`socksPort` / `socksUser` / `socksPassword` / `connectedAtMs` only for `connected`, `error` for every other state.
`getState` answers with the same map, so Dart parses both with one parser (`NativeSession.parse`,
[xray_engine](xray_engine.md)).

**Dead TUN.** `connected` in TUN mode while tun2socks no longer runs (the fd closed externally, e.g. during a phone
call, without `onRevoke()`): the stats thread calls `reconnectInternal()`, which publishes `reconnecting` — no
phantom connection, and the heartbeat's own tun2socks check stays as a fallback.

## Kill switch and reconnect

- **TUN fd reuse.** `stopVpn(reconnecting=true)` keeps TUN open, and `startVpn` of a request with `reconnect = true`
  whose `ConnectionParams` are the ones the TUN was built with (`tunParams`) passes the **same fd** to the core
  instead of a new `establish()` (tun2socks works on its own `dup`). No new VPN network agent, so no system "VPN
  active" notification on Android 15/16 and no connectivity flap for apps; traffic during the reconnect goes into the
  sink — no leak even without the kill switch. With other params (a failed manual connect stored new ones) the
  reconnect establishes a new TUN, which replaces the old fd as the sink. A user `ACTION_CONNECT` always establishes
  anew.
- **Retries.** A failed reconnect asks, after a linear backoff (5 s × attempt), for a new `On` of the stored session —
  only while the failed one is still wanted — up to `MAX_RECONNECT_ATTEMPTS` (3). A retry keeps the TUN held at the failure only while the stored params equal `tunParams`;
  otherwise it establishes a new TUN and closes the held one. Final failure with kill switch → sink stays, state
  `blocked`.
  A failed manual connect keeps a sink only if there already was one — a broken config must not lock the network.
- **`blocked`.** The kill switch keeps TUN with `setUnderlyingNetworks(emptyArray())` after an unexpected drop: traffic
  enters TUN and nobody reads it. Notification and tile show it; tapping the tile or the notification's Connect
  reconnects.
- **Off → the service stops.** A published `disconnected` / `error`, and every finished reconciler run while the
  state is off, post `stopIfIdle` to the main thread: with no session running, no TUN held and no change waiting or
  running (`serviceIdle`, `SessionReconciler.busy`; a disconnect still reports its end) the service
  calls `stopSelf(lastStartId)` (the system ignores it if a newer intent is on its way) and its notification goes
  away. So a user disconnect, a failed manual connect without a sink, `onRevoke` and a START_STICKY restart with
  nothing to start leave no service behind; `blocked` keeps it. The tile, boot and automation start it again.

## Network changes

The decisions below are `NetworkChangePolicy`'s; `NetworkWatcher` tracks the networks and runs the plan on its handler, and `XrayVpnService` applies the reconnect it asks for to the session.
`NetworkWatcher`'s `NetworkCallback` tracks the physical network (`physical()`: the process's own network, since the app is
excluded from TUN; otherwise VALIDATED first, then Wi-Fi) and sets it as the underlying network.

- A change of the physical network (`onAvailable`/`onLost` compare the snapshot before and after
  `updateUnderlyingNetworks`, both event orders) → `scheduleNetworkChanged(switched=true)` → 2 s debounce →
  `reconnectInternal()`: a new `On` of the stored session with `waitForNetwork`, only while the connected session's
  state is still wanted and, for a check bound to a session (network change, dead tun2socks, wake probe), that session
  is still the connected one — one captured after a stop cleared it never matches. Its run stops the session (`reconnecting`, TUN kept as a sink), waits up to 30 s for direct
  internet (`hasDirectInternet`: TCP to 8.8.8.8:53 bound to the physical network) while it is still wanted, then starts. A timed wakelock
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
`heartbeatThreshold` failures in a row. The counters, warm-up and cooldown are `HeartbeatPolicy`'s; the thread probes
and applies its actions; it reads the session (parameters, SOCKS port and login, core) only through its `Heartbeat.Host`, which the service implements. A failure below the threshold is retried twice, 3 s apart; a passed retry clears the count.

- **Probe** (`Heartbeat.probe`): `socks` — HTTP through the local SOCKS to `heartbeatUrl`, any 2xx (`SocksHttpProbe`; the
  request line carries the URL's raw, still-encoded path; it offers user/password only when the session has SOCKS credentials, and fails at once if the inbound demands them
  without any); `xrayDelay` — measured
  inside the core (also used for a custom `https://` URL); `passive` — none.
- **Passive success:** if TUN activity is fresh (the last 15 s), the tunnel is alive and the radio isn't woken. The
  activity (`VpnCore.lastRxActivityMs`): for the teapod-tun2socks cores (xray Go, sing-box) — payload from the proxy
  delivered to an app (`GetTunLastRxActivityMs`; the stack's own ACK/RST to connection attempts and DNS answers don't
  count, so a dead server isn't taken for a live one); for xray-rust — its own value, which also counts accepted TCP
  uploads. Until the first such payload the stall checks measure idle time from the heartbeat's start.
- **Warm-up** after a reconnect: probes every 15 s, failures don't count until the first success, hard limit 30 s
  (outbounds connect lazily; DNS + TLS on fresh LTE can be slow).
- **Exhausted** (the threshold, or a TUN stall): TUN activity (above) within the last 15 s (`isTunRxFresh`, whatever the probe cadence; re-checked for a stall) → keep the session (the probe can land on a dead balancer detour) and drop a pending config switch; otherwise: `reconnect` → `reconnectInternal()`; `switchConfig` → `tunnel_dead`
  event to Flutter ([vpn_provider](vpn_provider.md)); while it is pending (45 s) neither another exhaustion nor the
  warm-up limit reconnects; if nothing happens within 45 s (app killed, no live candidate) → plain reconnect.
- **Watchdogs:** no TUN activity for 120 s with ≥ 2 active connections → exhausted (a warning from 60 s, once a minute); more than 200 active tun2socks
  connections → reconnect when TUN activity is fresh (a gVisor state leak), otherwise exhausted (a dead upstream
  piling up attempts — `switchConfig` applies); on screen-on / Doze exit a TUN idle ≥ 120 s triggers a probe, not a
  blind reconnect (idle ≠ dead); ≥ 3 skipped probes for lack of internet, then a failure → reconnect at once.
- The SOCKS probe bypasses gVisor, so it can pass while app connections hang — that's what the watchdogs and the
  `onLost` force-close are for.

## Split tunneling and owner validation

`allExcept` → `addDisallowedApplication`, `onlySelected` → `addAllowedApplication` (the app itself is outside the
tunnel). `onlySelected` with no installed selected app allows none, and Android then applies the VPN to every app,
this one included: traffic stays in the tunnel, the owner check below is off (no listed UID), and the service logs a
warning. On top, tun2socks checks each new flow's owner UID (`getConnectionOwnerUid`) via `TunOwnerPolicy`
(shared by all cores): UID `-1` is either tethering or an excluded app that bound a socket to `tun0`
(`SO_BINDTODEVICE`) — indistinguishable. So `-1` is blocked in `onlySelected` (with at least one selected app installed), and in `allExcept` when the
exclusion list is non-empty and `allowTethering` is off. Exception: DNS to the TUN DNS address on port 53 (on Android
10 resolver sockets belong to netd). A lookup that throws (`SecurityException` while the service is not the active
VPN, a binder error) counts as UID `-1`: refused wherever `-1` is, allowed elsewhere. Such refusals are counted, and
the first one and every power of two after it go to the log as a warning. [security](../security.md)

## Stats, notification, logs

- **Stats** thread: every 1 s with the screen on (counters, history for the chart, notification), every 10 s with it
  off (counters only — the chart shows a gap). Flutter polls `getStats` / `getStatsHistory`.
- **Notification** is present while the service lives (a foreground service; the service lives only while the VPN
  is on or `blocked`); `showNotification`
  chooses full (`vpn_service`) or minimal (`vpn_service_minimal`). Updates are deduplicated, at most every 5 s, not with
  the screen off. All notifications come from `ServiceNotifications.base()` (`setOnlyAlertOnce`, fixed `when`,
  `FOREGROUND_SERVICE_IMMEDIATE`). Intermediate "Connecting…/Disconnecting…" only once per state.
- **Log file** `filesDir/vpn_log.txt`, lines `epochMs|level|message`, buffered (flush at 8 KB, every 5 s, immediately
  for warnings/errors, before reads); cleared on a user connect, kept across reconnects (previous one in
  `vpn_log.prev.txt`). Core logs arrive through `registerLogListener`. With `logsEnabled` off only warnings and errors
  are written; the flag is mirrored in native `vpn_prefs` so it works without Flutter.

## EventChannel (`VpnEventStreamHandler`)

`onListen` replays the current session snapshot (plus stats and the chart history when connected), so a restarted
UI catches up. It only sends: the tile and the notification follow the service's `publish()`. Events: `state`, `log`, `stats` (replay only), `statsHistory`,
`tunnel_dead`, `deeplink`.

## Tile

Disconnected: label "TeapodStream", subtitle = the config the tile will connect (`tile_config_name.txt` in
`QuickConnectStore`, saved with the quick-connect parameters; a name from the older `tile_config_name` preference is moved into the store once, under its lock, when the activity, the service or the tile starts). Active / transition / kill switch: label = config name, subtitle = status.
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
`dataExtractionRules` exclude everything. `FileProvider` for update APKs, limited to `filesDir/updates/`. The VPN service is not exported; the
activity, tile and command receiver are (the receiver checks `automationEnabled`).

Flutter renders with Skia (`EnableImpeller=false`): Impeller's Vulkan backend crashes the process in the Adreno driver
when the activity is destroyed over a live engine (a new task, a swipe from recents), and the VPN service lives in the
same process. In release builds the engine ignores the `ImpellerBackend=opengles` choice, so Impeller is off as a whole.

The battery-optimization exemption prompt is shown once per install, on the first connect while the app is
optimized (`battery_prompt_shown` in `vpn_prefs`); Settings → Battery optimization opens it again
(`openBatteryOptimizationSettings`: the prompt while optimized, the system list once exempt).

## Related

[VpnProvider](vpn_provider.md) · [XrayEngine](xray_engine.md) · [teapod-core](teapod_core.md) ·
[teapod-tun2socks](teapod_tun2socks.md) · [Security](../security.md)
