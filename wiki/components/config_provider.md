# ConfigProvider — configs and subscriptions

**Files:** `lib/providers/config_provider.dart`, `lib/core/models/pinned_ref.dart`,
`lib/core/services/config_storage_service.dart`, `lib/core/services/subscription_service.dart`

`ConfigNotifier` (`AsyncNotifier<ConfigState>`) owns the list of configs and subscriptions: loading, adding,
removing, ordering, the active selection, pins, subscription refresh and import of connection bundles.

## State: `ConfigState`

| Field | Meaning |
|---|---|
| `configs` | all `VpnConfig`s; order within a group = position in this list |
| `subscriptions` | `Subscription`s in display order |
| `activeConfigId` | the selected config (also the one native reconnects to) |
| `activeSubscriptionId` | auto mode: connect to the best config of this subscription |
| `pins` | `List<PinnedRef>` — pinned connections |

`activeConfigId` and `activeSubscriptionId` are not exclusive. A manual `setActiveConfig()` turns auto mode off.

**`effectiveConfigProvider`** — the config the next `connect()` uses: in auto mode the subscription's config with
the lowest `latencyMs` (never-pinged last), otherwise the active config. Used by `VpnNotifier` and Home.

`configsBySubscription` groups configs by `subscriptionId`; standalone configs are under `null`.

## Mutation queue

Every mutator runs through `_serial()`, a FIFO on a future chain. Each does "read state → load-modify-save →
set state"; run concurrently (a ping in the middle of a subscription refresh) they overwrote each other. Inside
the queue never call a public mutator — it would deadlock; use the private variant (`_setActiveConfig`).

## Subscriptions

`addSubscriptionFromUrl(url, {name, allowSelfSigned, replaceId})` — the download runs outside the queue, applying
it runs inside with a fresh state. Configs of a subscription get **new ids on every download**, so the refresh
carries over:
- ping results, by `address:port`;
- the active config, by name + endpoint → endpoint → name (names inside a subscription aren't unique);
- the subscription name: `name ?? existing ?? profile-title ?? host` — a user rename survives auto-refresh.

`replaceId` changes the URL of an existing subscription; on a download error the old one stays intact. A
self-signed certificate raises `UntrustedCertificateException`; after the user confirms, its DER is pinned
(trust on first use) and later refreshes require the same certificate ([services](services.md)).

`refreshStaleSubscriptions(intervalHours)` refreshes subscriptions never fetched or older than the interval; one
failure is logged and backed off for 1 h in memory (`_subFailedAt`) without stopping the others; `_refreshingSubs`
prevents parallel runs. It is triggered from `VpnNotifier.refreshStaleSubscriptionsIfDue()` on start and resume when
`subAutoRefresh` is on — there is no background timer.

`removeSubscription` removes its configs and clears auto mode if it pointed there.

## Pins

`PinnedRef(subscriptionId?, name, endpoint?)` identifies a config so that it survives subscription refreshes.
`resolve()`: exact (subscription, name, `address:port`) match, otherwise the first config with that name.
`resolvedPins` gives `(ref, config?)` — null is a lost pin, shown as such. Stored in `StorageSecureService`
(`pinned_refs_v1`).

## Other mutators

`addConfig(s)`, `updateConfig`, `removeConfig` (clears the selection if it was active), `renameSubscription`,
`reorderSubscriptions` / `reorderGroupConfigs(subId, …)` (indices from `ReorderableListView.onReorderItem`:
`newIndex` is the position after the move),
`batchUpdatePingResults` (one write for all pings), `importBundle` (connections from a profile or deep link,
[profiles](profiles.md)), `applySelection` (a profile's remembered server, [profiles](profiles.md#selected-server)).

## Related

[VpnProvider](vpn_provider.md) · [Services](services.md) · [Models](models.md) · [Screens](ui_screens.md)
