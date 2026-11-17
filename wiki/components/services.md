# Services

Business logic and persistence without UI, in `lib/core/services/`. Providers create and call them.

## SubscriptionService

`fetchSubscription(url, {allowSelfSigned, pinnedCertDer, hwid, userAgent, socks})` → `SubscriptionFetchResult`
(configs, `profileTitle`, usage info, `acceptedCertDer`).

- **Request.** User-Agent = `subUserAgent` or `AppConstants.subscriptionUserAgent`; HWID headers when enabled
  (below). Connection timeout 15 s, idle timeout while reading the body 15 s, body limit 10 MB, non-200 → error.
- **Through the tunnel.** `socks` (from `tunnelSocksProvider`, only while connected) sends the request through the
  tunnel ([TunnelSocks](#tunnelsocks)).
- **Certificates.** An untrusted certificate with `allowSelfSigned = false` → `UntrustedCertificateException`; the
  UI asks the user. Once accepted, the DER is returned as `acceptedCertDer` and stored in
  `Subscription.pinnedCertDer`; later refreshes accept only that certificate (trust on first use).
- **Body formats**, tried in order: a JSON array (managed subscription: each element becomes a `VpnConfig` with
  `rawXrayConfig`), base64 of a URI list, a plain URI list. URIs go to [VlessParser](vless_parser.md).
- **Response headers:** profile title, usage (`subscription-userinfo`), announce, HWID status (`x-hwid-active`,
  `x-hwid-not-supported`, `x-hwid-max-devices-reached`).

**HTTP rule for the whole app:** close `HttpClient` with `close(force: true)` in `finally`. Without `force` a
connection with an unread body (non-200, timeout) stays ESTABLISHED forever.

### HWID

`hwidEnabled` is on by default: some panels answer a request without a non-empty `X-Hwid` with a redirect to an HTML
page, and the subscription would import zero configs. Headers: `X-Hwid` (ANDROID_ID), `X-Device-Os: Android`,
`X-Device-Model`, `X-Ver-Os`. `DeviceService` reads them over the channel once and caches them in secure storage.

## TunnelSocks

`lib/core/services/tunnel_socks.dart` — the active tunnel's local SOCKS inbound, used for the app's own downloads
(subscriptions, geodata, update APK): the app itself is excluded from the VPN, so without it these requests would
leave from the real IP.

- `apply(HttpClient, {onBadCertificate})` installs a connection factory: SOCKS, then TLS with the host of the
  actual connection (after a redirect — the new one); certificate checks go through `onBadCertificate`.
- `orDirect(socks, run)` — through the tunnel, retried directly **only** on a transport failure
  (`isTransportError`: socket, timeout, TLS, HTTP client and SOCKS errors). A server answer (HTTP error, untrusted
  certificate) is not retried, otherwise a live tunnel could be bypassed.
- Provided by `tunnelSocksProvider` (`vpn_provider.dart`), a separate provider so that `ConfigNotifier` and
  `GeoNotifier` don't depend on `VpnNotifier` (tests override it with `null`).

## Storage

| Service | Stores | Backend |
|---|---|---|
| `StorageSecureService` | configs (`vpn_configs_v2`), subscriptions, active config/subscription, pins, profiles | EncryptedSharedPreferences (Keystore AES-256-GCM) |
| `ConfigStorageService` | typed load/save of configs, subscriptions, active ids, pins | through `StorageSecureService` |
| `ProfileStorageService` | profiles, active profile id | secure + SharedPreferences |
| `SettingsService` | `AppSettings`: one key per field; SOCKS credentials in secure storage | SharedPreferences |
| `StorageMigrationService` | one-time move from plaintext SharedPreferences to secure storage (`storage_migrated_v2`) | — |

`StorageMigrationService.runIfNeeded()` runs once per process; concurrent callers (configs and settings load at the
same time) await the same run instead of reading storage before the move; a failure before the move is retried
on the next call.

## LogService

`Notifier<List<VpnLogEntry>>` over a ring buffer of `AppConstants.maxLogEntries` (1000). `add`, `addInfo/Warning/
Error/Debug`, `loadFromEntries` (restores the native `vpn_log.txt` on start), `clear`. The native side writes the
file; when `logsEnabled` is off it writes only warnings and errors.

## UpdateService

`checkForUpdate(currentVersion, abi, {channel, socks…})` → `UpdateInfo?` from GitHub `/releases?per_page=30`
(newest first, drafts dropped; `stable` also drops prereleases): the first one is the update, its APK asset is chosen
by ABI. `UpdateInfo.notes` holds the bodies of every listed release newer than the installed version up to the update,
highest version first (the update's own when nothing is newer, i.e. a reinstall). `ReleaseNotes.forLanguage(code)`
splits a body by its `### <language name>` headings (`releaseNotesLanguages`: `en` → `English`, `ru` → `Русский`, the
H1s of `changelog/*.md`, [release notes](ci.md#release-notes)) and returns the section of the app's language, else
English, else the whole body (releases before per-language notes). The app reads notes only through the GitHub API:
`raw.githubusercontent.com` is often unreachable in Russia. `downloadApk` streams
`DownloadProgress`, resumes with `Range`, and fails after 30 s without data (otherwise a stalled download — and its
cancel — hung forever). Both go through the tunnel when connected. [UpdateProvider](update_provider.md).

## Deep links

`DeeplinkRouter.parse` / `fetchFromUrl` and `DeeplinkHandler.handleUri` (dialogs, import) — [profiles](profiles.md#bundles-and-deep-links).

## Other

`DeviceService` — ANDROID_ID, model and OS version for HWID. `third_party_licenses.dart` — license texts for About.

## Related

[ConfigProvider](config_provider.md) · [SettingsProvider](settings_provider.md) · [Security](../security.md)
