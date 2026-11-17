# English

## 1.8.1

- What's new: the update notes come in the app's language and cover every version since yours; the full history is in Settings → about → changelog (#184)
- Updated cores: xray-core 26.11.9, xray-rust 0.10.0, AmneziaWG; the "chrome" TLS fingerprint is now Chrome 155
- Saved configs and subscriptions move to a new encryption on the first launch, nothing to do on your side
- Updated Flutter, the Android build tools and libraries

## 1.8.0

- The interface is in English and Russian: pick the language in Settings → Appearance (system / English / Русский); notifications and the tile are translated too
- sing-box: the system DNS no longer loses IPv4 addresses in its answers
- Split tunneling: an excluded app can no longer get into the tunnel through a just-closed connection of an allowed one (#172)
- UDP (games, calls, streaming) no longer drops after a minute when data flows in one direction only (#173)
- A failed xray start no longer keeps its port busy and no longer breaks the next connection (#167)
- The latency test no longer counts a server as alive when its response is cut off midway (#168)
- Fixed rare AmneziaWG and tun2socks crashes on start and stop (#170, #175)
- For developers: rules for contributors and AI agents (CONTRIBUTING.md, AGENTS.md); the cores now live in this repository (core/)

## 1.7.8

- A connection error shows on the home screen: FAILED and the reason, tap to retry
- While the VPN waits for the network after it changes, the app, the tile and the notification show "Connecting…", not "Connected"
- A failed manual connection with the kill switch on no longer blocks the internet
- Updating a subscription no longer resets automatic server selection within the subscription; connect on startup works in this mode too
- When a subscription returns nothing, the reason is shown: the device limit (HWID) or the provider's message. The provider's message also shows in the expanded subscription
- "Update all" reports the result and the errors of each subscription
- Deleting a subscription removes its configs from the pinned ones
- The [local] group is expanded by default, so a manually added config doesn't "disappear"
- Selecting the already connected config again doesn't reconnect the VPN
- Links with %25 in the path no longer break
- In a read-only profile the routing and split tunneling switches show a warning instead of doing nothing
- A profile export no longer contains the SOCKS login/password and your own heartbeat address
- App updates are downloaded through the VPN
- Pinging all configs and searching for a working server no longer start dozens of checks at once
- The tile and the notification keep updating after the app is closed
- The source code link in "About" opens again

## 1.7.7

- Tile: when off it shows "TeapodStream" again, with the config name in the subtitle. When on, the config name is the title
- Switching the core is animated on the home screen, in the core card and in settings
- Subscription auto-update on startup goes through the VPN when it is already on from the tile
- If a reconnect from the tile fails, the tile no longer shows "Connected"
- Without the VPN permission the tile shows "Disconnected", not "Kill switch"
- With the notification turned off, disconnecting no longer shows the full notification

## 1.7.6

- The notification no longer gets stuck on "Connecting…" after turning on from the tile: it shows the status right away, and the speed once connected (#76)
- With the "Notification" option off, the tile and reconnects no longer show a full notification that never updated and couldn't be swiped away; only the minimal one stays (#76)
- The notification no longer jumps to the top of the shade on every update and appears right away; on Android 12+ it used to show only after 10 s
- After a failed connection the notification shows "Disconnected", or "Kill switch: traffic blocked" when the kill switch fired. It used to stay at "Connecting…"
- The tile shows the name of the config it will connect instead of "TeapodStream"
- With the VPN connected, subscriptions and geo databases download through the VPN, which helps when GitHub is blocked. If that fails, the download is retried directly (#150)
- A geo database download on a stalled network is aborted after 30 s instead of hanging forever
- "Connect" right after the app starts no longer opens the "Configs" tab while configs are still loading (#151)
- Now 658 Dart and 37 JVM tests (were 653 and 37)

## 1.7.5

- Core priority instead of one core for everything: settings hold the order xray-core → sing-box → xray-rust, each profile starts on the first core that supports it, unneeded cores can be turned off, and a profile can be pinned to its own core
- The cores are now called xray-core / xray-rust / sing-box; the home screen shows the core of the current connection under the IP
- A subscription update keeps each profile's pinned core; profiles with the same address:port used to get the core of the last one
- If the network changes right after connecting (after airplane mode the VPN came up on LTE and Wi-Fi turned on a second later), the VPN reconnects; the connection used to drop for about 30 s
- sing-box: after switching from LTE to Wi-Fi, Hysteria2 connections no longer hang for 20–30 s
- sing-box: settings show the core version (it was "unknown"); the log no longer has a "failed to search process" line for every connection
- xray-core: turning UDP off no longer breaks DNS; sites used to stop opening
- "Reply to ping" works again on xray-core and sing-box: the VPN itself replies, so the time doesn't reflect the latency to the server
- Safari / iOS / Edge / QQ TLS fingerprints with ECH connect; they used to fail with "malformed outer client hello"
- XHTTP with ECH and ALPN h3 over TCP connects; the server used to pick HTTP/3 and the connection dropped
- Hysteria2 with noise no longer hangs forever after a failed handshake; it reconnects
- Tip: if Android unloads the app from memory, the system doesn't always restart the VPN by itself; turn on "Always-on VPN" in the Android settings
- Now 653 Dart and 37 JVM tests (were 558 and 35), plus on-device integration tests

## 1.7.4

- A third core, sing-box (Settings → Core), experimental
- New protocols (sing-box only): WireGuard, AmneziaWG (including 3.x: header protection, I1–I5, RandomTrailers), SSH and NaiveProxy
- Import: wireguard:// and wg:// links, AmneziaVPN keys (vpn://), .conf configs (paste the whole text), ssh://, naive+https:// and naive+quic://; subscriptions understand the new links too
- Profiles sing-box doesn't support (XHTTP, full Xray JSON, VLESS Encryption and others) show as inactive with an explanation; on the Xray cores, so do profiles of the new protocols
- Reality with ML-DSA (pqv) connects in sing-box, but without the post-quantum server check; a warning says so on connect
- Xray settings sing-box doesn't have (noise, mux, fragmentation other than TLS ClientHello) are not applied, with a warning for each
- WG / AWG / SSH / NAIVE labels in the config list
- Settings show the version of the selected core, and there is a new "Licenses" section (sing-box is GPLv3, amneziawg-go is MIT)
- The APK grew by about 13 MB (arm64: 41.9 → 54.3 MB): that's sing-box with Naive
- Now 558 Dart and 35 JVM tests (were 493 and 26)

## 1.7.3

- Split tunneling on Android 10: apps in the tunnel resolve sites by name again; the VPN used to be connected while pages didn't open (#155)
- "Direct" DNS mode (Go core): the selected DNS server is used, queries to it bypass the VPN, DoH/DoT stay encrypted. All queries used to go to 1.1.1.1 in plain text
- Fixed the AdGuard (DoH) address: dns.adguard-dns.com; queries didn't go through with the old one
- The selected geo database source (Loyalsoldier / runetfreedom / v2fly) is now saved; it used to reset after an app restart and on a profile switch
- ICMP (ping) through the tunnel is off by default, as intended; it was on for new installs
- Switching the core Go ↔ Rust is picked up by the tile and autostart right away, and a profile the new core doesn't support is disconnected; the previous core used to be applied
- An update download on a stalled network is aborted after 30 s and resumed later; the "Cancel" button no longer hangs
- The app list is sorted case-insensitively: eBay, iHerb and the like no longer end up at the bottom
- Routing: a switch toggles on a tap anywhere on its row, as in settings
- Now 493 Dart and 26 JVM tests (were 203 and 11)

## 1.7.2

- Other apps can no longer see the VPN state or turn it off. Tasker/Anubis integration is now turned on manually (Settings → Automation)
- Apps excluded from the VPN can no longer get into the tunnel over UDP or learn the server address
- Import via a teapod://import/...?url= link: https only and only after confirmation; deep links with the app open are fixed too
- Importing a profile no longer changes the SOCKS port and password, proxy-only, HWID or the heartbeat check address
- An empty SOCKS login/password in VPN mode is replaced with a random one, so the proxy isn't left open to other apps
- Switching the server with the VPN on doesn't disconnect, and no traffic bypasses the tunnel during the switch
- urltest: automatic switching to a live server no longer leaves the VPN off
- Go core: profiles with allowInsecure without pinSHA256 and with the HTTP/2 or QUIC transport show as unsupported; the new Xray-core doesn't start them
- Go core: ECH is actually applied now; TCP with HTTP camouflage (headerType=http) is supported
- Subscriptions with a self-signed certificate update automatically, trusting only the certificate accepted by hand
- The MTU setting is now applied
- Tile: the VPN can't be turned off from the lock screen without unlocking
- Fixed a cut-off response when an app closes its side of the connection for writing (half-close)
- Less load: no extra checks on every connection, the xray connection log is written only at debug level, the speed graph receives only new points

## 1.7.1

- Xray-core updated to v26.10.31
- Hysteria2: port hopping moved to the new Xray-core format (the old one would have stopped working)
- The selected server is no longer reset by a subscription update (inspired by #154)
- Pinned connections don't get mixed up when a subscription has several servers with the same name
- Subscription auto-update: an error in one subscription doesn't stop the others from updating; a broken subscription is retried at most once an hour
- Auto-update no longer overwrites your subscription name with the provider's title
- Changing a subscription URL: the subscription isn't lost when the download fails, and the list updates right away
- Fixed possible corruption of the config list when a ping and a subscription update run at the same time
- A failed ping clears the old value, so automatic selection within a subscription no longer picks an unreachable server
- Mux is not applied to XHTTP (it has its own multiplexing)
- Connections that DPI silently drops are closed after 30 s instead of hanging for minutes
- The notification updates at most once every 5 s, waking watches, bands and other apps that read notifications less often
- Fixed connection leaks: XHTTP/gRPC after a reconnect, latency tests, subscription, update and geo database requests

## 1.7.0

- Core choice in settings: Xray (Go) or Xray (Rust) based on xray-rust, experimental, inspired by #152
- Profiles and settings the selected core doesn't support show as inactive with an explanation
- The certificate pin (pinSHA256) is actually applied now
- Hysteria2: port hopping support (a port range in the link and mport)
- Trojan: security=reality/none and the Reality, ALPN and ECH parameters are taken into account
- Backup import and "Edit URI" no longer lose profile fields (pin, insecure, ALPN and others)
- The "Sites" and "RU services" rules apply even when the other routing rules are off
- A custom DNS with an IPv6 address is no longer truncated
- Dropped the armeabi-v7a build (it seems it never really worked)

## 1.6

- Reworked interface; the tunnel is no longer recreated on reconnect, less battery drain
- Automatic switch to a live server when the tunnel breaks; candidates are checked with a real connection through the protocol
- Heartbeat: pick the check type (SOCKS, measured inside the core, passive) and the target (Cloudflare, Google, Apple or your own URL)
- Settings → Network: TLS ClientHello fragmentation, noise UDP packets for Hysteria2 and QUIC, Mux
- Split tunneling "All except selected": excluded apps no longer get into the tunnel; a "Share through VPN" option
- Fixed: Hysteria2 without SNI, the insecure parameter of VLESS/VMess/Trojan, the port of a custom DNS-over-TLS, DNS with the ad blocker on

## 1.5

- Managed subscriptions: the provider's ready xray configs (balancers, observatory, routing) merged safely, with ad blocking and no traffic bypassing the VPN
- TLS fingerprint (uTLS) setting; a custom User-Agent for subscriptions
- The kill switch also protects during an automatic reconnect; a failed reconnect is retried up to 3 times
- Fixed the main cause of a "stuck VPN": after ~1000 connections the tunnel stopped accepting new ones
- Hung connections are closed, long downloads no longer break at the 5th minute; with xtls-rprx-vision QUIC is blocked so the browser goes over TCP right away
- IPv6 in the tunnel (option), a tunnel diagnostics snapshot on the logs screen, logs survive a reconnect

## 1.4

- New design with a big round button, a font size setting
- Profiles and deep links for them (#97); export of all configs
- Always-on VPN and start on device boot; CONNECT / DISCONNECT for automation and other apps
- Subscriptions: automatic update, automatic server selection, sorting by ping, drag and drop, a view without groups
- Routing: custom GeoIP/GeoSite (presets or a URL), service presets, a "Sites" section, a "Russian services" checkbox, a wider ad blocker
- Network: MTU, sniffing, DNS strategy, disabling QUIC, blocking ICMP, resetting connections on a network change; DNS leaks closed
- Heartbeat over an HTTP request and tunnel watchdogs: a stuck VPN reconnects by itself
- The extra URI parameter (XHTTP), serviceName for Trojan + gRPC, allowInsecure and pinSHA256 for Hysteria2; tethering fixed

## 1.3

- xray-core inside the teapod-core AAR, armeabi-v7a support
- App auto-update
- Incoming and outgoing traffic graph
- Configs in secure storage
- Routing by geoip and geosite, geo database updates, ready network sets (Cloudflare, Google, Telegram and more)
- A quick settings tile; a long tap on it opens the app
- Instant reaction to a network change, heartbeat; built-in DoH/DoT addresses, a better ad blocker
- QUIC over IPv6 works (YouTube) while unknown UDP stays out of the tunnel; fixed a leak through UDP relay

## 1.0–1.2

- First versions: VLESS, VMess, Trojan and Shadowsocks through xray-core and tun2socks
- Transports TCP, WebSocket, gRPC, H2, QUIC, XHTTP, HTTPUpgrade, SplitHTTP; TLS and Reality
- Subscriptions, adding by QR code, traffic statistics
- Split tunneling, selected apps first in the list
- Shadowsocks with the Outline prefix, self-signed certificates, a SOCKS-only mode
