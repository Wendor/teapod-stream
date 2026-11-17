# Security policy

TeapodStream exists to keep traffic where the user put it. It was started to close a hole in Linux and Android:
an app that is *outside* the split tunnel can bind a socket to the VPN interface (`SO_BINDTODEVICE`) and send traffic
through the tunnel anyway — and so learn that a VPN is on and the IP address of the VPN server. Strict per-flow owner
checks in tun2socks, dropping connections whose owner is unknown (unless the user turns on tethering through the
VPN, which can't be told apart from such an app), and keeping DNS inside the tunnel all come from that goal. A way
around any of them is a vulnerability, and we treat it as the most serious kind of bug.

## Reporting

**Don't open a public issue.** Report privately through
[GitHub security advisories](https://github.com/Wendor/teapod-stream/security/advisories/new).

Include:

- the app version, the device and Android version, the core (xray-core, xray-rust or sing-box) and the protocol;
- the settings involved: VPN mode and the split-tunnel list, kill switch, DNS, tethering, automation;
- what an attacker learns or does, and the steps or a proof-of-concept app to reproduce it;
- masked logs — never real server addresses, subscription links, UUIDs or keys.

This is a project maintained in spare time. Expect an acknowledgement within 7 days and a fix for a critical issue
within 30 days. Please give us that time before publishing. We credit reporters in the advisory and the release
notes, unless you ask us not to.

## Supported versions

Only the latest release and the latest pre-release get fixes. The app updates itself from GitHub releases.

## What counts

The attacker is an ordinary app on the same device, without root, with any permissions it can get from the user
without a system dialog; or a link, a QR code, a subscription or a server the user imports.

**Critical**

- Traffic of an app excluded from the tunnel (or not included in it) goes through the tunnel, or traffic of an
  included app goes around it.
- DNS queries leave outside the tunnel, or reach a resolver other than the configured one.
- An unprivileged app learns the VPN server's IP address while the VPN is on; or an app whose traffic goes through
  the tunnel learns the device's real IP.
- The kill switch lets traffic out during a reconnect, a config switch, a core crash or a network change.

**High**

- Another app reaches the local SOCKS inbound or any other listener of the app without its credentials.
- Another app connects, disconnects or reconfigures the VPN without the automation option turned on.
- An imported link, QR code or subscription changes security settings, opens a listener, or makes the app send
  requests from the real IP without the user confirming it.
- Secrets (server credentials, subscription URLs, keys) leak to logs at the default level, backups, other apps or
  exported files.

**Out of scope**

- A rooted device, a modified system, or an attacker with ADB access.
- What Android itself exposes: that some VPN is on (`TRANSPORT_VPN`, the key icon), the VPN app's package name.
- The risks accepted in [`wiki/security.md`](wiki/security.md#accepted-risks), such as the loopback SOCKS fingerprint
  and direct pings to servers.
- Bugs in xray-core, sing-box or xray-rust that don't depend on how TeapodStream uses them — report those upstream;
  tell us too if the app makes them exploitable.
- What the VPN server or its operator can see.

How the app protects against these: [`wiki/security.md`](wiki/security.md).
