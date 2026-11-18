# VlessParser — link parsing

**Files:** `lib/protocols/xray/vless_parser.dart`, `lib/protocols/parsers/` (WireGuard, AmneziaVPN, SSH, Naive)

`VlessParser.parseUri(uri)` turns one link into a `VpnConfig` (null if it can't), dispatching non-xray schemes to
the parsers in `lib/protocols/parsers/`. `rawUri` keeps the original link for export and to detect edits.
Multi-line subscription bodies are split and decoded in `SubscriptionService` ([services](services.md)).

## Xray protocols

| Scheme | Format and notes |
|---|---|
| `vless://` | `uuid@host:port?…#name`: `security`, `type`, `path`, `host`, `sni`, `fp`, `alpn`, `flow`, `encryption`, Reality `pbk`/`sid`/`spx`/`pqv`, `ech`, `pinSHA256`, `allowInsecure`/`insecure`, `mode`/`extra` (xhttp), `fm` (finalmask) |
| `vmess://` | base64 JSON: `ps`, `add`, `port`, `id`, `aid`, `scy`, `net`, `type`, `host`, `path`, `tls`, `sni`, `alpn`, `fp`, … |
| `trojan://` | `password@host:port`; `security` (tls/reality/none), Reality params, `pinSHA256`, `alpn`, `ech`; the password is percent-decoded. `allowInsecure` is deliberately not read |
| `ss://` | `base64(method:password)@host:port` or legacy `base64(method:password@host:port)`; Outline `prefix` → `ssPrefix` |
| `hysteria2://`, `hy2://` | `password@host:port?sni&insecure&obfs-password&pinSHA256`; port hopping: a range/list in the authority (`20000-30000`, `443,5000-6000`) or `mport` → `hopPorts`, the first port → `port`; an unparsable port rejects the link, an unparsable `mport` is ignored |

`VlessParser.linkParams` / `vmessJson` re-read details that aren't model fields (e.g. TCP `headerType=http`) from
`rawUri` at build time. `linkMux` reads `mux=on|off` (also `true`/`false`, `1`/`0`) — Mux for this server regardless
of the global setting ([xray_config_builder](xray_config_builder.md#fragment-noise-mux)).

**Names** come from the fragment: percent-encoded or raw Unicode — `_decodeName` falls back to the raw text when
`Uri.decodeComponent` throws. IPv6 hosts in brackets are supported.

## sing-box-only protocols (`lib/protocols/parsers/`)

**WireGuard** (`wireguard_parser.dart`) — `wireguard://`, `wg://` and wg-quick `.conf` text (`isConf`):
- link: `wireguard://<privateKey>@host:port?publickey&presharedkey&address&mtu&reserved&allowedips&keepalive#name`
  (with synonyms); the query is parsed without turning `+` into a space (base64 keys);
- `.conf`: case-insensitive sections and keys, CRLF, `#`/`;` comments; wg-quick-only keys (`DNS`, `PostUp`, `Table`, …)
  ignored; exactly one `[Peer]`, otherwise a `FormatException` with the reason (shown by AddConfigScreen); repeated
  `Address`/`AllowedIPs` accumulate; an address without a mask gets `/32` or `/128`;
- defaults: `allowedIps = 0.0.0.0/0, ::/0`; a keepalive range takes the lower bound;
- **AmneziaWG**: `Jc`, `Jmin`, `Jmax`, `S1`–`S4`, `H1`–`H4`, `I1`–`I5`, `HeaderProtectionKey`, padding and timing keys,
  `RandomTrailers` / `DisableCookies` → `WireGuardSettings.amnezia`. Any of them makes the profile AWG. Without
  `RandomTrailers` the client drops AWG 3.1 server replies with a trailer;
- `toUri` gives the `rawUri` for a `.conf` profile (export, bundle deduplication).

**AmneziaVPN keys** (`amnezia_key_parser.dart`) — `vpn://` = base64url(qCompress(JSON)) (4-byte length + zlib).
Takes the wg-quick text from `containers[].awg|wireguard.last_config`, name from `description`, `mtu` if the text has
none. Full-access keys and other Amnezia protocols aren't imported.

**SSH** (`ssh_parser.dart`) — `ssh://user[:password]@host[:port]?pk=<key>&pkp=<passphrase>&hk=<host keys>#name`,
default port 22; a bare key body is wrapped as an OpenSSH PEM; no password and no key → null.

**NaiveProxy** (`naive_parser.dart`) — `naive+https://user:pass@host[:port]?extra-headers=…#name` and `naive+quic://`;
default port 443; headers are `Name: value` lines.

`SubscriptionService._uriSchemes` lists every scheme above: a text subscription made only of, say, WireGuard links
would otherwise be treated as base64.

## Related

[Models](models.md) · [Services](services.md) · [XrayConfigBuilder](xray_config_builder.md) ·
[SingBoxConfigBuilder](singbox_config_builder.md)
