# Services

Business logic and persistence without UI, in `lib/core/services/`. Each service has a provider next to it
(`settingsServiceProvider`, `profileStorageServiceProvider`, `configStorageServiceProvider`,
`subscriptionServiceProvider`, `updateServiceProvider`, `deviceServiceProvider`, `platformServiceProvider`); notifiers
read a service through it and never construct one, so a test swaps a service with an override.

## SubscriptionService

`fetchSubscription(url, {pinnedCertDer, hwid, userAgent, socks})` → `SubscriptionFetchResult`
(configs, `profileTitle`, usage info, `acceptedCertDer`).

- **Request** through [AppHttp](#apphttp) with its defaults (15 s timeouts, body limit 10 MB). User-Agent =
  `subUserAgent` or `AppConstants.subscriptionUserAgent`; HWID headers when enabled (below). Non-200 → error.
- **Through the tunnel.** `socks` (from `tunnelSocksProvider`, only while connected) sends the request through the
  tunnel, directly when the tunnel fails ([TunnelSocks](#tunnelsocks)).
- **Certificates.** An untrusted certificate of the subscription host → `UntrustedCertificateException` (host,
  subject, issuer, the presented `der` and its `sha256Fingerprint`); the UI asks the user
  (`confirmUntrustedCertificate`). On an untrusted certificate after a redirect to another host the fetch just fails:
  nothing is offered to accept. On "continue" the fetch is repeated with `pinnedCertDer: e.der`. The pin is returned
  as `acceptedCertDer` and stored in `Subscription.pinnedCertDer` (trust on first use); it lets through only that
  exact certificate, only from the subscription host, and only when normal verification fails — a certificate that
  passes verification is accepted as usual. There is no "accept any certificate" mode. `sha256()` is a local FIPS 180-4 implementation (`lib/core/crypto/sha256.dart`, no hashing dependency).
- **Body formats**, tried in order: a JSON array (managed subscription: each element becomes a `VpnConfig` with
  `rawXrayConfig`), base64 of a URI list, a plain URI list. URIs go to [VlessParser](vless_parser.md).
- **Response headers:** profile title, usage (`subscription-userinfo`), announce, HWID status (`x-hwid-active`,
  `x-hwid-not-supported`, `x-hwid-max-devices-reached`).

**HTTP rule for the whole app:** the app's own requests go through [AppHttp](#apphttp); it closes its `HttpClient`
with `close(force: true)`. Without `force` a connection with an unread body (non-200, timeout) stays ESTABLISHED
forever.

### HWID

`hwidEnabled` is on by default: some panels answer a request without a non-empty `X-Hwid` with a redirect to an HTML
page, and the subscription would import zero configs. Headers: `X-Hwid`, `X-Device-Os: Android`,
`X-Device-Model`, `X-Ver-Os`. `DeviceService` reads them over the channel once and caches them in secure storage.
`X-Hwid` is per subscription host: `HwidDeviceInfo.forHost` — hex HMAC-SHA256 of the lower-cased host under
ANDROID_ID (`hmacSha256` in `lib/core/crypto/sha256.dart`), so providers can't match one device across services. A subscription
with `rawHwid` (stored before per-host ids) keeps sending ANDROID_ID while its URL keeps the same host.

## AppHttp

`lib/core/services/app_http.dart` — the one HTTP client for the app's own requests: subscriptions, geodata, update
check and APK, IP lookup, profile and bundle downloads. Ping and delay measurement stay out of it: they go direct
by design.

- `client({socks, onBadCertificate})` — an `HttpClient` through [TunnelSocks](#tunnelsocks) when `socks` is given,
  connection timeout 15 s.
- `open(url, {method, socks, headers, httpsOnly, maxBytes, timeout, idleTimeout, onBadCertificate})` → `AppHttpStream`
  with the body unread; the caller calls `close()` in `finally`. `timeout` (15 s) covers the connection and the
  response headers, `idleTimeout` (15 s) each wait for the next body chunk. Redirects (up to 5) are followed here,
  so `httpsOnly` holds for every hop.
- `get(url, …)` → `AppHttpResponse` (status, headers, bytes): the body is read only for a 2xx status (an error body
  may never end).
- Limits: `maxBytes` (10 MB by default) is checked against `Content-Length` before the body and while reading it.
  Refusals (non-https URL, body over the limit, and — on a client `open` creates itself — a certificate rejected by
  `onBadCertificate` or by default) throw `AppHttpException`, which is not a transport error, so `orDirect` doesn't
  retry it outside the tunnel.
- `open` / `get` with `client:` (from `client()`) share one client; its owner closes it, which ends every request
  still running on it (the IP lookup chain stops waiting for a slow service but must not leave it running). A
  certificate rejection on such a client stays a `TlsException`, so a shared client is never used under `orDirect`.

| Caller | Tunnel | Limits |
|---|---|---|
| subscriptions (`SubscriptionService`) | `orDirect` | defaults |
| geodata (`GeodataService`, from `GeoNotifier`) | `orDirect` | 30 s, 200 MB per file |
| update check, APK (`UpdateService`) | when connected, no direct retry | defaults; APK: 30 s idle, 500 MB for the whole file, a resumed part included |
| IP lookup (`IpLookup.lookupThrough`, from `IpInfoNotifier`) | always (it asks for the tunnel's exit) | 64 KB |
| deep link and profile bundles (`BundleLoader.fetch`) | `orDirect` | https only, 1 MB |

## TunnelSocks

`lib/core/services/tunnel_socks.dart` — the active tunnel's local SOCKS inbound, used by [AppHttp](#apphttp): the
app itself is excluded from the VPN, so without it the app's own requests would leave from the real IP.

- `apply(HttpClient, {onBadCertificate})` installs a connection factory: SOCKS, then TLS with the host of the
  actual connection (after a redirect — the new one); certificate checks go through `onBadCertificate`.
- `orDirect(socks, run)` — through the tunnel, retried directly **only** on a transport failure
  (`isTransportError`: socket, timeout, TLS, HTTP client and SOCKS errors). A server answer (HTTP error, untrusted
  certificate) is not retried, otherwise a live tunnel could be bypassed.
- Provided by `tunnelSocksProvider` (`vpn_provider.dart`): a holder that `VpnNotifier` fills on every state change
  (`listenSelf`), with no dependencies of its own. `ConfigNotifier`, `GeoNotifier`, `ProfileNotifier` and the deep
  link UI read it; if it watched
  `vpnProvider`, the read would close a cycle (`vpnProvider` → `activeCoreProvider` → `configProvider`), which Riverpod
  refuses in debug builds.

## Storage

| Service | Stores | Backend |
|---|---|---|
| `StorageSecureService` | configs (`vpn_configs_v2`), subscriptions, active config/subscription, pins, profiles | flutter_secure_storage (AES-GCM, key wrapped by a Keystore RSA key) |
| `ConfigStorageService` | typed whole-list load/save of configs, subscriptions, active ids, pins (written only by `ConfigNotifier._commit`) | through `StorageSecureService` |
| `ProfileStorageService` | profiles, active profile id | secure + SharedPreferences |
| `SettingsService` | the per-key `AppSettings` of before profiles held them, read once by the migration; mirrors the flags native reads | SharedPreferences (+ secure for the old SOCKS login) |
| `UiPrefsService` | the device's look and list view, outside profiles: language (`app_locale`, also read by native), theme mode, accent, the server list's `cfg_hide_groups` / `cfg_sort_by_ping`; read by `localeProvider`, `themeModeProvider`, `accentProvider`, `configsViewProvider` (a choice made while the stored value loads wins) | SharedPreferences |

## LogService

`Notifier<List<VpnLogEntry>>` over a ring buffer of `AppConstants.maxLogEntries` (1000). `add`, `addInfo/Warning/
Error/Debug`, `loadFromEntries` (restores the native `vpn_log.txt` on start), `clear`. The native side writes the
file; when `logsEnabled` is off it writes only warnings and errors.

`maskLog(text, secrets:)` prepares the file for sharing; `logSecrets(configs:, subscriptions:, extra:)` collects the
known values it hides. What is masked: [security](../security.md).

## UpdateService

`checkForUpdate(currentVersion, abi, {channel, socks…})` → `UpdateInfo?` from GitHub `/releases?per_page=30`
(newest first, drafts dropped; `stable` also drops prereleases and falls back to `/releases/latest` when the page has
no stable release): the first one is the update, its APK asset is chosen by ABI. Versions compare by the leading
digits of each part (`1.9.2-beta` is `1.9.2`). `UpdateInfo.notes` holds the bodies of every listed release newer than the installed version up to the update,
highest version first (the update's own when nothing is newer, i.e. a reinstall). `ReleaseNotes.forLanguage(code)`
splits a body at its `### <language name>` headings (other `###` lines stay in their section) (`releaseNotesLanguages`: `en` → `English`, `ru` → `Русский`, the
H1s of `changelog/*.md`, [release notes](ci.md#release-notes)) and returns the section of the app's language, else
English, else the whole body (releases before per-language notes). The app reads notes only through the GitHub API:
`raw.githubusercontent.com` is often unreachable in Russia. `downloadApk` streams
`DownloadProgress`, resumes with `Range`, and fails after 30 s without data (otherwise a stalled download — and its
cancel — hung forever). Both go through [AppHttp](#apphttp) and the tunnel when connected. [UpdateProvider](update_provider.md).

## Deep links

`DeeplinkRouter.parse` reads a link; `BundleLoader` returns the bundle it carries or downloads it, and loads pasted
profiles and profile refreshes ([AppHttp](#apphttp)); `DeeplinkHandler.handleUri` shows the dialogs and imports —
[profiles](profiles.md#bundles-and-deep-links).

## PlatformService

Typed wrappers for the native calls on `com.teapodstream/vpn` that aren't about the tunnel: `binaryVersions`,
`availableEngines`, `installedApps`, `appIcon`, `filesDir`, `prepareBinaries`, `countryForIp`, `abi`, `installApk`, `openBatteryOptimizationSettings`, `deviceId`,
`deviceInfo`. Channel errors reach the caller, which keeps its own fallback. Providers read it through
`platformServiceProvider`, so tests override the service instead of mocking the channel; `main.dart` uses a
`const PlatformService()`.

## Other

`ShareService` — writes a file to the cache dir and opens the share sheet: `shareProfile` (`<name>.json`), `shareLog` (the native log masked by `maskLog` into one `teapod_log.txt`, overwritten on every export; false — an empty log). `DeviceService` — ANDROID_ID, model and OS version for HWID, cached in memory per instance (one per container). `third_party_licenses.dart` — license texts for About.

## Related

[ConfigProvider](config_provider.md) · [SettingsProvider](settings_provider.md) · [Security](../security.md)
