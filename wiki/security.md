# Security

**Threat model.** A malicious app on the same device wants to learn that a VPN is on, find the server, or learn the
real IP; a link or a subscription tries to change security-relevant settings. A rooted device is out of scope.
Vulnerabilities are reported privately (GitHub security advisories), not in issues: [SECURITY.md](../SECURITY.md)
says how, and what counts.

## Protections

| Threat | Protection |
|---|---|
| An excluded app binds a socket to `tun0` (`SO_BINDTODEVICE`) and learns the VPN and the server's IP | per-flow owner check in tun2socks / TUN admission (`TunOwnerPolicy`): UID `-1` is blocked in `onlySelected` and in `allExcept` with exclusions, unless "tethering through VPN" is on, and so is a flow whose owner lookup throws ([android_native](components/android_native.md#split-tunneling-and-owner-validation)); the cache is keyed by the full 5-tuple |
| Local SOCKS used by other apps | in TUN mode credentials are always set (random, or generated when the manual ones are empty); the Rust probe inbound uses a one-time password |
| `PrefixTcpProxy` reachable by others | loopback only, own UID only |
| State broadcast reveals the VPN | `STATE_CHANGED` is sent only with the automation option (off by default), without the port |
| An app turns the VPN off through `VpnCommandReceiver` | commands are ignored unless automation is on |
| Deep link `?url=` makes the app fetch an attacker URL from the real IP | https only (redirects too), at most 1 MB, downloaded after a dialog showing the host, through the tunnel when connected; when the tunnel fails it is retried directly, from the real IP (a rejected certificate is not retried) |
| An imported profile opens a noauth proxy, redirects probes or swaps the geodata source | security fields and geodata URLs stay local; export strips credentials and the custom probe URL ([profiles](components/profiles.md)) |
| An imported or refreshed profile or bundle changes traffic settings or adds subscriptions unnoticed | the changed kill switch, DNS, split tunneling, routing, tethering, IPv6, log level and the added subscription hosts are shown before applying ([profiles](components/profiles.md)) |
| A managed config adds sections a client doesn't need (`api` / `metrics` expose outbounds over gRPC / pprof, `reverse` turns the client into a reverse-proxy bridge) | `mergeWithRaw` keeps only an allowlist of top-level sections and removes `reverse` from outbound settings ([xray](components/xray_config_builder.md#mergewithraw--managed-subscriptions)) |
| Apps' DNS queries leave outside the tunnel | the TUN's DNS address is the only resolver apps get; tun2socks hands port 53 to the core (xray `dns-out`, sing-box `hijack-dns`), which resolves with the configured server through the tunnel ([xray](components/xray_config_builder.md#dns), [sing-box](components/singbox_config_builder.md)); a server-made xray config keeps the server's DNS |
| Traffic leaks during reconnect | TUN is kept as a sink during reconnects and hot switches; kill switch keeps it after a failure |
| QUIC leaking when blocked | answered locally with ICMP in tun2socks, never routed `direct` |
| Backups / device transfer copy secrets | `allowBackup=false`, `dataExtractionRules` exclude everything |
| Browsing history on disk | core access logs only at `debug`; sing-box `info` mapped to `warn` |
| A shared log reveals servers or credentials | "share" on the logs screen sends a masked copy (`ShareService.shareLog`, `maskLog` in `log_service.dart`): hosts, UUIDs, passwords and share links of saved configs, subscription URLs and hosts, SOCKS credentials, any UUID, `user=`/`pass=`-like values and public IPv4/IPv6 become `<hidden>` / `<uuid>` / `<ip>`; loopback, private and link-local addresses stay. One copy, `teapod_log.txt` in the cache dir, overwritten on every export. The prefix-proxy line doesn't name the server |
| Subscription providers match one device across services by HWID | `X-Hwid` is derived per subscription host (HMAC-SHA256 under ANDROID_ID); only subscriptions added before that keep the raw id ([services](components/services.md#hwid)) |
| Self-signed subscription servers | explicit user confirmation showing the SHA-256 fingerprint; the retry trusts only the certificate shown, only for the subscription host (TOFU pin) |

## Accepted risks

- **Loopback SOCKS fingerprint.** A password-protected SOCKS on localhost answers `05 FF`: a scanner sees "a proxy
  on loopback". The Rust core keeps its SOCKS inbound only for heartbeat and the IP check.
- **Direct pings.** Pinging configs (ICMP + TCP) goes outside the tunnel, so the provider sees the server list.
- **Debug signing key.** Releases are signed with the build machine's debug key ([CI](components/ci.md#signing)) —
  changing it would break updates for existing users.
- **`xray_config.json`** with server credentials stays in `filesDir` between sessions (needed by the tile and
  auto-start). `filesDir` is process-private and excluded from backups.

## Data classification and storage

| Data | Storage | Class |
|---|---|---|
| Configs (`password`, `uuid`, keys, `rawUri`), subscription URLs, profiles, pins, active ids | flutter_secure_storage via `StorageSecureService` (AES-GCM, key wrapped by a Keystore RSA key): `vpn_configs_v2`, `subscriptions_v2`, `profiles_v1`, `pinned_refs_v1`, `active_*_v2` | SECRET |
| SOCKS user / password | in the profile's settings (encrypted); `socks_user_v2`, `socks_password_v2` (encrypted) only read by the settings migration | SENSITIVE |
| HWID cache | `cached_device_id`, `cached_device_info` (encrypted) | SENSITIVE |
| Settings (ports, DNS, split tunneling, kill switch, …) | in the active profile (`profiles_v1`, encrypted); `auto_start_on_boot` and `automation_enabled` mirrored to SharedPreferences for native code; the per-key SharedPreferences of before are only read by the migration | PUBLIC |
| Core config | `filesDir/xray_config.json` through `QuickConnectStore` | SECRET, process-private |
| Quick-reconnect parameters | `filesDir/last_connection_meta.json` (no SOCKS credentials), `socks_creds.json`, `tile_config_name.txt` (the config name the tile shows), `user_disconnected.flag` — all through `QuickConnectStore` | SENSITIVE, process-private |
| Logs | `filesDir/vpn_log.txt` (+ `.prev`) | SENSITIVE: core warnings and errors carry server and destination addresses, `debug` adds access lines; masked on export |
| Exported log | `cacheDir/teapod_log.txt` | masked, overwritten by the next export |

flutter_secure_storage moves data written by its v9 (EncryptedSharedPreferences) to its own cipher key by key on
first access. If that fails before any key moved, reads fail for that launch and the migration runs again on the next
one. `StorageSecureService.androidOptions` (shared by every instance) sets `resetOnError: false` (the plugin's default
deletes the key on a read error, all keys on a `readAll` error) and leaves `migrateWithBackup` off (that path never
migrates v9 data and reads a v9-only store as empty). Accepted risk: there is no progress marker, so a migration that
stops after some keys moved (an error, or the process killed in those milliseconds of the first launch) leaves the keys
not yet moved reading as missing (`null`).

## Rules for contributors

- No server URIs, subscription links, keys or unmasked logs in code, tests, issues or PRs.
- Anything that sends traffic outside the tunnel, opens a listener, adds an exported component or a broadcast, or
  changes what is stored where needs a line in this page and a maintainer's explicit approval.
