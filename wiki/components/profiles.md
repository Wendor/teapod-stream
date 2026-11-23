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
yet (`null` — a profile created before this field, or never active). Then the incoming profile's settings are reloaded and
`ConfigNotifier.applySelection` restores its selection; whatever no longer exists is skipped, and if nothing of it is left the current
selection stays. Bundles never carry it: export clears it, import doesn't read it. Every write of the
profile list (switch with restoring the selection, settings sync, create, rename, delete, read-only, import, the
merge after a refresh download) runs through one queue and re-reads the state inside it, so none drops another's
change; a sync writes to the profile that was active when the settings were saved, and the switch reads the
outgoing selection through the configs queue (`ConfigNotifier.currentSelection`).

## ProfileNotifier

| Method | What it does |
|---|---|
| `switchProfile(id)` | remembers the outgoing profile's server, applies the profile's settings, then its server, inside `VpnNotifier.duringProfileSwitch`: the VPN follows the final state (a live tunnel is rebuilt if the server or connection settings changed), also when restoring the server failed |
| `syncActiveSettings(settings)` | called by `SettingsNotifier.save()`: keeps the active profile's snapshot current |
| `refreshProfile(id, url)` | downloads the profile again, applies settings, imports its connections |
| `importBundle(bundle, …)` | adds a profile and imports its connections through `ConfigNotifier.importBundle` (deduplicated by subscription URL / server) |
| `exportBundle` | a `ProfileBundle` for sharing |

**Security fields stay local** (`_keepLocalSecurity`): an imported or refreshed profile never sets the SOCKS port and
credentials, `randomPort`/`randomCredentials`, `proxyOnly`, `hwidEnabled`, `automationEnabled` or the heartbeat
target — otherwise one tap on a link could open an unauthenticated proxy or send probes to an attacker's URL.
Export strips the SOCKS credentials and the custom heartbeat URL.

## Storage

| Data | Key | Storage |
|---|---|---|
| Profiles | `profiles_v1` | flutter_secure_storage (`StorageSecureService`) |
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
`DeeplinkRouter.parse` → confirmation dialog → import. A `url=` link is accepted only over https and is downloaded
**after** a dialog that shows the host. The download (`DeeplinkRouter.fetchBundle`, also used by `refreshProfile`)
goes through [AppHttp](services.md#apphttp): https only including redirects, at most 1 MB, through the tunnel when
connected and directly when the tunnel fails; without a tunnel it goes out from the real IP.

## Related

[SettingsProvider](settings_provider.md) · [ConfigProvider](config_provider.md) · [Security](../security.md)
