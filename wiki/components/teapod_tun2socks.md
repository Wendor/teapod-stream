# teapod-tun2socks

**Directory:** `core/tun2socks/` — package `github.com/Wendor/teapod-core/tun2socks`.

A TUN → SOCKS5 gateway on gVisor's userspace TCP/IP stack, with a per-flow owner check.

```
TUN fd → tunReadLoop ─┬─ ICMP echo / QUIC reject (answered locally)
                      └─ gVisor netstack → TCP/UDP forwarder → EngineHook.Validate (UID) → SOCKS5 → core
```

| File | Role |
|---|---|
| `teapod_tun2socks.go` | gomobile entry `TeapodTun2socks` |
| `engine.go` | netstack, TUN reader/writer, forwarders, connection trackers |
| `engine_hook.go` | `EngineHook`: LRU cache + `UIDValidatorFunc` |
| `icmp_reject.go` | ICMP Port Unreachable (QUIC block) and local Echo Reply |
| `connection.go` | `ConnectionKey`, LRU cache |
| `socks5.go` | SOCKS5 CONNECT + UDP ASSOCIATE client |

## API

`Start(tunFD, mtu, socksHost, socksPort, user, pass, allowICMP, blockQuic, cacheCapacity, cacheTTLSeconds, validator)`
returns an error string (empty = OK). Works on a `dup` of the fd — `Stop()` closes only its copy, which is what lets
the app reuse the TUN fd across reconnects. Also: `Stop`, `IsRunning`, `CacheSize`, `SetLogEnabled`,
`GetUpload/DownloadBytes`, `GetActiveConnections` (TCP + UDP), `GetLastRxActivityMs` (last payload from the proxy delivered to an app, TCP or UDP — not the stack's own ACK/RST, not DNS answers),
`ForceCloseAllConnections` (gVisor side of all TCP and UDP flows), `GetStatsLine`, `GetDiagnostics` (JSON with the
active connection table).

`UIDValidatorFunc.Validate(srcIP, srcPort, dstIP, dstPort, protocol) bool`, protocol 6/17. The app's policy:
[android_native](android_native.md#split-tunneling-and-owner-validation).

## Behaviour worth knowing

- **TCP order:** `CreateEndpoint` first (ACK the SYN), then `Validate` — the IPC to Kotlin takes 20–100 ms and
  serializes under bursts; validating first made gVisor RST Chrome's SYN retransmits.
- **`req.Complete(false)`** right after `CreateEndpoint` removes the 4-tuple from the forwarder's in-flight table.
  Without it every connection leaked an entry, and after 1024 all new SYNs were dropped — a "VPN is connected but
  nothing works" state the heartbeat can't see.
- **UDP validation** runs in the flow goroutine, not in the packet path, so a cache miss doesn't stall the whole TUN.
  The cache key is the full 5-tuple: a key by source port only let an excluded app bound to `tun0` reuse a port that
  an allowed app had just used, and get into the tunnel. For the same reason an allowed decision is dropped when its
  flow ends (TCP and UDP), before the endpoint closes and lets a new flow on that 5-tuple in, or as soon as the app
  resets a TCP connection (even while the SOCKS dial is pending); denials stay for the TTL, so a blocked app's
  retries don't call the validator each time.
- **Idle and zombie TCP:** activity tracked per direction; closed when both sides are silent ≥ 5 min, or after 2 min
  of "request sent, upstream silent" (a lost close after a server reset). Read deadlines in 30 s steps, no sweepers.
- **Half-close:** EOF in one direction becomes `CloseWrite` on the other side; the reverse direction keeps working.
- **UDP idle:** a flow ends after 60 s without a forwarded datagram in either direction, so send-only and
  receive-only flows stay alive; dropped datagrams (foreign source, bad header) don't count.
- **UDP relay** has a third goroutine watching the SOCKS5 ASSOCIATE control connection: when the core closes the
  relay, the flow ends at once instead of after the 60 s idle timeout.
- **QUIC block** (`blockQuic`): UDP to port 443 is answered with ICMP Port Unreachable (v4 type 3 code 3, v6 type 1
  code 4) in `tunReadLoop`, before gVisor. A silent drop or a blackhole makes Chrome wait ~55 s of QUIC retransmits
  while HTTP/2 requests to the same host hang; routing it `direct` would leak. Nothing leaves the device.
- **ICMP echo:** SOCKS5 can't carry ICMP and gVisor has no handler, so with `allowICMP` the reader answers Echo
  Requests itself (the time is to the TUN, not to the host — as xray-rust does); otherwise they are dropped.
- **gVisor tuning:** TIME_WAIT off and global reuse (addresses are virtual; TIME_WAIT piled up over hours), linger
  1 s, gVisor → TUN channel 4096 (256 overflowed under bursts and dropped ACKs).
- **Stop before start:** the wrapper runs `Engine.Start` in a goroutine, so `Stop` may come first; it still closes
  the fd copy and the stack, and the late `Start` returns without starting workers.
- Forwarder goroutines aren't in the engine wait group: `Stop()` cancels pending SOCKS dials but established flows end
  by idle timeout or with the stack.

## Tests

```bash
cd core && ./build.sh prepare && go test ./tun2socks/    # engine hook, ICMP, half-close, SOCKS5
```

## Related

[teapod-core](teapod_core.md) · [Android native](android_native.md)
