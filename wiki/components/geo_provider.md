# GeoProvider — geodata

**Files:** `lib/providers/geo_provider.dart`, `GeoPresets` in `lib/core/services/settings_service.dart`

`GeoNotifier` manages `geoip.dat` and `geosite.dat` in `filesDir`, which the cores read for `geoip:` / `geosite:`
rules and ad blocking.

State (sealed): `GeoMissing`, `GeoReady(lastUpdated)`, `GeoDownloading(downloaded, total)`, `GeoError(message)`.

- **`check()`** on app start: both files present → `GeoReady`. Missing → native `prepareBinaries` copies the
  fallback bundled in `assets/binaries/` (put there by `./build.sh binaries` from the Loyalsoldier release pinned in
  `build.sh`, `GEODATA_VERSION` with SHA-256 per file; the monthly update check moves it), then checks again.
- **`download()`** from `AppSettings.geoipUrl` / `geositeUrl`: HEAD for the total size, both files into `*.tmp`,
  then an atomic rename — a failure leaves the old files intact. While connected the download goes through the
  tunnel (`TunnelSocks.orDirect`, [services](services.md#tunnelsocks)): the app is excluded from TUN and GitHub's CDN
  may be blocked. Timeouts: 15 s for HEAD, 30 s for the response and for a stalled stream. The timestamp is kept in
  SharedPreferences (`geo_last_updated`).

**Sources** (`GeoPresets`): Loyalsoldier (default), runetfreedom, v2fly (its `dlc.dat` is saved as
`geosite.dat`). Loyalsoldier has no `geosite:ru`; Russian TLDs use `domain:ru` instead ([models](models.md#routingsettings)).

UI: the geo section of `RoutingScreen` — source picker, download/update with progress; geoip, geosite and ad
blocking toggles are disabled while `GeoMissing`.

## Related

[SettingsProvider](settings_provider.md) · [Screens](ui_screens.md)
