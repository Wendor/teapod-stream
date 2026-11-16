# IpInfoProvider — exit IP and country

**File:** `lib/providers/ip_info_provider.dart`

`IpInfoNotifier` (`AsyncNotifier<IpInfo?>`) watches `vpnConnectionStateProvider`. When connected and the SOCKS port
is known it requests `http://ip-api.com/json?fields=query,country,countryCode,status` **through the tunnel's SOCKS**
(10 s timeout) and returns `IpInfo(ip, country, countryCode)`; otherwise `null`. Works in TUN and proxy-only mode.

It rebuilds by itself on state changes — don't `ref.refresh` it from a listener of the VPN state (circular
dependency).

Shown on Home under the active config while connected.
