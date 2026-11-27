# UI — screens and widgets

**Directory:** `lib/ui/` (`screens/`, `widgets/`, `theme/`), shell in `lib/app.dart`.

A "console" look on Material 3: mono + sans fonts, hex section addresses (`0x10 diagnostics`), square switches,
breadcrumbs. Dark, light or system theme with an accent color.

Widgets import `package:flutter/material.dart` (and `app.dart` the `flutter_localizations` delegates), which Flutter
deprecates in favour of the `material_ui` package; each such line carries `// ignore: deprecated_member_use`. Moving to
`material_ui` is a separate change: fl_chart and mobile_scanner still build on the SDK's Material library, and two
copies of `Theme` would not see each other.

## Navigation

```
TeapodApp (app.dart) → _TeapodMaterialApp (theme, locale, text scale; builder sets L10n.current)
└── _AppShell — tabs via tabIndexProvider, custom bottom bar (its settings tab shows the update badge from updateProvider)
    ├── 0 HomeScreen
    ├── 1 ConfigsScreen      → AddConfigScreen → QrScanScreen
    ├── 2 RoutingScreen      → SplitTunnelScreen
    └── 3 SettingsScreen     → LogsScreen, SubscriptionSettingsScreen, NetworkSettingsScreen,
                               DnsSettingsScreen, ProfilesScreen
```

`_AppShell` also listens to `XrayEngine.events` for deep links and hands the app's lifecycle to
`appLifecycleProvider` (`lib/providers/app_lifecycle_provider.dart`, next to `tabIndexProvider`): `start()` after the
first frame, `resumed()` / `paused()` from its observer. The notifier holds the steps and their order — at start the
log restore, `autoSwitchProvider`, the stale ping, the geodata check, auto-connect (`autoConnect` on, an effective
config, the VPN not already up or coming up), the subscription refresh after both the log restore and the VPN sync,
the update check after 5 s; on resume the stats polling, the sync, then the refresh; on pause the stats polling
stops. It also pings configs that were added and pulls the chart only on the home tab. The system bars follow the theme
through an `AnnotatedRegion<SystemUiOverlayStyle>` around its scaffold. Deep-link imports (profile or connections)
share one confirmation dialog in `DeeplinkHandler` (`_showImportDialog`).

## Screens

| Screen | What's on it |
|---|---|
| `HomeScreen` | hero panel: power button (`_PowerCore`), state with the error reason for FAILED/BLOCKED, server, exit IP, core line (`[core] xray-core ›`, tap → core sheet), speeds and the live chart; server picker sheet; warning for managed configs |
| `ConfigsScreen` | groups: pinned → local → subscriptions (collapsible, drag to reorder in sort mode); flat mode and sort-by-ping (`configsViewProvider`); auto-select per subscription; context menus (pin, core, copy/QR, edit, rename, refresh, delete); export of all connections as a compact `teapod://import/connections` link |
| `AddConfigScreen` | one input for links, subscription URLs (`http(s)://`), WireGuard `.conf` text, `vpn://` keys and `teapod://import/connections`; QR scan |
| `RoutingScreen` | direction (global / bypass / only selected), kill switch, split tunneling entry, sniffing, geo data (source, download), domain zones, sites, geosite/geoip codes, Russian services, ad block |
| `SplitTunnelScreen` | app list with lazy icons, mode, tethering through VPN (`allExcept` only), cleans uninstalled packages |
| `SettingsScreen` | `0x10` diagnostics (logs) · `0x20` appearance (theme, language, font size, accent) · `0x30` connection (auto-connect, boot, notification, automation, subscriptions) · `0x40` network (network screen, DNS screen, core order) · `0x50` system (profiles, battery optimization → the system prompt, update channel) · `0x60` about (version, changelog → `WhatsNewScreen`, licenses, source). An available update is shown first |
| `NetworkSettingsScreen` | local proxy, proxy-only, UDP/ICMP/QUIC, IPv6, MTU, TLS fingerprint, fragment, noise, Mux, heartbeat, observatory interval |
| `DnsSettingsScreen` | DNS mode, server presets and custom server, query strategy |
| `SubscriptionSettingsScreen` | HWID, auto-refresh and interval, User-Agent |
| `ProfilesScreen` | profile cards: switch, rename, read-only, export link/QR, import, refresh from URL, delete |
| `WhatsNewScreen` | release history from the bundled `changelog/<lang>.md` (English fallback): versions and their bullets (`parseChangelog`) |
| `LogsScreen` | log list with auto-scroll, share a masked copy of the file ([security](../security.md)), clear, logging on/off, tunnel diagnostics |

## Cores in the UI

- **Core order** (Settings → network → cores, `_CoreOrderList`): cores by priority with versions; "↑" moves a core up,
  the switch disables it (the last enabled one can't be disabled); a core that doesn't load on the device is greyed
  out. No drag and drop: a nested `ReorderableListView` broke the outer list's height.
- **Config rows** show ` · sing-box` when the config doesn't run on the first enabled core; a config no core can run is
  dimmed with the reason (`CoreSupportGate`).
- **Core sheet** (`core_sheet.dart`, from the config menu or Home): every core in check order — in use (with ignored
  settings), compatible, or the refusal reason; pin a core or AUTO.
- **`FeatureGate`**: a setting a core doesn't support stays editable (other cores apply it) with "Not supported:
  sing-box, xray-rust." under it, computed from `CoreBackend.supports`.

## Shared widgets (`lib/ui/widgets/`)

`HeroPanel`, `LiveSparkline` (speed chart; a single point is drawn flat), `ServerPickerSheet`, `ReconnectBanner`
(settings changed on a live VPN → reconnect), `Pressable` (whole-row tap target), `settings_shared.dart`
(`SetRowToggle`, `SetSquareSwitch`, `SetSegSquare`), `BreadcrumbBar`, `FeatureGate`, `CoreSupportGate`, `core_sheet`,
`confirmUntrustedCertificate` (the untrusted subscription certificate dialog with its SHA-256, used by Add and
Configs), `import_review.dart` (`ImportReviewDetails`, `confirmImportReview`: what an import changes,
[profiles](profiles.md)).

## Read-only profiles

On a read-only profile settings rows are locked and a tap explains why; `SettingsNotifier.save` ignores changes
anyway ([profiles](profiles.md)).

## Theme

`lib/ui/theme/`: `AppTheme.build(brightness, accent)` with the `TeapodTokens` extension (`bg`, `bgElev`, `bgSunken`,
`accent`, `accentSoft`, `text`, `textDim`, `textMuted`, `line`, `lineSoft`, `danger`); `AppTheme.mono` / `sans`
text helpers (minimum 11 px). Text follows the system font size: the app's `textScaler` is the system one (Android's font size and accessibility
scaling) times the app's font setting (`fontScale`: 1.0 or 1.2), capped at 2.0 (`appTextScaler`,
`theme/app_text_scaler.dart`). Layouts at large sizes are checked on a device: the test font is wider than the real ones.
Where width is fixed, text gives way instead of breaking the layout: a short caption (tab label, `0x01` address, hero
title) is a `OneLine` (`widgets/one_line.dart`) and shrinks rather than wrap mid-word; the tab bar caps its scale at
1.3 so its four labels keep one size; a label + selector row is a `Wrap` and the selector's labels (`SetSegSquare`) are capped at 1.5, so it fits on its own
line without scaling its 48 dp targets; a line of short metadata is a `Wrap`; a bottom-sheet menu is a `ListView`.

## Conventions

- Every visible string through `context.l10n` ([localization](localization.md)).
- Widgets read providers and call notifier methods; no business logic in widgets (picking a config:
  `VpnNotifier.selectConfig`, [vpn_provider](vpn_provider.md)).
- A large screen is a folder `screens/<name>/`: the screen and its state in `<name>_screen.dart`, its sections as
  private widgets in `part` files next to it (`screens/configs/`: `header`, `groups`, `config_row`, `pinned`,
  `tiles`; `screens/routing/`: `controls`, `picker`, `geo`; `screens/settings/`:
  `header`, `rows`, `core_order`, `appearance`, `update`; `screens/home/`: `header`, `power`, `ticks`, `metrics`).
- Every tap target is at least 48 dp on each side and an icon-only one has a label: `TapTarget`
  (`widgets/tap_target.dart`) puts a transparent 48 dp area around a smaller visual, dims it while pressed and
  carries the TalkBack label; a row that toggles as a whole is one target announced as a switch (`SetToggleRow`; its
  `SetSquareSwitch` is then only the visual) or, with `checkbox: true`, as a checkbox. A full-width row is a
  `Pressable` at least 48 dp high; a segment of a full-width selector is a `Pressable` marked `selected`. No bare
  `GestureDetector` for a tap target outside these widgets. A dense `TextField` in a dialog or a sheet gets
  `InputDecoration.constraints` of 48 dp.
- Every dialog is a plain `AlertDialog` without its own colours: `dialogTheme` and `textButtonTheme` in `AppTheme`
  give the frame, title, body text and buttons; `widgets/dialog_parts.dart` adds what the theme can't —
  `DialogCancel` (muted), `DialogAction` (accent, or `danger` for deleting and lowering security) and
  `dialogField` / `dialogFieldStyle` for a text field. `test/ui/accessibility_test.dart` checks the main screens, a subscription
  group, the profile dialog and the server sheet with `androidTapTargetGuideline` and `labeledTapTargetGuideline`.
- UI tests: `test/ui/` — smoke of every screen, interactions ([tests](tests.md)).

## Related

[VpnProvider](vpn_provider.md) · [ConfigProvider](config_provider.md) · [Localization](localization.md)
