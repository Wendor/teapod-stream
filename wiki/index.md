# TeapodStream wiki

How TeapodStream works inside and why. Read the pages for the area you change before changing it, and fix any page
your change makes wrong in the same pull request. The wiki describes the **current state only** — history lives in
git and pull requests, plans and open problems in GitHub issues.

Rules for contributing: [CONTRIBUTING.md](../CONTRIBUTING.md), for AI agents: [AGENTS.md](../AGENTS.md).

## Overview

- [Architecture](architecture.md) — layers, traffic, cores, Flutter ↔ native, connecting, persistence, source layout
- [Security](security.md) — threat model, protections, accepted risks, data storage

## Flutter

| Page | About |
|---|---|
| [VpnProvider](components/vpn_provider.md) | connection lifecycle, core choice, native events, config switch on a dead tunnel |
| [ConfigProvider](components/config_provider.md) | configs, subscriptions, auto mode, pins, mutation queue |
| [SettingsProvider](components/settings_provider.md) | `AppSettings`, tuning (fragment, noise, Mux), heartbeat |
| [Profiles](components/profiles.md) | settings profiles, bundles, deep links |
| [GeoProvider](components/geo_provider.md) | geodata download and sources |
| [AppsProvider](components/apps_provider.md) | installed apps and icons for split tunneling |
| [IpInfoProvider](components/ip_info_provider.md) | exit IP and country |
| [UpdateProvider](components/update_provider.md) | app updates from GitHub releases |
| [Services](components/services.md) | subscriptions, tunnel SOCKS, storage, logs, updates |
| [Models](components/models.md) | `VpnConfig`, subscriptions, routing, compatibility rule |
| [Screens](components/ui_screens.md) | navigation, screens, cores in the UI, shared widgets, theme |
| [Localization](components/localization.md) | ARB, `context.l10n` / `L10n.current`, native strings |

## Protocols and cores

| Page | About |
|---|---|
| [XrayEngine](components/xray_engine.md) | the MethodChannel client |
| [XrayConfigBuilder](components/xray_config_builder.md) | xray JSON (Go), managed configs, xray-rust translation |
| [SingBoxConfigBuilder](components/singbox_config_builder.md) | sing-box JSON and its limits |
| [VlessParser](components/vless_parser.md) | link parsing for all protocols |

## Native

| Page | About |
|---|---|
| [Android native](components/android_native.md) | `VpnService`, kill switch, reconnect, heartbeat, split tunneling, notification, tile |
| [teapod-core](components/teapod_core.md) | the AAR: Go API, xray-core patches, sing-box integration |
| [teapod-tun2socks](components/teapod_tun2socks.md) | TUN → SOCKS5 gateway, owner check, QUIC/ICMP handling |

## Process

| Page | About |
|---|---|
| [Tests](components/tests.md) | unit tests, techniques, on-device integration tests |
| [CI/CD](components/ci.md) | checks, PR rules, branch protection, releases, signing |
