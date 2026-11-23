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
└── _AppShell — tabs via tabIndexProvider, custom bottom bar
    ├── 0 HomeScreen
    ├── 1 ConfigsScreen      → AddConfigScreen → QrScanScreen
    ├── 2 RoutingScreen      → SplitTunnelScreen
    └── 3 SettingsScreen     → LogsScreen, SubscriptionSettingsScreen, NetworkSettingsScreen,
                               DnsSettingsScreen, ProfilesScreen
```

`_AppShell` also: listens to `XrayEngine.events` for deep links, syncs native state on resume and pauses stats on
pause, auto-connects on start (`autoConnect`), pings stale configs, checks geodata.

## Screens

| Screen | What's on it |
|---|---|
| `HomeScreen` | hero panel: power button (`_PowerCore`), state with the error reason for FAILED/BLOCKED, server, exit IP, core line (`[core] xray-core ›`, tap → core sheet), speeds and the live chart; server picker sheet; warning for managed configs |
| `ConfigsScreen` | groups: pinned → local → subscriptions (collapsible, drag to reorder in sort mode); flat mode and sort-by-ping (`cfg_hide_groups`, `cfg_sort_by_ping`); auto-select per subscription; context menus (pin, core, copy/QR, edit, rename, refresh, delete); export of all connections as a compact `teapod://import/connections` link |
| `AddConfigScreen` | one input for links, subscription URLs (`http(s)://`), WireGuard `.conf` text, `vpn://` keys and `teapod://import/connections`; QR scan |
| `RoutingScreen` | direction (global / bypass / only selected), kill switch, split tunneling entry, sniffing, geo data (source, download), domain zones, sites, geosite/geoip codes, Russian services, ad block |
| `SplitTunnelScreen` | app list with lazy icons, mode, tethering through VPN (`allExcept` only), cleans uninstalled packages |
| `SettingsScreen` | `0x10` diagnostics (logs) · `0x20` appearance (theme, language, font size, accent) · `0x30` connection (auto-connect, boot, notification, automation, subscriptions) · `0x40` network (network screen, DNS screen, core order) · `0x50` system (profiles, update channel) · `0x60` about (version, changelog → `WhatsNewScreen`, licenses, source). An available update is shown first |
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
(`SetRowToggle`, `SetSquareSwitch`, `SetSegSquare`), `BreadcrumbBar`, `FeatureGate`, `CoreSupportGate`, `core_sheet`, `confirmUntrustedCertificate` (the untrusted
subscription certificate dialog with its SHA-256, used by Add and Configs).

## Read-only profiles

On a read-only profile settings rows are locked and a tap explains why; `SettingsNotifier.save` ignores changes
anyway ([profiles](profiles.md)).

## Theme

`lib/ui/theme/`: `AppTheme.build(brightness, accent)` with the `TeapodTokens` extension (`bg`, `bgElev`, `bgSunken`,
`accent`, `accentSoft`, `text`, `textDim`, `textMuted`, `line`, `lineSoft`, `danger`); `AppTheme.mono` / `sans`
text helpers (minimum 11 px). Font scale (`fontScale`) applies through the app's `textScaler`.

## Conventions

- Every visible string through `context.l10n` ([localization](localization.md)).
- Widgets read providers and call notifier methods; no business logic in widgets.
- UI tests: `test/ui/` — smoke of every screen, interactions ([tests](tests.md)).

## Related

[VpnProvider](vpn_provider.md) · [ConfigProvider](config_provider.md) · [Localization](localization.md)
