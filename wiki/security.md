# Security

**Threat model.** A malicious app on the same device wants to learn that a VPN is on, find the server, or learn the
real IP; a link or a subscription tries to change security-relevant settings. A rooted device is out of scope.
Vulnerabilities are reported privately (GitHub security advisories), not in issues: [SECURITY.md](../SECURITY.md)
says how, and what counts.

## Protections

| Threat | Protection |
|---|---|
| An excluded app binds a socket to `tun0` (`SO_BINDTODEVICE`) and learns the VPN and the server's IP | per-flow owner check in tun2socks / TUN admission (`TunOwnerPolicy`): UID `-1` is blocked in `onlySelected` and in `allExcept` with exclusions, unless "tethering through VPN" is on ([android_native](components/android_native.md#split-tunneling-and-owner-validation)); the cache is keyed by the full 5-tuple |
| Local SOCKS used by other apps | in TUN mode credentials are always set (random, or generated when the manual ones are empty); the Rust probe inbound uses a one-time password |
| `PrefixTcpProxy` reachable by others | loopback only, own UID only |
| State broadcast reveals the VPN | `STATE_CHANGED` is sent only with the automation option (off by default), without the port |
| An app turns the VPN off through `VpnCommandReceiver` | commands are ignored unless automation is on |
| Deep link `?url=` makes the app fetch an attacker URL from the real IP | https only (redirects too), at most 1 MB, downloaded after a dialog showing the host, through the tunnel when connected |
| An imported profile opens a noauth proxy or redirects probes | security fields stay local; export strips credentials and the custom probe URL ([profiles](components/profiles.md)) |
| `api` / `metrics` in a managed config expose outbounds over gRPC / pprof | removed by `mergeWithRaw` |
| Apps' DNS queries leave outside the tunnel | the TUN's DNS address is the only resolver apps get; tun2socks hands port 53 to the core (xray `dns-out`, sing-box `hijack-dns`), which resolves with the configured server through the tunnel ([xray](components/xray_config_builder.md#dns), [sing-box](components/singbox_config_builder.md)); a server-made xray config keeps the server's DNS |
| Traffic leaks during reconnect | TUN is kept as a sink during reconnects and hot switches; kill switch keeps it after a failure |
| QUIC leaking when blocked | answered locally with ICMP in tun2socks, never routed `direct` |
| Backups / device transfer copy secrets | `allowBackup=false`, `dataExtractionRules` exclude everything |
| Browsing history on disk | core access logs only at `debug`; sing-box `info` mapped to `warn` |
| Self-signed subscription servers | explicit user confirmation, then only that certificate is trusted (TOFU pin) |

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
| SOCKS user / password | `socks_user_v2`, `socks_password_v2` (encrypted) | SENSITIVE |
| HWID cache | `device_id_v2`, `device_info_v2` (encrypted) | SENSITIVE |
| Other settings (ports, DNS, split tunneling, kill switch, …) | SharedPreferences | PUBLIC |
| Core config | `filesDir/xray_config.json` | SECRET, process-private |
| Quick-reconnect parameters | `filesDir/last_connection_meta.json` (no SOCKS credentials), `socks_creds.json` | SENSITIVE, process-private |
| Logs | `filesDir/vpn_log.txt` (+ `.prev`) | may contain hosts at `debug` |

`StorageMigrationService` moved data from plaintext SharedPreferences to encrypted storage once
(`storage_migrated_v2`); on a Keystore error the flag isn't set and it retries next launch.

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
