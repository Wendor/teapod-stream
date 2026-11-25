# ConfigProvider — configs and subscriptions

**Files:** `lib/providers/config_provider.dart`, `lib/core/models/pinned_ref.dart`, `lib/core/models/subscription.dart`,
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

Every mutator runs through `_serial()`, a FIFO on a future chain, and most through `_mutate(next)`: wait for
`build()` (`_loaded()` — a mutation never starts from a state the finishing load would overwrite), compute the next
`ConfigState` with a pure function, `_commit(current, next)`. `_commit` is the only writer of the stored state: it
saves each list or id that changed (whole lists, one write each; `ConfigStorageService` is plain load/save) and then
publishes it — after a failed write, only the parts saved before it, so memory never runs ahead of or behind
storage. A failed initial load makes mutations fail instead of writing over data that couldn't be read. Serialization
prevents a ping update and a subscription refresh from overwriting each other's changes. Inside the queue never call
a public mutator — it would deadlock.

The transitions are `ConfigState` methods without side effects: `withoutConfig`, `withoutSubscription`,
`withSubscription` (below); the rest are `copyWith` in the mutator.

## Subscriptions

`addSubscriptionFromUrl(url, {name, pinnedCertDer, replaceId})` — the download runs outside the queue, applying
it runs inside with a fresh state: `ConfigState.withSubscription(sub, fetched)`, table-tested. Configs of a
subscription get **new ids on every download**, so the refresh carries over:
- ping results, by `address:port`;
- the pinned core, by name + endpoint, or by an endpoint unique in the subscription;
- the active config, by name + endpoint → endpoint → name (names inside a subscription aren't unique); none, or it
  vanished — the first fetched one; the subscription mode is left as it is;
- the subscription name: `name ?? existing ?? profile-title ?? host` — a user rename survives auto-refresh.

The fresh state decides which subscription the download belongs to. A refresh or a `replaceId` update whose
subscription was removed during the download applies nothing — a removed subscription doesn't come back. A new URL
that was added meanwhile (another add, an import) is updated under that subscription's id — no duplicate.

`replaceId` changes the URL of an existing subscription; on a download error the old one stays intact. A
self-signed certificate raises `UntrustedCertificateException`; after the user confirms, the call is repeated with
`pinnedCertDer` = the DER of the certificate shown, which is stored as the pin (trust on first use); on later
refreshes an otherwise untrusted certificate passes only if it is that one ([services](services.md)).

`refreshStaleSubscriptions(intervalHours)` refreshes subscriptions never fetched or older than the interval; one
failure is logged and backed off for 1 h in memory (`_subFailedAt`) without stopping the others; `_refreshingSubs`
prevents parallel runs. It is triggered from `VpnNotifier.refreshStaleSubscriptionsIfDue()` on start and resume when
`subAutoRefresh` is on — there is no background timer.

`removeSubscription` (`withoutSubscription`) removes its configs and pins, and clears the selection and auto mode if
they pointed there.

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
[profiles](profiles.md); one commit for its subscriptions, configs and the selection), `reviewBundle` / `newSubscriptionHosts` (hosts of the subscriptions an import would add,
shown before it), `applySelection` (a profile's remembered server, [profiles](profiles.md#selected-server)).

## Related

[VpnProvider](vpn_provider.md) · [Services](services.md) · [Models](models.md) · [Screens](ui_screens.md)
