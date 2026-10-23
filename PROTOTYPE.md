# TeapodStream: Go and experimental Rust builds

The default build uses Go/teapod-core. The separate Rust build uses
**xray-rust 0.8.1** and its direct TUN file-descriptor backend.
Rust application ID: `com.teapodstream.rustprobe`. It installs alongside the original TeapodStream.
No live VPN profile or credentials are bundled.

## Rust support (1.6.6-rust.8)

Profiles come from share links. Anything outside this list is refused with an
explanation before VPN startup; nothing is silently dropped.

- VLESS with `encryption=none` and a UUID over TCP/RAW, WebSocket, HTTPUpgrade,
  gRPC and XHTTP/SplitHTTP. TLS works on all of these carriers; REALITY on
  TCP/RAW, gRPC and XHTTP. XHTTP `auto` / `packet-up` / `stream-up` /
  `stream-one`, host/path/extra, REALITY SNI, fingerprint, public key, short ID
  and spiderX are kept.
- `xtls-rprx-vision` and `xtls-rprx-vision-udp443` over TCP/RAW with TLS or
  REALITY. Vision over plain TLS works since xray-rust 0.8.0. On other carriers
  the core refuses Vision before dialing, as Xray-core does.
- Trojan over the same carriers, with TLS or REALITY. The core refuses
  plaintext Trojan to a public server; the app refuses it for any server.
  Trojan links do not read `allowInsecure`, so the certificate is verified
  unless a pin is given.
- VMess AEAD over the same carriers, with or without TLS. It needs a UUID
  `id`. A link's `aid` is ignored, as in Go: no `alterId` is written and the
  client always speaks AEAD. The cipher is the link's `scy` when it is
  `auto`, `aes-128-gcm` or `chacha20-poly1305`; any other value (`none`,
  `zero`, CFB) is sent as `auto`, which Go always sends. Neither build parses
  the VMess JSON `fp` and `alpn` fields.
- Shadowsocks 2022, TCP and UDP. Methods are `2022-blake3-aes-128-gcm` and
  `-aes-256-gcm` (up to eight colon-separated identity keys) and
  `-chacha20-poly1305` (one key). Each key must be padded standard base64, at
  least as long as the method's key. UDP goes to the server over its own
  protected socket.
- Hysteria 2 (`hy2://`, `hysteria2://`), with Salamander (`obfs=salamander`,
  4–4096-byte password) and port hopping (a port range/list or `mport`, up to
  65,535 expanded ports, the core's default 30 s interval). The Rust builder
  keeps the Go builder's FinalMask `udp` Salamander and
  `quicParams.udpHop.ports` unchanged. Brutal, bandwidth, other QUIC overrides
  and other `obfs` types are refused.
  - Each QUIC connection carries up to 256 TCP streams and 128 UDP sessions
    (the core default is 64/32); a further flow fails at once until one closes.
  - UDP travels in 1200-byte QUIC datagrams and is fragmented above that.
  - QUIC TLS is not shaped, so fingerprint and ALPN overrides are dropped.
  - After a network change the carrier rebinds instead of reconnecting; see
    below.
- Also refused:
  - Shadowsocks: AEAD-2017 methods, SIP003 plugins, the Outline `prefix`.
  - VMess: a link `tls` other than `tls` or `none`, including `reality` and
    case variants such as `TLS`. The parser takes only the exact `tls`, so
    such a profile would go to the TLS port without TLS.
  - Carriers: kcp, QUIC, h2, TCP `headerType=http`.
  - Other: ECH, a link's own `fm` (FinalMask), raw Xray JSON.
- TLS certificate verification stays on.
  - `pinSHA256` is the SHA-256 of the full leaf certificate, as hex,
    colon-separated hex or base64. Both builders write it as
    `pinnedPeerCertSha256`.
  - A pin wins over `allowInsecure`: such a profile is built with
    `allowInsecure: false`, so only the pinned certificate is accepted.
  - `allowInsecure` without a pin is refused.
- Fragmentation splits the TLS ClientHello on TCP TLS/REALITY carriers
  (FinalMask `tcp` fragment).
  - Settings: packets must be `tlshello`; length up to 16384 bytes; pause up
    to 1000 ms.
  - The core drops a connection whose cut exceeds 4096 pieces or 10 s of
    pauses. The builder caps `maxSplit` only when a 16 KiB hello could reach
    those limits, so ordinary settings cut as in Go.
  - Not applied, as in Go: QUIC (Hysteria 2, XHTTP h3) and carriers without TLS.
  - Refused with an XHTTP `downloadSettings`.
- Noise is sent as junk UDP datagrams before the first QUIC packet (FinalMask
  `udp` noise).
  - Applies to Hysteria 2 and to XHTTP with TLS `alpn=h3`. On Hysteria 2 it
    goes after Salamander, so it stays unobfuscated, like Go's freedom noise.
  - Limits: up to 4096 bytes and a 1000 ms pause.
  - TCP carriers are unaffected, as in Go.
  - A Shadowsocks profile with noise is refused: Go adds noise to its UDP, but
    the core cannot. Noise is a global network setting, so connecting to such
    a profile means turning it off there; the message says so.
- UDP switch and QUIC blocking. A routing rule right after the DNS rules sends
  matching UDP to a `blackhole`:
  - QUIC blocking catches UDP/443 from TUN. It turns on with the toggle, and
    automatically for `xtls-rprx-vision-udp443`, as Go blocks QUIC for Vision.
  - Plain `xtls-rprx-vision` gets no automatic rule: the core answers its
    UDP/443 with ICMP "port unreachable" itself, so apps fall back to TCP at
    once, as with Go's tun2socks. With the toggle on, the rule drops that
    UDP/443 silently instead.
  - Turning UDP off catches all UDP from TUN and from the local SOCKS.
    xray-rust parses SOCKS `udp: false` but does not enforce it.
  - Port 53 still reaches DNS. The core's DNS module and the proxy's own
    carrier (Hysteria QUIC, Shadowsocks UDP) are not affected.
  - Go's tun2socks answers blocked UDP with ICMP "port unreachable". The
    blackhole drops silently, so an app falls back from QUIC to TCP only after
    its own timeout.
- DNS through the VPN or direct. App queries always go to the core's DNS
  outbound, which answers A/AAAA through the DNS module with the selected
  server (other query types get an empty NOERROR). In direct mode the module
  (`dns-module`) is routed to `direct`: the selected server is queried outside
  the tunnel through protected sockets, for app lookups and for the core's own
  (IP rules, direct destinations). Go instead forwards port 53 to 1.1.1.1 and
  resolves through `localhost`; xray-rust reads `localhost` as a server named
  localhost:53, and the StaticOnly bootstrap has no system resolver. A custom
  DNS server given by name is resolved by Android into `dns.hosts` before TUN
  starts (presets carry their IP); without it StaticOnly returns SERVFAIL.
  Android resolves every proxy server name (VLESS/VMess `vnext`, Trojan and
  Shadowsocks `servers`, Hysteria, and an XHTTP `downloadSettings` address)
  the same way, under one 5-second budget.
- Ad blocking: the DNS outbound answers `geosite:category-ads-all` and
  `geosite:win-spy` (Go's list) with an empty NOERROR, as Go's
  `rcode://success` server does, which xray-rust rejects. It applies with
  FakeDNS and in direct DNS mode too; Go's direct mode skips ad blocking.
  xray-rust (unchanged in 0.8.1) caps a config at 250,000 domain matchers
  shared by routing and DNS-outbound rules, and ad blocking alone expands to
  about 187k (category-ads-all 186,402 + win-spy 327 in the bundled snapshot).
  Ad blocking together with a GeoSite rule on `cn`, `china-list` (about 111k
  each) or `category-ads-all` is therefore rejected before VPN startup.
  category-ads-all is also at 93% of the core's per-category cap of 200,000
  entries: a Loyalsoldier update growing it by about 7% would stop every
  ad-blocking start.
- Per-flow owner check (the 1.6.4 protection) and the tethering toggle work
  as in Go for TUN flows, using the core's TUN flow admission. Go's validator
  rule is ported unchanged (`TunOwnerPolicy`).
  - «ТОЛЬКО»: only the selected apps' flows pass. Flows without an owner
    (tethered clients, or an app outside the VPN that binds a socket to
    `tun0`) are refused.
  - «КРОМЕ» with exclusions: flows without an owner are refused unless the
    tethering toggle is on, as in Go.
  - In other cases the check cannot refuse anything and is not installed.
  - The core asks before a TCP flow opens its outbound and before UDP
    (including DNS) is routed. The callback looks up the owner with
    `getConnectionOwnerUid`.
  - A lookup that throws allows the flow, as in Go. A lookup that stalls for
    5 s, or a full admission queue (four workers, 64 jobs), refuses the flow:
    TCP is reset, and a UDP tuple stays refused until it falls idle. Go would
    wait instead; neither build admits an unchecked flow, so an excluded app
    cannot flood the queue to get through. A legitimate burst of more than
    about 68 pending decisions (every app reconnecting at once) can reset
    fresh TCP flows; apps recover on their next connect.
  - The check covers TUN flows only. The loopback SOCKS listener has no
    login, because the core accepts only no-auth. Any app on the device,
    excluded or unselected ones included, can find its port and send TCP or
    UDP through it; in FULL/BYPASS routing that goes through the proxy and
    reveals the server's exit IP. Go prevents this with random per-session
    SOCKS credentials, on by default; a random port only slows a port scan.
    The split-tunnel screen of the Rust build says so.
  - Some OEMs report no owner even for an included app's socket bound to
    `tun0`; that flow is dropped in «ТОЛЬКО», as Go drops it.
  - While the check is installed, the core drops local ICMP. Otherwise it
    answers pings itself, so the check is installed only when it can refuse
    something.
- GeoIP, GeoSite, domain suffixes, individual sites and Russian-service lists.
  BYPASS sends matches directly; ONLY sends matches through the proxy. FULL
  disables destination rules. The app selection is applied by Android before
  these rules.
- The bundled Loyalsoldier databases are the checksum-pinned 202609082347 snapshot.
  The existing routing screen downloads updates. A complete candidate pair is
  validated through Rust before an atomic pointer selects it; failure retains
  the prior pair. Reconnect VPN to apply new rules or databases.
- Domain routing enables bounded FakeDNS automatically (4096 addresses, 300-second
  leases) to retain domain identity through TUN. Keep domain detection enabled.
  Apps then get FakeDNS answers in both DNS modes; direct mode applies to the
  core's own lookups. Applications using their own encrypted DNS or cached real IPs
  may evade GeoSite matching; turn off their secure-DNS override and restart them
  after changing routing. FakeDNS returns IPv4 and suppresses AAAA in this mode.
- Heartbeat probes: SOCKS, XRAYDELAY and PASSIVE.
  - SOCKS: custom `http://` and `https://` targets. HTTPS runs TLS with
    certificate and hostname checks inside the SOCKS tunnel.
  - XRAYDELAY: one HTTP(S) GET inside the core through the proxy outbound
    (`probeOutboundUrl`, 10 s), bypassing routing. In ONLY mode, where the
    default outbound is direct, a dead proxy therefore cannot look alive.
    URLs the core refuses (IPv6 literal, userinfo, fragment) fall back to the
    SOCKS probe with one warning.
  - PASSIVE runs only the TUN checks below, with no probe in the loop or on
    screen wake.
- Liveness comes from the core's live TUN counters.
  - Data counts as received only when TCP/UDP remote read bytes grow. The
    core's own DNS/FakeDNS answers, ICMP replies and TCP control packets do
    not count.
  - As in Go, an exited TUN fd read/write loop reconnects.
  - The TUN stall watchdog runs the failure action after 120 s without
    received data while at least 2 TUN flows are open.
  - For the watchdog only, TCP payload the outbound accepted also counts as
    activity. xray-rust ACKs an app's upload locally, while Go's tun2socks
    refreshes on every TUN write (including those ACKs). Without this, a
    reply-less upload longer than 2 minutes (HTTP/1.1 PUT, FTP STOR) would
    trigger a reconnect.
  - UDP sends never block and do not count. The probe-skip freshness check
    stays read-only.
- Network changes reconnect after the usual 2 s debounce. Hysteria 2
  profiles rebind the QUIC carrier onto the new network instead.
  - A follow-up check confirms the rebind: one GET through the proxy outbound
    inside the core (5 s, bypassing routing), so a direct route or direct DNS
    answer cannot pass for the proxy. It allows two attempts, 3 s apart.
  - PASSIVE sends no probe: there any TUN data received after the rebind
    counts, a direct route included, and a session without any reconnects.
  - When the rebind throws or both checks fail, the app falls back to a full
    reconnect.
- switchConfig measures candidates through their protocol, as Go does.
  - Each runs in a temporary core started from the production probe variant:
    the candidate's exact proxy outbound plus a loopback SOCKS on an
    ephemeral port.
  - 5 s timeout, at most two at once; a queued candidate waits at most 20 s
    for a slot, then counts as unmeasured. Their server lookups run on their
    own two workers, so they never hold up the VPN's own start. The running
    VpnService protects their sockets.
  - A heartbeat URL the core refuses (IPv6 literal, userinfo, fragment,
    upper-case scheme) is measured through the default
    `http://cp.cloudflare.com/generate_204`.
  - Only profiles the Rust build supports are considered.

Remaining limits. These controls stay visible but disabled, with the reason
shown. Where a stored value would change the config (proxy-only mode, MTU,
Mux, raw JSON, ECH), the builder also refuses it before VPN startup.

| Setting | Why it stays off |
| --- | --- |
| SOCKS login/password | The core's SOCKS inbound is no-auth only, so any local app can use the listener while the VPN runs; app selection and the owner check do not cover it. |
| Proxy-only mode | The unauthenticated SOCKS would be the only way into the tunnel. |
| ICMP toggle | TUN-level behaviour with no config knob. The core answers pings locally, or drops them under the owner check. |
| MTU other than 1500 | The TUN runtime path is verified only at 1500. |
| Mux | The core has no VLESS mux, XHTTP needs `concurrency: -1`, and the core caps concurrency at 64 where the app allows 1024. |
| ECH | Not implemented in the core. |
| Raw Xray JSON, Observatory | Managed JSON is not supported. |
| App update checks (upstream releases) | The Rust build is updated manually from the fork. |

ICMP handling is the Rust core's local synthetic behavior; it is not a remote
ping measurement.

Packet path: Android TUN → Rust userspace stack → VLESS, Trojan, VMess,
Shadowsocks 2022 or Hysteria 2.
A no-auth SOCKS listener on `127.0.0.1` supports the app's heartbeat and IP check.
Device TUN traffic does not traverse this listener. SOCKS credentials settings
do not apply to this experimental build, so other apps, excluded ones
included, can connect to it, unlike Go's default random credentials. Speed and totals come from the core's
live TUN payload counters (bytes written to and read from outbounds, proxy and
direct), not tun2socks IP-byte counters; the per-outbound snapshot in the
diagnostics counts closed connections only.

## xray-rust 0.8.1 (1.6.6-rust.8)

The core moves from 0.7.0 to stable xray-rust v0.8.1, commit
`5b61eee201fac8639cb1dac0349e34af65db90f7`, built without local changes. The
C ABI goes from 1.7 to 1.12, adding to the existing interface without breaking
it.

Most features below shipped in 0.8.0. Version 0.8.1 itself adds only the
Apple startup-probe preflight (ABI 1.12, unused on Android) and dependency
updates; protocol and config formats are unchanged. rust.7 ran on 0.7.0,
which had none of these features.

Upstream requests now used by the app:

- PR #48, Vision direct mode beneath plain TLS: TLS + Vision is enabled.
- PR #49, the on-demand outbound URL probe (released as ABI 1.9): the
  XRAYDELAY heartbeat and switchConfig measurement through the protocol.
- PR #50, the `blackhole` outbound: QUIC blocking and the UDP switch.
- Issue #51, TUN flow admission (ABI 1.11): the per-flow owner check and the
  tethering toggle.
- Issue #52, ClientHello fragmentation and UDP noise: both network settings.
- Issue #53, Hysteria 2 Salamander, port hopping, raisable stream budgets
  (ABI 1.10) and Kotlin rebind: these Hysteria 2 profiles, 256/128 streams,
  and rebinding on network changes.
- The maintainer's PR #42: Trojan, Shadowsocks 2022 and VMess AEAD.

Fixes that change both builds:

- Trojan links now keep `security` (`reality`/`none`), the REALITY keys
  (`pbk`, `sid`, `spx`, `pqv`), `pinSHA256`, `alpn` and `ech`. All of these
  were silently dropped before.
- Percent-encoded SIP002 Shadowsocks keys are now decoded; `%2B`/`%3D` used to
  stay inside the key.
- Percent-encoded Trojan passwords are now decoded (`p%40ss%3A1` is
  `p@ss:1`), as v2rayN and v2rayNG read them; they used to reach the server
  encoded. A stray `%` leaves the password as given.

Rust-only changes:

- The WebSocket `Host` header is written as `host`. This removes a
  deprecation warning the core printed for every WebSocket profile.
- With UDP off, the blackhole rule also covers the local SOCKS, because
  xray-rust accepts UDP ASSOCIATE despite `udp: false`.

The Go build's behaviour is otherwise unchanged.

Device interop harness. `scripts/test-rust-transports.py` exports production
configs through the parser and the Rust builder, then runs them on the emulator
against the pinned Xray-core 26.7.28. Every case runs:

- plain and inner-TLS echo through SOCKS;
- the in-core XRAYDELAY probe;
- the switchConfig candidate probe.

It has 32 cases in groups:

| Group | Cases |
| --- | --- |
| `vless` | 8 carrier/security combinations. |
| `vision` | Both Vision flows over TLS and over REALITY. |
| `trojan` | TCP/TLS with SOCKS UDP, WebSocket/TLS, TCP/REALITY. |
| `vmess` | TCP/TLS with ChaCha20 and SOCKS UDP; WebSocket/TLS with `auto`. |
| `ss` | Each SS2022 method plus an AES identity-key chain, TCP and SOCKS UDP. |
| `hysteria` | Pin; `insecure=1` + pin; Salamander; noise; Salamander + noise; each with SOCKS UDP. |
| `fragment` | ClientHello fragmentation over TCP/TLS, TCP/REALITY and REALITY + Vision. |
| `udp` | Hysteria 2 with UDP on, QUIC blocked, and UDP off (below). |

The `udp` cases send UDP packets through the TUN packet path to a UDP echo
and to port 443. The server redirects port 443 to the same echo, so a missing
reply proves the client's rule dropped the packet. A VMess link has no pin
field, so the exporter pins the test certificate on the parsed profile.

Environment flags:

- `TEAPOD_INTEROP_GROUPS=trojan,ss` and `TEAPOD_INTEROP_CASES=name,…` select
  cases. `TEAPOD_INTEROP_VISION_ONLY=1` and `TEAPOD_INTEROP_HYSTERIA_ONLY=1`
  still work.
- `TEAPOD_INTEROP_CHECK_ONLY=1` runs without a device. It checks the server
  config with `xray run -test` and every exported VPN and probe config with
  `xray-rust config check`. Set `XRAY_RUST_CLI` when the host CLI is not at
  `.native/host-cli-0.8.1/xray-rust`; a device run also does this check when
  the CLI exists.
- `TEAPOD_INTEROP_WORKDIR=dir` keeps the generated configs and `xray.log`.

```sh
TEAPOD_INTEROP_CHECK_ONLY=1 python3 scripts/test-rust-transports.py
JAVA_HOME=/path/to/jdk17 ANDROID_SERIAL=emulator-5554 \
  TEAPOD_INTEROP_GROUPS=trojan,vmess,ss python3 scripts/test-rust-transports.py
```

`TunAdmissionTest` (xraymobile androidTest, needs no fixture or VPN permission)
checks the admission behaviour the owner check relies on. It uses synthetic
app packets through the core's packet I/O and confirms that:

- the callback sees the app's own tuple;
- a denied UDP datagram never reaches its target;
- a denied TCP flow is reset before its outbound opens;
- a Java exception in the callback denies;
- a timeout allows only with `failOpen` (the app passes `failOpen = false`);
- local ICMP is answered without a policy and dropped with one.

```sh
cd android
JAVA_HOME=/path/to/jdk17 ./gradlew :xraymobile:connectedDebugAndroidTest \
  -Pdart-defines=VEVBUE9EX0NPUkU9cnVzdA== \
  -Pandroid.testInstrumentationRunnerArguments.class=org.xrayrust.mobile.TunAdmissionTest
```

The owner rule itself is covered by JVM tests (`android/app/src/testRust`,
`:app:testReleaseUnitTest` with `TEAPOD_CORE=rust`).

Verification for 1.6.6-rust.8:

- 204 Flutter tests passed in each build mode; analysis has only the three
  existing `onReorder` deprecation infos; the 6 JVM `TunOwnerPolicyTest`
  cases pass (owner decision checked against the Go validator).
- Every Rust config the production builder exported (all protocols,
  transports, security, routing modes, DNS presets, fragmentation, noise,
  QUIC/UDP blocking; 1,395 built, 340 refused as expected) was accepted by
  `xray-rust config check` 0.8.1, as built and with Android's server-address
  resolution applied, except REALITY with the `android` fingerprint (no
  X25519 key share). The probe configs started in the host core.
- On the API 36 emulator, all 32 interop cases passed against Xray-core
  26.7.28 (groups vless, vision, hysteria, trojan, vmess, ss, fragment, udp):
  plain and inner-TLS echo, SOCKS and TUN UDP checks, the in-core probe and
  the temporary-core candidate probe. The 6 GeoIP/GeoSite tests, the TUN
  counter test and the 4 `TunAdmissionTest` cases passed.
- The release APK installed over rust.7 kept its profile. Through the
  installed APK's TUN, a different UID (shell, 2000) downloaded and
  SHA-256-verified 8 MiB over Trojan TLS and over Shadowsocks 2022; the
  server logs show the flows on the Trojan and Shadowsocks inbounds. UI
  disconnects removed `tun0`.
- Release APKs keep the earlier signing certificate, raise the version code
  (12611/14611), pass 16 KiB alignment checks and package the newly built
  xray-rust 0.8.1 core (compared after symbol stripping).
- Not covered: owner check and Hysteria rebind on a phone (Wi-Fi ↔ LTE,
  OEM UID visibility), screen-off soak, and the remaining no-auth loopback
  SOCKS exposure (upstream aimalygin/xray-rust#80 adds SOCKS passwords).

## Hysteria 2 in the Rust build (1.6.6-rust.7)

As of rust.7, on xray-rust 0.7.0. rust.8 lifts the Salamander, port-hopping,
noise and 64/32-stream limits below; see the support list above.

- `hy2://` / `hysteria2://` profiles run on the core's Hysteria 2 client:
  `protocol: hysteria`, stock QUIC TLS with ALPN `h3`, password auth (1–4096
  bytes, no control characters), default BBR. The core keeps one QUIC
  connection per server with fixed budgets of 64 concurrent TCP streams and
  32 UDP sessions for the whole device: a further connection fails at once
  until one closes. UDP is carried in 1200-byte QUIC datagrams and fragmented
  above that.
- Rejected before VPN startup with an explanation: Salamander `obfs`, port
  hopping (a port range/list or `mport`), Brutal/bandwidth and other QUIC
  overrides, and noise (it needs `sockopt.dialerProxy`). Mux and fragmentation
  do not apply to Hysteria 2 in either build and do not block it.
- `pinSHA256` (hex, colon-hex or base64 of the leaf certificate's SHA-256) is
  written as hex `pinnedPeerCertSha256` by both builders: it is also the only
  pin key of Xray-core `1aabe7ea` (teapod-core 1.1.15), which silently ignored
  the earlier Go `pinnedPeerCertificateChainSha256` key (this fix applies to
  both builds). TLS fingerprint and ALPN overrides are dropped, as QUIC TLS is
  not shaped.
- A certificate pin wins over `allowInsecure` (`insecure=1`), for Hysteria 2
  and VLESS TLS, in both builds: such a profile is built with
  `allowInsecure: false` and the pin, so only the pinned certificate is
  accepted (Xray-core `1aabe7ea` refuses `allowInsecure: true` outright). Rust
  still rejects `allowInsecure` without a pin.
- Routing, FakeDNS and DNS are the same as for VLESS; domain destinations are
  passed to the server. Android resolves every VLESS `vnext` and Hysteria
  server name into `dns.hosts` before TUN starts, under one 5-second budget;
  IP-literal servers are used as is.
- Share links: `host:port/?…` keeps its port. A port range or list
  (`20000-30000`, `443,5000-6000`) or `mport` keeps the first port in `port`
  and the specification in `hopPorts`, instead of silently becoming 443 (this
  parser fix applies to both builds). An unreadable `mport` (for example
  sing-box's `20000:30000`) is ignored when the link's own port is valid, as
  before, so such a profile still imports with that port. The Go build passes it to Xray-core as
  `finalmask.quicParams.udpHop.ports` (format checked against Xray-core
  `1aabe7ea` used by teapod-core 1.1.15 and v26.7.28).
- `scripts/test-rust-transports.py` adds two Hysteria 2 cases (pin, and
  `insecure=1` + pin) against the pinned Xray 26.7.28 `hysteria` inbound, each
  with TCP, inner-TLS and SOCKS UDP echo (64/1000/3000 bytes);
  `TEAPOD_INTEROP_HYSTERIA_ONLY=1` runs only them.

Verification for 1.6.6-rust.7:

- 152 Flutter tests passed in each build mode; analysis has only the three
  existing `onReorder` deprecation infos.
- Rust configs exported through the production builder were accepted by
  `xray-rust config check` across Hysteria 2 and VLESS profiles, routing modes,
  DNS presets, direct/proxy DNS and ad blocking; the expected Hysteria 2
  rejections (Salamander, port hopping, Go pin key, `allowInsecure` without a
  pin) were confirmed against the core. On the host, ad-blocked domains got an
  empty NOERROR and direct DNS resolved outside the tunnel.
- On the API 36 emulator: all 10 VLESS combinations and both Hysteria 2 cases
  (TCP, inner TLS and SOCKS UDP echo) against Xray-core 26.7.28; the 6
  GeoIP/GeoSite tests and the new TUN counter test.
- The release APK installed over rust.6 kept its profile. Through the installed
  APK's TUN, a different UID (shell, 2000) downloaded and SHA-256-verified
  64 MiB over xHTTP/TLS, and 8 MiB plus 64 MiB over Hysteria 2. During the
  64 MiB transfer the home screen totals grew live (29.6 → 58.6 → 64.0 MB).
  Disconnecting through the UI removed `tun0`.
- Release APKs keep the rust.4–rust.6 signing certificate, raise the version
  code (12610/14610), pass 16 KiB alignment checks and package the same
  xray-rust 0.7.0 core as rust.6.
- Not covered by these tests: heavy browsing against the 64-stream Hysteria 2
  limit, screen-off soak for the stall watchdog, and PASSIVE on a phone.

## Build selection and feature flags

`TEAPOD_CORE` is a compile-time flag, with `go` as the default. Flutter forwards
it to Gradle in `dart-defines`; Gradle selects exactly one native source set and
dependency. Native `getEngine` is checked before connecting, rejecting a stale or
mismatched frontend/native build. There is no runtime switch between engines.

```sh
# Original Go core; Rust/rustup is not needed.
JAVA_HOME=/path/to/jdk17 ./build.sh release
./build.sh test

# Experimental Rust core; installs alongside Go and upgrades earlier Rust Probe versions.
JAVA_HOME=/path/to/jdk17 ./build-rust.sh release
./build-rust.sh test
```

Artifacts are copied to `build/artifacts/go/` and `build/artifacts/rust/`.
Go builds include arm64, armv7 and x86_64; Rust builds include arm64 and x86_64.
Both are release builds with AOT/R8; they currently use the local Android debug
signing key. A published release signing setup is a separate task.

For direct Flutter commands, prepare dependencies first:

```sh
./build-rust.sh binaries
flutter build apk --release --dart-define=TEAPOD_CORE=rust \
  --target-platform android-arm64,android-x64 --split-per-abi \
  --build-name=1.6.6-rust.8 --build-number=10611

# Native Android binding tests use the same base64-encoded Flutter flag.
cd android
JAVA_HOME=/path/to/jdk17 ./gradlew :xraymobile:connectedDebugAndroidTest \
  -Pdart-defines=VEVBUE9EX0NPUkU9cnVzdA==
```

`lib/core/constants/core_features.dart` is the per-core feature matrix.
Unsupported controls remain visible inside `FeatureGate`, with interaction and
keyboard focus disabled and an explanation. Imported incompatible settings have
an explicit reset action. The config builder still rejects unsupported values;
a UI change alone cannot bypass validation. Go exposes its existing controls.
Rust's upstream update buttons are gated; its source link points at this fork.

Shared requirements: Flutter/Dart compatible with `pubspec.yaml`, Android SDK,
NDK 28.2.13676358, CMake 3.22.1, Python 3 and JDK 17 (or a compatible JDK).
Rust additionally needs rustup; its first build installs Rust 1.96.0 and the
Android targets. `JAVA_HOME` is honored without changing global Flutter settings.

`fetch-go-core.py` downloads checksum-pinned teapod-core 1.1.15. Both builds use
the same checksum-pinned geodata assets. `build-rust-core.py` builds the pinned,
unmodified Rust source and refuses a checkout with local changes. See
[Android binding notes](android/xraymobile/README.md).

The original Go service is preserved in `android/app/src/go/`; the tested Rust
service and geodata adapter are in `android/app/src/rust/`. Notifications and
service interfaces remain compatible with the shared UI. Future lifecycle fixes
must be evaluated for both implementations.

Controlled battery savings have not been measured. These builds support
comparison; phone battery-screen observations are not a controlled A/B result.

## TeapodStream 1.6.6 and core 0.7.0 (1.6.6-rust.6)

The fork now merges upstream TeapodStream 1.6.6. The core moves to stable
xray-rust v0.7.0, commit `67969094b352f948c6b8b9e2ac75402c577cb7f7`, built
without local changes: 0.7.0 ships the same GeoIP budgets that the removed
`geo-budgets.patch` added (500,000 CIDRs per category, 750,000 IP matchers,
1,000,000 matchers in total). The C ABI goes from 1.4 to 1.7 with additive
changes only. The binding is resynchronised with v0.7.0 and keeps the local
`geodataDirectory` extension. Hysteria 2, WireGuard, profile import and carrier
rebinding are in the core but are not used by the app yet. Package ID, signing
key and bundled geodata are unchanged, so the APK installs over earlier Rust
Probe versions.

Relevant core changes for VLESS through TUN:
- A client TCP FIN is forwarded after buffered upload drains, so replies
  after a half-close are kept and naturally closed flows are released.
- Download and cancellation stay responsive while an upload is blocked.
- Fewer allocations in async setup and bounded TUN upload queues.
- The 0.7.0 changelog has no TLS/Vision change. Vision over ordinary TLS
  stays gated without a new test.

Upstream 1.6.4–1.6.6 in the Rust build:
- Custom DoT/DoH/UDP DNS addresses with default ports work. xray-rust takes a
  DoT port only from its `tls://` URL, so the Rust builder writes it there.
  The upstream parser mangled IPv6 literals (`2001:db8::1`,
  `[2001:db8::1]:5353`); the fix applies to both builds.
- The heartbeat target URL is configurable. The Rust SOCKS probe accepts any
  2xx response and supports `https://` with TLS inside the SOCKS tunnel.
- `switchConfig` (formerly `urltest`) works with TCP-ping candidate checks.
  XRAYDELAY, PASSIVE, measuring candidates through the protocol, and the
  tethering switch are gated with explanations (see the support list above).
- The Rust build has no per-flow owner check, so the 1.6.4 protection against
  excluded apps binding to `tun0` does not apply. The UI and the service log say so.

Verification for this update:

- 129 Flutter tests passed in each build mode; analysis has only the three
  existing `onReorder` deprecation infos.
- Host tests of the pinned 0.7.0 source: `xray-config` 391 passed; TUN tests
  in `xray-tun` 27 passed and `xray-core-rs` 264 passed (4 Hysteria/WireGuard
  tests need a reference server and were ignored), including the new FIN and
  stalled-upload regressions.
- 1,380 Rust configs exported through the production builder (30 profile
  variants of the supported transports, security, Vision, xHTTP modes and
  certificate pins; 5 routing modes; 24 DNS variants; 9 fingerprints) were
  each checked with `xray-rust config check`, both as built and with Android's
  server-address resolution applied. All were accepted except REALITY with the
  `android` fingerprint, which has no X25519 key share. That fingerprint cannot
  complete REALITY in the Go core either.
- On the API 36 emulator, all 10 VLESS interoperability combinations passed
  again against Xray-core 26.7.28, and all 6 GeoIP/GeoSite tests passed.
- Release APKs keep the rust.5 signing certificate, raise the version code
  (12609/14609), pass 16 KiB alignment checks, and package exactly the newly
  built core (compared after symbol stripping). The Go build still produces
  all three ABIs.
- Installing over rust.5 kept an imported profile and an app-data marker.
  Through the installed release APK's TUN, a different UID (shell, 2000)
  downloaded and SHA-256-verified 8 MiB over xHTTP/TLS, then 8 MiB more with
  a client half-close, then 8 MiB over xHTTP/REALITY. The heartbeat probe went
  through the tunnel. Disconnecting through the UI removed `tun0`. The fixture
  used a local reference server and generated test credentials.

## Core update (1.6.3-rust.5)

The core is pinned to stable xray-rust v0.6.1, commit
`ed5258a3a589c2a1f9330142f37c8f3d28a640fa`. The existing GeoIP budget patch,
bundled geodata, supported protocols, package ID and signing key are retained.
Installing this APK updates rust.4 without requiring profile re-import.

Upstream changes increase the default XHTTP/H2 stream receive window from
65,535 bytes to 4 MiB (connection credit stays 16 MiB), avoiding the small-window
single-download limit on high-latency paths. A stalled TUN TCP reader no longer
blocks neighboring TCP, UDP or control events. Download prefetch is bounded to
256 KiB per flow and immediately ready reads are batched without waiting for
more data. Larger H2 receive credit permits more buffering; the TUN prefetch
limit is not a whole-process memory limit.

No additional setting is needed to use these fixes. Vision over ordinary TLS
remains gated; the upstream TLS/Vision implementation was not changed by this
release. The public Android bindings and C ABI are unchanged. Keep rust.4 and
rust.5 energy observations separate because the native data path has changed.

Verification for this update:

- 90 Flutter tests passed in each build mode; analysis has only the three
  existing `onReorder` deprecation infos.
- 19 upstream regression tests passed against the patched v0.6.1 source:
  H2 window validation, receive-window limits/replenishment, all H2 modes,
  stalled-reader isolation, bounded prefetch, DNS/FIN ordering and cancellation.
- Six Android GeoIP/GeoSite tests passed, including simultaneous loading of
  the bundled US/RU and Cloudflare/YouTube categories.
- All 10 Android VLESS interoperability combinations passed again, transferring
  both plain payloads and inner TLS against the local Xray-core 26.7.28 server.
- Both release APKs retain the rust.4 signing certificate, increase the Android
  version code and pass 16 KiB ZIP alignment checks. Their packaged Rust libraries
  match the newly built v0.6.1 libraries after symbol stripping.
- On an isolated API 36 emulator, installation over rust.4 retained an app-data
  marker. A separate application UID downloaded and SHA-256-verified 8 MiB through
  the installed release APK's Android TUN with xHTTP/TLS, then another 8 MiB with
  xHTTP/REALITY. Both sessions disconnected cleanly. The fixture used a local
  reference server and generated test credentials.

## Verification of additional VLESS transports (1.6.3-rust.4)

90 Flutter tests passed in each build mode. The local Android interoperability
campaign passed all 10 enabled combinations against Xray-core v26.7.28,
including both REALITY/Vision flows. Each combination transferred 128 KiB in
plain echo and another 128 KiB inside TLS, with byte-for-byte verification.
TLS/Vision was separately tested and failed after the inner handshake; its flag
remains disabled. The native core itself was not modified for this expansion.


The Dart tests check carrier/security/flow combinations, TCP/RAW and WebSocket
aliases, preservation of Vision flow/path/SNI, TLS certificate pin conversion,
unsupported combinations and the per-engine QUIC policy. Rust does not inherit
Go's automatic host-side QUIC toggle for Vision; the native core enforces the
selected Vision UDP policy.

The optional local interoperability campaign uses Xray-core v26.7.28, ephemeral
keys/certificates and echo endpoints bound to host loopback. Flutter exports
configs through the production parser and builder. Android native clients send
both plain payloads and an inner TLS session (4 × 32 KiB per stream) through each
supported combination. It requires a running Android emulator; no live VPN
profile is needed:

```sh
JAVA_HOME=/path/to/jdk17 ANDROID_SERIAL=emulator-5554 \
  python3 scripts/test-rust-transports.py
```

The default download is the checksum-pinned Linux x86_64 Xray reference binary;
other platforms can set `XRAY_REFERENCE` to a compatible local binary. The
harness uses emulator host alias `10.0.2.2`; physical-device battery and WAN
performance measurements are outside this test.

## Verification of separate builds (1.6.3-rust.3)

- 71 Flutter tests passed in each mode (`TEAPOD_CORE=go` and `rust`).
  Coverage includes unchanged Go feature availability, visible-but-disabled Rust
  controls, explicit reset of an imported unsupported value, per-core config and
  SOCKS credentials, and refusal to connect with a mismatched native engine.
- Release APKs were built for all three Go ABIs and both Rust ABIs. Archive
  inspection confirms exactly the selected core: `libgojni.so` in Go and
  `libxray_ffi.so` / `libxray_mobile_jni.so` in Rust.
- Both installed builds connected through their Flutter UI with the same separately
  imported VLESS/XHTTP/REALITY profile. A different application UID received HTTP
  204 through each VPN, followed by a successful explicit disconnect.
- The Go service source is byte-for-byte identical to the upstream baseline.
- The installed Rust network screen retains SOCKS authentication and proxy-only
  controls with disabled interaction and explanatory text.
- Static analysis has no new findings; three existing `onReorder` deprecation
  infos remain.

## Verification of routing (1.6.3-rust.2)

- 63 Flutter tests passed, including both routing modes and failed-download/failed-validation retention.
- 6 Android native tests passed: GeoSite match/non-match, GeoIP literal/domain matching,
  missing/corrupt databases, and simultaneous loading of bundled US/RU plus Cloudflare/YouTube sets.
- On the API 36 emulator, a separate application fetched an external-IP endpoint:
  baseline used the VPN IP; GeoSite BYPASS, GeoIP US BYPASS, and a combined GeoSite/GeoIP
  fallback used the physical connection's IP; GeoSite ONLY used the VPN IP for a match
  and the physical IP for a different domain.
- The same application used the physical IP when excluded by Android's app allowlist,
  and the VPN IP when selected. The test disconnected between cases.
- Updating databases through the app downloaded and validated a new pair, activated
  its generation, and retained the bundled pair. Combined GeoIP/GeoSite routing
  passed again after reconnecting against the downloaded generation.
- Native libraries packaged in both APKs match the patched build after Android's symbol stripping.

## Validation on a phone

The initial 1.6.3-rust.1 validation on 2026-09-09 passed 57 Flutter tests. An Android API 36 x86_64
emulator connected using a separately imported VLESS/XHTTP/REALITY profile.
A second application (a different UID) received valid DNS answers over UDP
through the TUN DNS endpoint and HTTP 204 through the tunnel. The same probes
passed after disconnecting and reconnecting. The native diagnostic snapshot
reported `tunBackend: fd` and no packet drops in the sampled run.
`flutter analyze` reports only three pre-existing `onReorder` deprecation infos.
Physical-device battery, Wi-Fi/cellular transitions and extended sleep tests
remain to be measured; the emulator result is a functional smoke test.

Import a VLESS share link in the app, approve the Android VPN request, and test
web browsing, DNS/UDP, screen-off resume, reconnect and disconnect. In the
diagnostic snapshot, `engine` must be `xray-rust 0.8.1` and `tunBackend` must be
`fd`; incoming and outgoing packet counters should increase with app traffic.

Compare energy against the original app on the same phone, server, network and
workload. Desktop/emulator tests cannot establish a battery-life improvement.

## Dependencies

- [xray-rust source](https://github.com/aimalygin/xray-rust), MPL-2.0.
- [Pinned source v0.8.1](https://github.com/aimalygin/xray-rust/tree/5b61eee201fac8639cb1dac0349e34af65db90f7), unmodified;
  [third-party notices](third_party/xray-rust/THIRD_PARTY_NOTICES.md), including the vendored GotaTun WireGuard engine.
- [Bundled geodata snapshot](https://github.com/Loyalsoldier/v2ray-rules-dat/releases/tag/202609082347).
- Upstream TeapodStream retains its existing license.
