# Models

Immutable data classes and the enums they use, in `lib/core/models/` (`AppSettings` —
[settings_provider](settings_provider.md)). Models import no services; all of them are stored as JSON.

**Compatibility rule.** Users keep their data across updates. A new field needs a default in `fromJson`; a renamed
or restructured field needs a read of the old key or a migration. Tests check the round trip
(`test/core/`); never "fix" old data by resetting it. A migration is removed only by a maintainer's decision on the
oldest version that may still upgrade directly; versions before 1.3.3 (plaintext configs in SharedPreferences) are
below that cut-off.

## VpnConfig (`vpn_config.dart`)

One server. Fields by purpose:

| Purpose | Fields |
|---|---|
| Identity | `id` (UUID; subscription configs get a new one on every refresh), `name`, `createdAt`, `subscriptionId`, `rawUri` (original link, for export and to detect edits) |
| Endpoint | `protocol`, `address`, `port`, `hopPorts` (Hysteria2 port hopping) |
| Credentials | `uuid` (VLESS/VMess), `password` (Trojan/SS/Hy2), `method` (SS), `encryption`, `alterId`, `flow` |
| Security | `security` (`none`/`tls`/`reality`), `sni`, `fingerprint`, `alpn`, `allowInsecure`, `ech`, Reality `publicKey`/`shortId`/`spiderX`/`postQuantumKey` |
| Transport | `transport`, `wsPath`, `wsHost`, `grpcServiceName`, `xhttpMode`, `xhttpExtra`, `finalmask`, `obfsPassword` (Hy2 salamander), `ssPrefix` (Outline prefix, hex) |
| Managed | `rawXrayConfig` — a ready xray JSON from a managed subscription, merged instead of generated |
| sing-box only | `protocolSettings` (below) |
| Core | `core` — the pinned core, null = by priority ([vpn_provider](vpn_provider.md#choosing-the-core)) |
| Ping | `latencyMs` (null = unknown), `lastPingedAt` |

`VpnProtocol`: `vless`, `vmess`, `trojan`, `shadowsocks`, `hysteria2`, and sing-box-only `wireguard`, `ssh`,
`naive` (xray cores refuse them with `VpnProtocol.singBoxOnlyReason`). `VpnTransport`: `tcp`, `ws`, `grpc`, `http2`,
`quic`, `xhttp`, `httpupgrade`, `splithttp`.

`validate()` returns the first problem (empty address, port out of range, missing UUID/password, missing
`protocolSettings` of the right type) or null; `VpnNotifier.connect` calls it before native. `protoTag` is the short
label in lists (`AWG` for WireGuard with Amnezia parameters).

### ProtocolSettings (`protocol_settings.dart`)

Sealed, JSON with a `type` discriminator; null for the xray protocols.
- `WireGuardSettings` — keys, addresses, peer, PSK, MTU, reserved, allowed IPs, keepalive and
  `amnezia: AmneziaParams?` (AmneziaWG 3.1 parameters; serialized for teapod-core's `awg` endpoint).
- `SshSettings` — user, password and/or private key (+ passphrase), pinned host keys.
- `NaiveSettings` — user, password, `quic`, extra headers.

## Subscription (`subscription.dart`)

`id`, `name`, `url`, `createdAt`, `lastFetchedAt`; usage info from the response headers (`expireAt`,
`uploadBytes`, `downloadBytes`, `totalBytes`, `announce`, `announceUrl`); `pinnedCertDer` — the self-signed
certificate the user accepted (trust on first use; auto-refresh accepts only it).

## RoutingSettings

File: `routing_settings.dart`.

`direction` (`global` / `bypass` / `onlySelected`) decides where matched traffic goes (`selectedOut`) and where the
rest goes. Matchers, each with its own switch: `bypassLocal` (`geoip:private` → direct), `domainZones`
(`domain:ru`), `geositeCodes`, `geoCodes` (`geoip:xx`), `sites`, `ruServicesEnabled` (a built-in list of Russian
services). `adBlockEnabled` works in DNS, not routing: `geosite:category-ads-all` and `geosite:win-spy` are answered
locally. Rule order and per-core translation: [xray_config_builder](xray_config_builder.md),
[singbox_config_builder](singbox_config_builder.md).

## Other models

| Model | File | Notes |
|---|---|---|
| `VpnStats`, `SpeedPoint` | `vpn_stats.dart` | totals, speeds (bytes/s), duration, server, chart history |
| `DnsServerConfig`, `DnsMode`, `DnsType` | `dns_config.dart` | `proxy`/`direct`; UDP, DoH, DoT; presets (`cf_udp`, `google_doh`, …) |
| `VpnLogEntry`, `LogLevel` | `vpn_log_entry.dart` | `LogService` keeps the last `AppConstants.maxLogEntries` (1000) |
| `AppInfo` | `app_info.dart` | installed app for split tunneling; icons load lazily |
| `FragmentSettings`, `NoiseSettings`, `MuxSettings`, `TlsFingerprint` | `xray_tuning.dart` | [settings_provider](settings_provider.md#tuning-xray_tuningdart) |
| `HeartbeatSettings` | `heartbeat_settings.dart` | [settings_provider](settings_provider.md#heartbeat-heartbeat_settingsdart) |
| `CoreKind` | `core_kind.dart` | `xrayGo`, `singBox`, `xrayRust`; `nativeId`, `defaultOrder`, `parseOrder` |
| `PinnedRef` | `pinned_ref.dart` | [config_provider](config_provider.md#pins) |
| `Profile`, `ProfileBundle`, `ConfigSelection` | `profile.dart`, `profile_bundle.dart`, `config_selection.dart` | [profiles](profiles.md) |
| `ConnectionsBundle` | `connections_bundle.dart` | [profiles](profiles.md#bundles-and-deep-links) |
| `connectionFingerprint` | `connection_fingerprint.dart` | [vpn_provider](vpn_provider.md) |

## Related

[VlessParser](vless_parser.md) · [ConfigProvider](config_provider.md) · [Services](services.md)
