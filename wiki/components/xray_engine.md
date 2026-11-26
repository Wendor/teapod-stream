# XrayEngine — the MethodChannel client

**Files:** `lib/protocols/xray/xray_engine.dart`, `lib/core/interfaces/vpn_engine.dart`

`XrayEngine` is a thin client of the native service: it builds the core config with the `CoreBackend` passed to the
call and marshals calls over `MethodChannel("com.teapodstream/vpn")`. No state lives here — events
come back over `EventChannel("com.teapodstream/vpn/events")`, exposed once as the static broadcast stream
`XrayEngine.events` (a second `receiveBroadcastStream()` on the same name would steal the handler).

The name is historical: it drives all three cores. Providers get it from `xrayEngineProvider`, so tests override the
engine instead of mocking the channel.

## Calls

| Dart | Channel method | Notes |
|---|---|---|
| `connect(config, backend, options, attempt:)` | `connect` | `backend.buildConfig` → `xrayConfig` + `engine` (`CoreKind.nativeId`), `attempt` (the caller's connect attempt; state events of the session carry it back, [vpn_provider](vpn_provider.md#connectswitching)), config name, SOCKS, split tunneling (`vpnMode`, `excludedPackages`, `includedPackages`), proxy-only, notification, kill switch, ICMP, QUIC block, tethering, MTU, heartbeat (`probe`, `action`, `threshold`, `url`), `ssPrefix`. A `ReasonException` from the builder passes through as is (the caller keeps the reason localizable); another `FormatException`/`StateError` becomes `PlatformException('UNSUPPORTED_CONFIG')` |
| `saveQuickConnect(config, backend, options)` / `clearQuickConnect` | same | parameters for reconnect from the tile, boot or service restart, without connecting |
| `disconnect()` | `disconnect` | |
| `getVpnState()` | `getState` | a `NativeSession`: state, `reconnecting`, SOCKS credentials, `connectedAtMs`, `attempt` (the connect attempt of the native session), `error`. `NativeSession.parse` reads the `state` event map, which `getState` returns too; `VpnNotifier` parses its events with it |
| `getStats()` / `getStatsHistory(epoch, since)` | same | history is incremental: `(epoch, seq)` |
| `pingConfig(config)` | `ping` | ICMP `ping` (only for an address that is a hostname or IP literal, `isPingableAddress`), TCP connect as fallback; direct, not through the tunnel |
| `measureOutbound(config, backend, options, url)` | `measureOutbound` | real request through a temporary core instance (config switch, urltest) |
| `getLogs` / `getLogFilePath` / `clearLogs` / `setLogsEnabled` | same | `vpn_log.txt` in `filesDir`, lines `epochMs|level|message` |
| `getTunnelDiag()` | `getTunnelDiag` | diagnostic dump for the logs screen |

The other methods of the same channel — binary versions, available cores, installed apps and icons, files dir and
binary preparation, ABI, APK install, device id and info — go through
[`PlatformService`](services.md#platformservice).

## Related

[VpnProvider](vpn_provider.md) · [Android native](android_native.md) · [XrayConfigBuilder](xray_config_builder.md)
