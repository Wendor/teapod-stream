# Profiles

**Files:** `lib/providers/profile_provider.dart`, `lib/core/models/profile.dart`, `lib/core/models/profile_bundle.dart`,
`lib/core/models/connections_bundle.dart`, `lib/core/services/profile_storage_service.dart`,
`lib/core/services/deeplink_router.dart`, `lib/core/services/deeplink_handler.dart`

A profile is a named snapshot of `AppSettings`. There is always at least one (`id = 'default'`, `isDefault`, can't
be deleted). Switching profiles writes its settings and reloads `settingsProvider`; it doesn't touch the VPN or the
selected config.

**In a profile:** all `AppSettings`, `readonly` (settings can't be changed), `sourceUrl` + `lastFetchedAt` for
profiles that refresh from a URL.
**Not in a profile:** configs and subscriptions (global), the selected config, theme.

## ProfileNotifier

| Method | What it does |
|---|---|
| `switchProfile(id)` | applies the profile's settings |
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
**after** a dialog that shows the host: the app is excluded from the tunnel, so the request goes out from the real
IP.

## Related

[SettingsProvider](settings_provider.md) · [ConfigProvider](config_provider.md) · [Security](../security.md)
