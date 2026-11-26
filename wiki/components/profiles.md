# Profiles

**Files:** `lib/providers/profile_provider.dart`, `lib/core/models/profile.dart`, `lib/core/models/profile_bundle.dart`,
`lib/core/models/connections_bundle.dart`, `lib/core/services/profile_storage_service.dart`,
`lib/core/services/deeplink_router.dart`, `lib/ui/deeplink_handler.dart`

A profile is a named snapshot of `AppSettings` plus the server selected under it. There is always at least one
(`id = 'default'`, `isDefault`, can't be deleted).

**In a profile:** all `AppSettings`, `readonly` (settings can't be changed), `sourceUrl` + `lastFetchedAt` for
profiles that refresh from a URL, `selection` — the selected server.
**Not in a profile:** configs and subscriptions (global), theme.

## Selected server

`selection` is a `ConfigSelection` (`config_selection.dart`): the chosen config — its id, and a `PinnedRef`
(subscription, name, `address:port`) for when the id is gone after a subscription refresh — and the subscription
in auto-select mode. It is recorded on switch, not on every selection change: `switchProfile` stores
the current selection (`ConfigState.selection`) in the outgoing profile, and in the incoming one too if it has none
yet (`null` — a profile created before this field, or never active). Then the incoming profile becomes active (its settings are the ones in force) and
`ConfigNotifier.applySelection` restores its selection; whatever no longer exists is skipped, and if nothing of it is left the current
selection stays. Bundles never carry it: export clears it, import doesn't read it. Every write of the
profile list (switch with restoring the selection, a settings change, create, rename, delete, read-only, import, the
merge after a refresh download) runs through one queue and re-reads the state inside it, so none drops another's
change; a settings save writes to the profile that was active when it was called, and the switch reads the
outgoing selection through the configs queue (`ConfigNotifier.currentSelection`).

## ProfileNotifier

| Method | What it does |
|---|---|
| `switchProfile(id)` | remembers the outgoing profile's server, makes the profile active (its settings apply), then restores its server; false — nothing to switch. The app switches through `VpnNotifier.switchProfile(id)`, which runs it inside `duringProfileSwitch`: the VPN follows the final state (a live tunnel is rebuilt if the server or connection settings changed), also when restoring the server failed. (`ProfileNotifier` can't read `vpnProvider`: that one depends on the settings, which derive from profiles.) |
| `updateActiveSettings(change, {profileId})` | the only writer of the settings in force (`SettingsNotifier` calls it): queued, refused for a read-only profile, mirrors the native flags ([settings](settings_provider.md)) |
| `refreshProfile(id, url, {confirm})` | downloads the profile again (`BundleLoader.fetch`); if it changes traffic settings or adds subscriptions, `confirm` is asked first; applies settings, imports its connections. Returns a `ProfileRefresh`: `ProfileRefreshed`, `ProfileRefreshDeclined` (nothing applied) or `ProfileRefreshFailed(reason)` — the download's reason, or `profileUpdateError` when the profile is gone |
| `reviewImport(bundle)` | the `ImportReview` shown before `importBundle` (below) |
| `importBundle(bundle, …)` | adds a profile and imports its connections through `ConfigNotifier.importBundle` (deduplicated by subscription URL / server); returns its id. The UI imports through `VpnNotifier.importProfile(bundle, {makeReadonly, sourceUrl, switchTo})`, which calls it and then switches to the profile (`switchTo`, default true) |
| `exportBundle` | a `ProfileBundle` for sharing |

**Security fields stay local** (`_keepLocalSecurity`): an imported or refreshed profile never sets the SOCKS port and
credentials, `randomPort`/`randomCredentials`, `proxyOnly`, `hwidEnabled`, `automationEnabled`, the heartbeat
target or the geodata sources (`geoipUrl`/`geositeUrl`) — otherwise one tap on a link could open an unauthenticated
proxy, send probes to an attacker's URL or take routing decisions from a foreign file.
Export strips the SOCKS credentials and the custom heartbeat URL.

**Shown before applying.** The other settings are the point of a profile and are applied, but the user sees first
what changes the way traffic goes: `ImportReview` (`lib/core/models/import_review.dart`) lists the changed kill
switch, DNS, split tunneling (mode and app lists), routing rules, tethering through VPN, IPv6 and log level (against
the settings in force; for a refresh, against the profile's own), and the hosts of subscriptions the import adds (ones
already present are skipped; the app fetches the added ones itself later, with HWID headers when enabled). The
deep link dialogs embed it (`ImportReviewDetails`); a pasted profile, a pasted `teapod://import/connections` link on
the Add screen and a profile refresh ask through `confirmImportReview` when the review isn't empty.

## Storage

| Data | Key | Storage |
|---|---|---|
| Profiles (with the settings in force: the active one's) | `profiles_v1` | flutter_secure_storage (`StorageSecureService`) |
| Active profile id | `active_profile_id` | SharedPreferences |

## Bundles and deep links

`ProfileBundle` (profile + optional configs and subscriptions) and `ConnectionsBundle` (connections only) are JSON
encoded as base64url without padding. `ConnectionsBundle` has a full form (config objects) and a compact one
(`rawUris` + `subscriptionUrls`); export always uses the compact form, `fromJson` reads both.

| Link | Content |
|---|---|
| `teapod://import/profile?data=<base64url>` | inline profile |
| `teapod://import/profile?url=https://…` | profile downloaded from a URL |
| `teapod://import/connections?data=<base64url>` | connections |

Flow: `MainActivity` → `deeplink` event on the shared event stream → `DeeplinkHandler.handleUri` →
`DeeplinkRouter.parse` → `BundleLoader.load` → confirmation dialog → import. A `url=` link is accepted only over
https and is downloaded **after** a dialog that shows the host.

`BundleLoader` (`lib/core/services/bundle_loader.dart`, `bundleLoaderProvider` in `profile_provider.dart`, which reads
the tunnel SOCKS at each download) returns a `BundleLoad`: `ProfileLoaded(bundle, sourceUrl)`,
`ConnectionsLoaded(bundle)` or `BundleFailed(reason)` — `bundleFetchFailed` (network, non-200, refused URL, over the
limit) or `bundleInvalid` with the parser's message. `load(link)` returns an inline bundle or downloads the linked
one; `profileInput(text)` takes what is pasted into the profile import (a profile link or a bundle's JSON);
`fetch(url, type)` downloads, also for `refreshProfile`. The download goes through [AppHttp](services.md#apphttp): https only including redirects, at most 1 MB, through the tunnel when
connected and directly when the tunnel fails; without a tunnel it goes out from the real IP.

## Related

[SettingsProvider](settings_provider.md) · [ConfigProvider](config_provider.md) · [Security](../security.md)
