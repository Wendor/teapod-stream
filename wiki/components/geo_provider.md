# GeoProvider — geodata

**Files:** `lib/providers/geo_provider.dart`, `lib/core/services/geodata_service.dart`, `GeoPresets` in
`lib/core/models/app_settings.dart`

`geoip.dat` and `geosite.dat` in `filesDir` are what the cores read for `geoip:` / `geosite:` rules and ad blocking.
`GeodataService` (`geodataServiceProvider`) does the I/O: whether both files are there, the last download time, the
download. `GeoNotifier` holds the state and the progress, and picks the tunnel.

State (sealed): `GeoMissing`, `GeoReady(lastUpdated)`, `GeoDownloading(downloaded, total)`, `GeoError(message)` (an `AppMessage`, [localization](localization.md)).

- **`check()`** on app start: both files present → `GeoReady`. Missing → native `prepareBinaries` copies the
  fallback bundled in `assets/binaries/` (put there by `./build.sh binaries` from the Loyalsoldier release pinned in
  `build.sh`, `GEODATA_VERSION` with SHA-256 per file; the monthly update check reports a newer release, and the pin
  is moved by a pull request), then checks again.
- **`download()`** from `AppSettings.geoipUrl` / `geositeUrl` (`GeodataService.download`): HEAD for the total size, both files into `*.tmp`,
  then an atomic rename — a failure leaves the old files intact. While connected the download goes through the
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
