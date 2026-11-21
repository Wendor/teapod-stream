# SingBoxConfigBuilder — the sing-box core, Dart side

**Files:** `lib/protocols/singbox/` — native: `BoxCore` ([android_native](android_native.md)), Go: `StartBox`
([teapod_core](teapod_core.md)).

| File | Role |
|---|---|
| `singbox_backend.dart` | `SingBoxBackend implements CoreBackend`. Unsupported: `noise`, `mux` (sing-mux isn't compatible with xray servers), `observatory`, `rawConfig`. Fragmentation only `tlshello` (other values are reset with a warning). QUIC is blocked by tun2socks, as for Go |
| `singbox_config_builder.dart` | `build` / `buildJson` / `buildProbeJson` (no inbounds, logging off), `unsupportedReason` |
| `singbox_outbound.dart` | the `proxy` outbound: VLESS/VMess (`packet_encoding: xudp`), Trojan, Shadowsocks, Hysteria2 (`server_ports` `a:b`, salamander), WireGuard/AmneziaWG (in `endpoints`), SSH, Naive; TLS/Reality/uTLS/ECH/ALPN, `tls.fragment`; transports ws (`?ed=` → `max_early_data`), grpc, http, httpupgrade, quic |
| `singbox_route.dart` | DNS and route |

## Config

- Inbound `mixed` `socks-in` on 127.0.0.1 with a password; tun2socks feeds it, as for the Go core.
- Route: `sniff` → `hijack-dns` (port 53 from tun2socks) → reject UDP when UDP is off → `ip_is_private` → zones /
  geosite / geoip / sites / Russian services (`selectedOut`) → in `onlySelected` the probe hosts and the IP lookup hosts
  (`IpLookupSource.hosts`) through the proxy; `final` is `direct` for `onlySelected`, otherwise `proxy`.
- DNS: `dns-main` by `DnsType` (`detour: proxy` in proxy mode), `dns-local` — the system resolver and
  `default_domain_resolver`. SSH and Naive carry no UDP, so in proxy mode a UDP `dns-main` becomes TCP.
- Ad block: DNS rule `predefined NOERROR` for `geosite-category-ads-all` / `geosite-win-spy`.
- Geo: local rule-sets `geoip-<code>` / `geosite-<code>` (`<tag>.srs`, lower case); teapod-core builds them from the
  `.dat` files (`geoconv`). The Russian services list comes from `RoutingDefaults.ruServicesDomains` (`domain:` →
  `domain_suffix`, `full:` → `domain`).
- Log: the app's `info` → sing-box `warn` (at `info` sing-box logs every connection — a browsing history in
  `vpn_log.txt`); `debug` as is.
- TLS: Hysteria2 without uTLS (QUIC needs the standard stack); `ech` in xray's DNS form (`[domain+]https://…`) →
  `query_server_name`, otherwise a PEM ECHConfigList.

## Refused on sing-box (config disabled)

XHTTP / SplitHTTP, TCP with HTTP header obfuscation, VLESS Encryption, flows other than `xtls-rprx-vision`,
`rawXrayConfig`, `finalmask` / `xhttpExtra`, `mux=on` in the link (Xray Mux; not for Hysteria2), SS plugins and
unknown methods, **certificate pins** (sing-box pins only public keys — connecting without the check is not an
option), AmneziaWG `HeaderProtectionKey` with `S1`–`S4` < 12, `reserved` together with AWG.

Reality `pqv` doesn't block: the ML-DSA signature is an extra certificate extension and the main Reality HMAC check is
the same, so the config works without the post-quantum check — `checkOptions` warns.

## Known limitations

- AmneziaWG endpoint (`internal/awg` in teapod-core): one peer, outbound only.
- SSH links: the hiddify format (`pk` / `hk`) plus `pkp`.
- `vpn://`: only client AWG/WireGuard configs.

## Related

[XrayConfigBuilder](xray_config_builder.md) · [VlessParser](vless_parser.md) · [Architecture](../architecture.md#cores)
