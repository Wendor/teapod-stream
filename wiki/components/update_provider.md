# UpdateProvider — app updates

**Files:** `lib/providers/update_provider.dart`, `lib/core/services/update_service.dart`

`UpdateNotifier` checks GitHub releases, downloads the APK and hands it to the installer. The channel (`stable` /
`beta`) is `AppSettings.updateChannel`; release selection lives in [UpdateService](services.md#updateservice).

State (sealed): `UpdateIdle`, `UpdateChecking`, `UpdateUpToDate(info)`, `UpdateAvailable(info, resumableBytes)`,
`UpdateDownloading(info, downloaded, total)`, `UpdateDownloaded(info, filePath)`, `UpdateError(message, retryInfo)`.

| Method | Behaviour |
|---|---|
| `checkForUpdate()` | device ABI (`getAbi`); outside `AppConstants.supportedAbis` → error; newer → `UpdateAvailable`, same → `UpdateUpToDate` (allows reinstall) |
| `startDownload(info)` | streams `downloadApk` into `teapod-update-<abi>-<version>.apk`, resuming a partial file; through the tunnel when connected |
| `cancelDownload()` | back to `UpdateAvailable` with `resumableBytes`; takes effect on the next chunk or the 30 s idle timeout |
| `reinstall(info)` | deletes the cached APK of this version, then downloads |
| `installApk(path)` | native `installApk` (`FileProvider` + `ACTION_VIEW`) |

`_cleanOldApks(keepPath)` removes other `teapod-update-*.apk` files so the installer never picks a stale one
("Cannot parse package").

UI: the update row in Settings → system (at the top when an update is available) with the notes of each version
between the installed one and the update, in the app's language (`ReleaseNotes.forLanguage`). Settings → about →
changelog opens `WhatsNewScreen`: the whole history from the bundled `changelog/<lang>.md` asset (English when there is
no file for the app's language), offline.
