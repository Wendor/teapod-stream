# XrayConfigBuilder and RustConfigBuilder

**Files:** `lib/protocols/xray/xray_config_builder.dart`, `lib/protocols/xray/rust_config_builder.dart`,
`lib/protocols/xray/xray_go_backend.dart`, `lib/protocols/xray/xray_rust_backend.dart`,
`lib/core/constants/xray_defaults.dart`

`XrayConfigBuilder` turns a `VpnConfig` + `VpnEngineOptions` into the JSON for xray-core (Go): `buildJson` for a
generated config, `mergeWithRaw` for a managed subscription's ready JSON. Pure functions, no state.
`RustConfigBuilder` translates the Go builder's output into the subset xray-rust accepts.

## Generated config

```
log · dns · inbounds: [socks-in] · outbounds: [proxy, direct (freedom), block (blackhole), dialer-out?] · routing · policy
```

Access log (`log.access`) only at `debug`: otherwise it writes a line per connection to logcat and `vpn_log.txt` —
a browsing history on disk.

### Inbound

One SOCKS5 inbound `socks-in` on `127.0.0.1:socksPort`, `auth: password` when credentials are set.
- `udp: true` always: tun2socks also sends the apps' DNS through UDP ASSOCIATE. `enableUdp = false` is a rule instead:
  `socks-in`, `network: udp`, ports `1-52,54-65535` → `block`, right after `port 53 → dns-out`.
- `sniffing.enabled` = `sniffingEnabled`; when on, `routeOnly: true` — the sniffed domain is used only for routing,
  the destination stays the IP the app connected to. Without it xray re-resolves the domain and may switch the
  connection to another IP: broken connections and a DNS leak.
- Routing `domainStrategy: IPIfNonMatch` so `geoip:` rules also match domain requests (affects only the decision).

### DNS

- `proxy` — the DNS module answers the apps' queries with the chosen server, its sockets go through the tunnel.
  `direct` — the same block, but the module's sockets go to `direct`; DoH/DoT stay encrypted.
- `tag: dns-module`; routing sends `inboundTag: [dns-module]` → `proxy` (or `direct` in direct mode) and
  `socks-in` port 53 → `dns-out`.
- `queryStrategy` from `dnsQueryStrategy`: `UseIPv4` / `UseIPv6` / `UseIP`.
- `disableFallback: true` in proxy mode: otherwise a broken main server silently degraded to the bootstrap entry
  and everything resolved through Google. With it, a domain matching no `domains` filter goes to `servers[0]`, so
  **the main server is always first**, then ad block (`rcode://success`), then bootstrap.
- DoT uses `tls://<domain>:<port>` (`DnsServerConfig.domain`), not the IP — otherwise no SNI and the certificate
  check fails. Custom addresses are parsed by `_custom()`: scheme, `:port` (also for bracketed IPv6), defaults
  UDP 53 / DoT 853 / DoH 443; a bare DoH host becomes `https://<host>/dns-query`.
- **Bootstrap.** The DNS module can't resolve its own DoH/DoT hostname. Presets use `hosts`
  (`cloudflare-dns.com → 1.1.1.1`); a custom hostname gets a UDP `8.8.8.8` entry filtered to that hostname only.
  Not added for an IP address.
- Ad block (any routing direction): `geosite:category-ads-all` + `geosite:win-spy` → `rcode://success`.

### Proxy outbound

VLESS / VMess / Trojan / Shadowsocks (+ Outline `prefix` from `ssPrefix`) / Hysteria2 in the standard xray
form; `streamSettings` by transport (`tcp`, `ws`, `grpc`, `xhttp` + `mode`/`extra`, `httpupgrade`, `splithttp`)
and security (`tls` with `serverName`, `fingerprint`, `alpn`, `echConfigList`; `reality` with `publicKey`,
`shortId`, `spiderX`, post-quantum key).

- **TLS fingerprint**: `options.tlsFingerprint.xrayValue ?? config.fingerprint` — the global setting overrides the
  link unless it is `defaultFp`; Reality falls back to `chrome`. Not applied to managed configs.
- **Certificate pin**: `certificatePins()` normalizes hex / colon-hex / base64 SHA-256 into
  `pinnedPeerCertSha256`; with a pin `allowInsecure` is false; garbage → `FormatException`.
- **Hysteria2**: `finalmask.udp` — `udphop` first when `hopPorts` is set (masks that dial themselves must come
  first), then `salamander` with `obfsPassword`. **SNI is mandatory**: the hysteria dialer doesn't pass the
  destination to `GetTLSConfig()`, so an empty `serverName` became the literal `hysteria`; the builder uses the
  address when `sni` is empty.
- **TCP HTTP header** (`headerType=http`) is read from `rawUri` into `tcpSettings.header`.
- `sockopt.tcpUserTimeout: 30000` (not Hysteria2; on `dialer-out` when it is used): a connection whose packets DPI
  drops breaks after 30 s instead of hanging until `tcp_retries2`.

### Fragment, noise, Mux

- Fragment or noise active (and `isValid` — garbage values stop xray from starting) → a freedom outbound
  `dialer-out` with `fragment` / `noises`, and the proxy outbound gets `sockopt.dialerProxy = dialer-out`. Fragment
  works on the TCP leg (not Hysteria2), noise on UDP (Hysteria2, QUIC); port 53 isn't noised.
- Mux (`_muxApplies`): never for Hysteria2 (QUIC multiplexes itself). The global switch skips xhttp: it has its own
  xmux, and Xray's xhttp inbounds refuse TCP inside Mux. `mux=on` / `mux=off` in the link
  (`VlessParser.linkMux`) overrides the switch for one server, xhttp included: a server behind a GET-only CDN that
  buffers responses pads the download with Mux KeepAlive frames, so the client must use Mux. With
  `xtls-rprx-vision` TCP Mux is forced off (`concurrency: -1`) — the server breaks Mux connections carrying TCP;
  only XUDP stays.

### Routing

In order: DNS rules → `geoip:private` → direct (`bypassLocal`) → `domain:<zone>` → `geosite:` → `geoip:` → sites →
Russian services list → diagnostic hosts → proxy (only `onlySelected`, so connectivity checks see the tunnel) →
catch-all. Matched traffic goes to `selectedOut` (`direct` for `bypass`, `proxy` for `onlySelected`); the catch-all
goes to `proxy` for `global`/`bypass` and `direct` for `onlySelected`.

QUIC blocking is **not** a routing rule: tun2socks answers UDP/443 with ICMP Port Unreachable before xray sees it.
A silent drop made Chrome wait ~55 s on QUIC while HTTP/2 requests to the same host hung
([teapod_tun2socks](teapod_tun2socks.md)). Vision flows force the block (`effectiveQuicBlock`): Vision rejects UDP/443.

Policy timeouts (`XrayDefaults`): handshake 4 s, connIdle 120 s, uplinkOnly 5 s, downlinkOnly 30 s.

## `mergeWithRaw` — managed subscriptions

`VpnConfig.rawXrayConfig` is a server-made config. **The server owns routing and DNS**; the app replaces only what it
must:

| Section | Action |
|---|---|
| `inbounds` | replaced by the app's SOCKS (port, credentials, sniffing), **keeping the original tag** — server rules match `inboundTag: ["socks", …]` |
| `log` | replaced |
| `dns` | kept — it is built for the server's outbound topology; replacing it broke resolving, and routing `dns-module → direct` would leak |
| `api`, `metrics` | removed — with `listen` they are an unauthenticated gRPC (lists outbounds with keys) / pprof on localhost |
| `allowInsecure` in outbounds | removed — fatal in xray v26 |
| `observatory.probeInterval` | raised to at least `obsProbeIntervalSec` (default 600 s, 0 = keep): configs with 30 s and 20+ outbounds flooded mobile links with TLS probes and triggered server resets |
| balancer `fallbackTag` pointing to freedom | rewritten to the first proxy outbound of the selector, else `teapod-blackhole` — otherwise traffic leaves outside the VPN when all nodes are "dead" and in the first seconds before observatory has results |
| ad block | `geosite:` ads rule → `teapod-blackhole` at the top (no DNS-level ad block here) |
| `routing.rules` | only `→ direct` rules are prepended (bypassLocal, geo bypass); proxy rules and the catch-all stay the server's |
| UDP off | the same `network: udp` rule on the server's SOCKS tag → `teapod-blackhole` |
| parse error | `FormatException` (never fall back to the raw config with the server's inbounds) |

Shown to the user on Home: their DNS settings and ad block via DNS don't apply; `onlySelected` routing doesn't work
(there is no `proxy` outbound).

## Core compatibility

- **Go** (`XrayGoBackend.checkConfig` → `XrayConfigBuilder.unsupportedReason`): refuses what xray v26 rejects at start
  — `h2`/`http`/`quic` transports, `allowInsecure` without a pin, a broken pin, sing-box-only protocols.
- **Rust** (`XrayRustBackend`, `RustConfigBuilder.unsupportedReason`): VLESS, Trojan, VMess AEAD, Shadowsocks 2022,
  Hysteria2; no raw configs, no link `finalmask` (the builder assembles its own subset), no `mux=on` in the link (except
  Hysteria2), no Vision on non-RAW transports without VLESS encryption. Unsupported features (`CoreFeature`):
  proxy-only, ICMP toggle, MTU, Mux, observatory, raw config. The Rust core reads the TUN fd itself, so
  `RustConfigBuilder` adds the TUN inbound, removes the Go-only UDP rule (it has `_blockTunUdp`), strips `sockopt`, and
  converts `udphop` back to `quicParams.udpHop`. `buildProbe` makes a password-protected probe inbound for latency
  measurement.

## Related

[SingBoxConfigBuilder](singbox_config_builder.md) · [VlessParser](vless_parser.md) · [Models](models.md) ·
[Architecture](../architecture.md#cores)
