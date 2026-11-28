# GeoProvider — geodata

**Files:** `lib/providers/geo_provider.dart`, `lib/core/services/geodata_service.dart`, `GeoPresets` in
`lib/core/models/app_settings.dart`

`geoip.dat` and `geosite.dat` in `filesDir` are what the cores read for `geoip:` / `geosite:` rules and ad blocking.
`GeodataService` (`geodataServiceProvider`) does the I/O: whether both files are there, the last download time, the
download. `GeoNotifier` holds the state and the progress, and picks the tunnel.

State (sealed): `GeoMissing`, `GeoReady(lastUpdated)`, `GeoDownloading(downloaded, total)`, `GeoNeedsTrust(sha256ByUrl, changed)`, `GeoError(message)` (an `AppMessage`, [localization](localization.md)).

- **`check()`** on app start: both files present → `GeoReady`. Missing → native `prepareBinaries` copies the
  fallback bundled in `assets/binaries/` (put there by `./build.sh binaries` from the Loyalsoldier release pinned in
  `build.sh`, `GEODATA_VERSION` with SHA-256 per file; the monthly update check reports a newer release, and the pin
  is moved by a pull request), then checks again.
- **`download()`** (one at a time: a second call while one runs returns at once; a check running when it starts is finished first and discarded, so the bundled-copy extraction never overlaps the install; `check()` does nothing during a download) from `AppSettings.geoipUrl` / `geositeUrl` (`GeodataService.download`): HEAD for the total size, both files into `*.tmp`
  (hashed as they arrive, `Sha256` in `lib/core/crypto/sha256.dart`), each checked against the SHA-256 its source
  publishes next to it (`<url>.sha256sum`: Loyalsoldier, runetfreedom and v2fly do), then renamed over the old files
  only when both arrived and matched; the old files are copied to `*.bak` until both renames succeed and put back if one fails. A failure, mismatch (`geoChecksumMismatch`) or failed rename leaves both old files intact. No
  sum file (404, whatever its error page) or one whose first bytes aren't in `sha256sum` form (read as ASCII) — a
  custom source — means the file is checked against its **pin** instead: the SHA-256 the user trusted for that URL
  (SharedPreferences `geo_pins`, URL → hash). A file with no pin, or not matching it, installs nothing:
  `GeodataNeedsTrust` → `GeoNeedsTrust` (`changed` when the URL had a pin). The routing screen's geo row then says
  so (`geoUnverified` / `geoChanged`) and its REVIEW dialog shows each URL with its SHA-256; trusting calls
  `trust()`, which downloads again with those hashes as `trusted`: only files with exactly the hashes the user saw
  are installed and become the pins; content that changed after the review asks again, together with the files
  trusted in that round (so both get a pin in one step). Any other status for the sum
  is an error, so a failed request never skips the check. `releases/latest` links resolve per request: a release published
  between the file and its sum gives a mismatch, and the next download succeeds. While connected the download goes through the
  tunnel (`TunnelSocks.orDirect`, [services](services.md#tunnelsocks)): the app is excluded from TUN and GitHub's CDN
  may be blocked. Requests go through [AppHttp](services.md#apphttp). Timeouts: 15 s for HEAD, 30 s for the response
and for a stalled stream; at most 200 MB per file. The timestamp is kept in
  SharedPreferences (`geo_last_updated`).

**Sources** (`GeoPresets`): Loyalsoldier (default), runetfreedom, v2fly (its `dlc.dat` is saved as
`geosite.dat`). Loyalsoldier has no `geosite:ru`; Russian TLDs use `domain:ru` instead ([models](models.md#routingsettings)).

UI: the geo section of `RoutingScreen` — source picker, download/update with progress; geoip, geosite and ad
blocking toggles are disabled while `GeoMissing`.

## Geosite index

`GeositeIndex` (`lib/core/services/geosite_index.dart`): every code of `geosite.dat` with its domain count and the
count xray-rust gets. `geositeIndexProvider` builds it in an isolate, one build at a time; `GeoNotifier` refreshes it
after a download and after `check()` extracted the bundled files. It is cached in `filesDir/geosite.index.json` per
file version (size and mtime), so it's built once per file; the cache and the xray-rust copy are written through a
temporary file and a rename. A file that fails to parse isn't retried: the connect goes on without the index.

- Every core refuses a config referencing a code the file lacks (v2fly has no `win-spy`, a custom source may lack
  user codes): `buildEngineOptions` leaves such codes out of the user's geosite rule and ad blocking
  (`VpnEngineOptions.adBlockCodes`; none left → ad blocking off), and the connect logs them. The core sheet shows the
  same warning.
- xray-rust refuses the whole file when one entry is over 32 MiB (runetfreedom's `ru-blocked-all`,
  `antifilter-download`) and a code over 200,000 domains (Loyalsoldier's `category-ads-all`). The index writes
  `filesDir/geosite-rust.dat`, with such entries trimmed to their first domains within both limits, and
  `RustConfigBuilder` points the domain matchers at it (`ext:geosite-rust.dat:<code>` in `domain` / `domains`
  lists). The copy is written even when nothing needs trimming: quick-connect configs saved earlier reference it. The config-wide limit: [xray_config_builder](xray_config_builder.md#core-compatibility).

## Related

[SettingsProvider](settings_provider.md) · [Screens](ui_screens.md)
