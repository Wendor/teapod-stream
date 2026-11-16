# AppsProvider — installed apps

**Files:** `lib/providers/apps_provider.dart`, `lib/providers/app_icon_provider.dart`, `lib/core/models/app_info.dart`

`installedAppsProvider` (`FutureProvider<List<AppInfo>>`) asks native `getInstalledApps` once per screen visit and
returns `AppInfo(packageName, appName, isSystem, isExcluded)`, sorted by name case-insensitively. Icons are not in
that list: `appIconProvider` (`FutureProvider.family` by package) fetches each icon's PNG bytes lazily with
`getAppIcon` (raw bytes, no base64) when its row is built, and keeps them cached in memory.

`SplitTunnelScreen` combines it with `settingsProvider` (`excludedPackages` / `includedPackages`, `vpnMode`).
`SettingsNotifier.cleanGhostPackages` removes packages that are no longer installed.

Native side: `PackageManager` in `MainActivity`; the manifest declares `QUERY_ALL_PACKAGES` for Android 11+ package visibility.

## Related

[SettingsProvider](settings_provider.md) · [Screens](ui_screens.md) · [Android native](android_native.md)
