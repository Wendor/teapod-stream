# English

## 1.8.0

- English and Russian interface: pick the language in Settings → Appearance (system / English / Русский); notifications and the tile are translated too
- sing-box: the system DNS no longer loses IPv4 addresses in answers
- Split tunneling: an excluded app can no longer get into the tunnel through a just-closed connection of an allowed one (#172)
- UDP (games, calls, streaming) no longer drops after a minute when data flows only one way (#173)
- A failed xray start no longer keeps its port busy and no longer blocks the next connection (#167)
- Latency test no longer counts a server as alive when the response breaks off midway (#168)
- Fixed rare AmneziaWG and tun2socks crashes on start and stop (#170, #175)
- For developers: rules for contributors and AI agents (CONTRIBUTING.md, AGENTS.md); the cores now live in this repository (core/)

## 1.7.8

- Connection errors are shown on the home screen: FAILED and the reason, tap to retry
- While VPN waits for the network after it changes, the app, tile and notification show "Connecting…", not "Connected"
- A failed manual connection with the kill switch on no longer blocks the internet
- Refreshing a subscription no longer resets the subscription's automatic server choice; auto-connect on start works in this mode too
- When a subscription returns nothing, the reason is shown: device limit (HWID) or the provider's message. The provider's message is also shown in the expanded subscription
- "Update all" reports the result and errors for each subscription
- Deleting a subscription removes its configs from the pinned ones
- The [local] group is expanded by default, so a manually added config doesn't "disappear"
- Selecting the already connected config again no longer reconnects VPN
- Links with %25 in the path no longer break
- In a read-only profile, the routing and split-tunnel switches show a warning instead of doing nothing
- Profile export no longer includes the SOCKS login/password and the custom heartbeat address
- App updates are downloaded through VPN
- Pinging all configs and searching for a working server no longer start dozens of checks at once
- The tile and notification keep updating after the app is closed
- The source code link in "About" opens again

## 1.7.7

- Tile: when off, it shows "TeapodStream" again with the config name in the subtitle; when on, the config name is the title
- Core switching is animated on the home screen, in the core card and in Settings
- Subscription auto-update on start goes through VPN if it was already turned on from the tile
- If a reconnect from the tile fails, it no longer shows "Connected"
- Without the VPN permission the tile shows "Disconnected", not "Kill switch"
- With the notification turned off, disconnecting no longer shows the full notification

## 1.7.6

- The notification no longer gets stuck on "Connecting…" after turning on from the tile: the status shows right away, and the speed after connecting (#76)
- With the "Notification" option off, the tile and reconnects no longer show a full notification that never updated or could be swiped away; only the minimal one remains (#76)
- The notification no longer jumps to the top of the shade on every update and appears right away; on Android 12+ it used to show only after 10 s
- After a failed connection the notification shows "Disconnected", and "Kill switch: traffic blocked" when the kill switch fired. It used to stay on "Connecting…"
- The tile shows the name of the config it will connect instead of "TeapodStream"
- With VPN connected, subscriptions and geo databases are downloaded through VPN, which helps when GitHub is blocked. If that fails, the download is retried directly (#150)
- Geo database downloads on a stuck network abort after 30 s instead of hanging forever
- "Connect" right after the app starts no longer opens the Configs tab while configs are still loading (#151)
- Tests: 658 Dart and 37 JVM (were 653 and 37)

## 1.7.5

- Core priority instead of one core for everything: Settings has the order xray-core → sing-box → xray-rust, each profile runs on the first core that supports it, unneeded cores can be turned off, and a profile can be pinned to its own core
- The cores are now called xray-core / xray-rust / sing-box; the home screen shows the current connection's core under the IP
- Refreshing a subscription keeps each profile's pinned core; profiles with the same address:port used to get the core of the last of them
- If the network changes right after connecting (VPN came up on LTE after airplane mode, and Wi-Fi turned on a second later), VPN reconnects; the connection used to drop for about 30 s
- sing-box: Hysteria2 connections no longer hang for 20–30 s after switching from LTE to Wi-Fi
- sing-box: Settings shows the core version (was "unknown"); the log no longer has a "failed to search process" line for every connection
- xray-core: turning UDP off no longer breaks DNS; sites used to stop opening
- "Reply to ping" works again on xray-core and sing-box: VPN itself replies, so the time doesn't reflect the latency to the server
- Safari / iOS / Edge / QQ TLS fingerprints with ECH connect; they used to fail with "malformed outer client hello"
- XHTTP with ECH and ALPN h3 over TCP connects; the server used to pick HTTP/3 and the connection broke
- Hysteria2 with noise no longer hangs forever after a failed handshake; it reconnects
- Tip: if Android unloads the app from memory, the system doesn't always restart VPN by itself; turn on "Always-on VPN" in Android settings
- Tests: 653 Dart and 37 JVM (were 558 and 35), plus on-device integration tests

## 1.7.4

- A third core, sing-box (Settings → Core), experimental
- New protocols (sing-box only): WireGuard, AmneziaWG (including 3.x: header protection, I1–I5, RandomTrailers), SSH and NaiveProxy
- Import: wireguard:// and wg:// links, AmneziaVPN keys (vpn://), .conf configs (paste the whole text), ssh://, naive+https:// and naive+quic://; subscriptions understand the new links too
- Profiles sing-box doesn't support (XHTTP, full Xray JSON, VLESS Encryption and others) are shown inactive with an explanation; on the Xray cores, so are profiles of the new protocols
- Reality with ML-DSA (pqv) connects in sing-box, but without post-quantum server verification; a warning says so on connect
- Xray settings sing-box doesn't have (noise, mux, fragmentation other than TLS ClientHello) are not applied, with a warning for each
- WG / AWG / SSH / NAIVE labels in the config list
- Settings shows the selected core's version and a new "Licenses" section (sing-box is GPLv3, amneziawg-go is MIT)
- The APK grew by about 13 MB (arm64: 41.9 → 54.3 MB): that's sing-box with Naive
- Tests: 558 Dart and 35 JVM (were 493 and 26)

## 1.7.3

- Split tunneling on Android 10: apps in the tunnel resolve sites by name again; VPN used to be connected while pages didn't open (#155)
- "Direct" DNS mode (Go core): the selected DNS server is used, queries to it bypass VPN, DoH/DoT stay encrypted. All queries used to go to 1.1.1.1 in plain text
- Fixed the AdGuard (DoH) address: dns.adguard-dns.com; queries didn't go through with the old one
- The selected geo database source (Loyalsoldier / runetfreedom / v2fly) is saved; it used to reset after an app restart and on profile change
- ICMP (ping) through the tunnel is off by default, as intended; it was on for new installs
- Switching the core Go ↔ Rust takes effect for the tile and autostart right away, and a profile the new core doesn't support is turned off; the previous core used to be applied
- An update download on a stuck network aborts after 30 s and resumes later; the "Cancel" button no longer hangs
- The app list is sorted case-insensitively: eBay, iHerb and the like no longer end up at the bottom
- Routing: the switch reacts to a tap on the whole row, as in Settings
- Tests: 493 Dart and 26 JVM (were 203 and 11)

## 1.7.2

- Other apps can no longer see the VPN state or turn it off. Tasker/Anubis integration is now turned on manually (Settings → Automation)
- Apps excluded from VPN can no longer get into the tunnel over UDP and learn the server address
- Import via teapod://import/...?url= links: https only and only after confirmation; deep links with the app open are fixed too
- Importing a profile no longer changes the SOCKS port and password, proxy-only, HWID and the heartbeat check address
- An empty SOCKS login/password in VPN mode is replaced with a random one so the proxy isn't left open to other apps
- Switching servers with VPN on doesn't disconnect, and traffic doesn't bypass the tunnel during the switch
- urltest: automatic switching to a live server no longer leaves VPN off
- Go core: profiles with allowInsecure without pinSHA256 and with HTTP/2 or QUIC transport are shown as unsupported, since the new Xray-core doesn't start them
- Go core: ECH is actually applied; TCP with HTTP obfuscation (headerType=http) is supported
- Subscriptions with a self-signed certificate update automatically, trusting only the manually accepted certificate
- The MTU setting is applied
- Tile: VPN can't be turned off from the lock screen without unlocking
- Fixed a broken response when an app closes the connection for writing (half-close)
- Less load: no extra checks on every connection, the xray connection log is written only at debug level, the speed chart gets only new points

## 1.7.1

- Xray-core updated to v26.10.31
- Hysteria2: port hopping moved to the new Xray-core format (the old one would have stopped working)
- The selected server is no longer reset when a subscription is refreshed (inspired by #154)
- Pinned connections no longer get mixed up when a subscription has several servers with the same name
- Subscription auto-update: an error in one subscription doesn't stop the others from updating, and a broken subscription is retried at most once an hour
- Auto-update no longer overwrites your subscription name with the provider's title
- Changing a subscription URL: on a download error the subscription isn't lost, and the list updates right away
- Fixed possible corruption of the config list when pinging and refreshing a subscription at the same time
- A failed ping clears the old value, so automatic selection in a subscription no longer picks an unreachable server
- Mux is not applied to XHTTP (it has its own multiplexing)
- Connections silently dropped by DPI are closed after 30 s instead of hanging for minutes
- The notification updates at most every 5 s, waking up watches, fitness bands and other apps that read notifications less often
- Fixed connection leaks: XHTTP/gRPC after reconnect, latency test, subscription, update and geo database requests

## 1.7.0

- Core selection in Settings: Xray (Go) or Xray (Rust) based on xray-rust, experimental, inspired by #152
- Profiles and settings the selected core doesn't support are shown inactive with an explanation
- Certificate pinning (pinSHA256) is actually applied now
- Hysteria2: port hopping support (port range in the link and mport)
- Trojan: security=reality/none and the Reality, ALPN and ECH parameters are taken into account
- Backup import and "Edit URI" no longer lose profile fields (pin, insecure, ALPN and others)
- The "Sites" and "RU services" rules apply even when the other routing rules are off
- A custom DNS with an IPv6 address is no longer truncated
- Dropped the armeabi-v7a build (it seems it didn't work at all)
