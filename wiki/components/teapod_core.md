# teapod-core

**Directory:** `core/` — a Go module (`github.com/Wendor/teapod-core`).

A gomobile AAR with all native engines. `core/build.sh build` produces `core/outputs/teapod-core.aar` (fat:
arm64-v8a + x86_64) and per-ABI AARs.

**Identity = the `core/` tree hash** (`git rev-parse --short=12 HEAD:core`), not the app version:
- `./build.sh binaries` takes `core/outputs/teapod-core-<hash>.aar`, else downloads that asset from an app release
  with the same `core/`, else builds (`./build.sh core`; Go, gomobile, NDK — `core/README.md`); uncommitted changes
  in `core/` always build locally;
- CI restores it from the Actions cache by the hash (`.github/actions/teapod-core`) and builds only on a miss;
- every app release attaches the AAR it was built with.

| Part | Source |
|---|---|
| xray-core (Go) | `github.com/xtls/xray-core`, patched (below) |
| sing-box (Go) | upstream v1.14.4 + AmneziaWG endpoint, `sysdns`, geo conversion (`internal/`) |
| tun2socks (Go) | `core/tun2socks/` ([teapod_tun2socks](teapod_tun2socks.md)) |
| xray-rust | prebuilt [xray-rust-mobile](https://github.com/aimalygin/xray-rust-mobile) AAR 0.9.0 (SHA-256 pinned), merged into the fat AAR |

```
GoCore / BoxCore:  TUN → tun2socks → SOCKS5 inbound → xray-core | sing-box → server
RustCore:          TUN fd → xray-rust → server
```

## Go API (`teapodcore.*`, called from Kotlin)

| Area | Functions |
|---|---|
| Setup | `InitCoreEnv(dir, …)` (geodata location; missing files are read from APK assets), `RegisterVpnProtector` (`VpnService.protect` for xray dialers and sing-box `AutoDetectInterfaceControl`), `RegisterLogListener`, `RegisterXrayProcessFinder` |
| xray | `StartXray(config, cb)`, `StopXray`, `GetXrayVersion`, `QueryXrayStats(tag, dir)`, `MeasureXrayDelay(url)`, `MeasureOutboundDelay(config, url)` |
| sing-box | `StartBox(config, dataDir, cb)`, `StopBox`, `GetBoxVersion`, `MeasureBoxDelay(url)`, `MeasureBoxOutboundDelay(config, dataDir, url)` |
| tun2socks | `StartTun2Socks(fd, mtu, socksPort, user, pass, allowICMP, blockQuic, validator)`, `StopTun2Socks`, `IsTunRunning`, `GetTunUpload/DownloadBytes`, `GetTunLastRxActivityMs`, `TunActiveConnections`, `ForceTunCloseAllConnections`, `GetTunStatsLine`, `GetTunDiagnostics`, `GetTunCacheSize`, `SetTunLogEnabled` |
| Diagnostics | `DumpGoroutines()` — stacks of all goroutines; itest saves it on failure |

`XrayCallback.onStatus(0 | -1, message)` reports start/stop. Log lines from Go goroutines arrive in
`LogListener.onLog` — the Kotlin side must be thread-safe.

## Behaviour worth knowing

- `StartXray` stops the previous instance first; the start goroutine checks it is still the current instance, so a
  concurrent `StopXray` can't leave an orphan holding the SOCKS port.
- Delay measurement: `http.Transport` over `core.Dial`, 2 attempts with keep-alive, `CloseIdleConnections` on exit
  (an idle connection keeps the outbound session and the server connection alive). Temporary instances don't register
  the global log handler — otherwise the main instance stopped logging.
- The console log writer writes to stdout only without a `LogListener` (no duplicate logcat lines).
- sing-box: platform interface stub with protected sockets (`auto_detect_interface` forced); connection owner lookup
  off (behind tun2socks the source is always 127.0.0.1); `cache.db` in `dataDir` (cwd on Android is read-only `/`);
  the `local` DNS transport uses the system resolver (`internal/sysdns`, Android has no `/etc/resolv.conf`); version
  injected by `build.sh` via `-ldflags`.
- Geo for sing-box (`internal/geoconv`): sing-box 1.12+ can't read `.dat`; before start, local rule-sets tagged
  `geoip-<code>` / `geosite-<code>` are built into `<dataDir>/box-rules/*.srs` from the `.dat` files and cached by the
  source's size and mtime.
- AmneziaWG (`internal/awg`): endpoint `type: awg` = sing-box WireGuard options + `amnezia`; adapted from sing-box's
  WireGuard transport onto `amneziawg-go/v3`; one peer, outbound only; the bind doesn't touch bytes 1–3 (AWG header).
  After reconfiguration it wakes the TUN reader so the first packet gets the padding; a pending wake is served before
  any queued packet.
- Build tags: `with_gvisor,with_quic,with_wireguard,with_utls,with_naive_outbound,badlinkname,tfogo_checklinkname0`.
  Naive links Cronet statically (`CGO_LDFLAGS_ALLOW='-l:libcronet\.a'` for Go 1.27.4+). gomobile needs
  `-checklinkname=0`.
- `replace github.com/sagernet/gvisor` pins the gVisor version sing-box is tested with.

## xray-core patches (`patches/xray-core/`)

`core/build.sh` (also `./build.sh prepare` alone) copies the module into `.xray-core/` and applies them; `go build`,
`go vet` and `go test` need that directory.

| Patch | Problem it fixes |
|---|---|
| `0001-release-cached-transport-dialers` | xhttp and gRPC cached connections globally per instance config and never released them: every restart or temporary instance left a connection with keep-alive forever |
| `0002-utls-ech-for-fingerprints-without-ech` | ECH with a fingerprint whose spec has no ECH extension (Safari, iOS, Edge) failed with `malformed outer client hello`; adds a GREASE ECH extension |
| `0003-xhttp-no-h3-alpn-over-tcp` | xhttp over TCP offered `h3` in ALPN; with ECH the server picked `h3` and HTTP/2 got `unexpected EOF` |
| `0004-quic-close-pipe-conn-before-transport` | QUIC over `dialerProxy` (Hysteria2 with noise/fragment, xhttp h3) hung forever in `Transport.Close` after a failed handshake, blocking all later requests |

## Licenses

sing-box is GPL-3.0-or-later, so the AAR binary is GPL; amneziawg-go MIT, xray-core MPL-2.0 (`third_party/`).

## Related

[teapod-tun2socks](teapod_tun2socks.md) · [Android native](android_native.md) · [CI](ci.md)
