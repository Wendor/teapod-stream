# IpInfoProvider — exit IP and country

**Files:** `lib/providers/ip_info_provider.dart`, `lib/core/services/ip_lookup.dart`

`IpInfoNotifier` (`AsyncNotifier<IpInfo?>`) watches `vpnConnectionStateProvider`. When connected and the SOCKS port
is known it asks the lookup services **through the tunnel's SOCKS** and returns `IpInfo(ip, country?, countryCode?)`;
otherwise `null`. Works in TUN and proxy-only mode.

**Lookup chain** (`lib/core/services/ip_lookup.dart`, `IpLookup` held by `ipLookupProvider`): `ip-api.com` (IP,
country, code) → `ipinfo.io` (IP, code) → `api.ipify.org` (IP only), 4 s per service and 10 s for the whole chain;
the first answer with an IP wins. The order is kept per effective config id, in memory only: the service that
answered goes first, one that failed goes last for an hour. After a restart the worst case is one slow service once.
In `onlySelected` routing every core sends `IpLookupSource.hosts` through the proxy, so the lookup sees the tunnel's
exit ([xray](xray_config_builder.md), [sing-box](singbox_config_builder.md); xray-rust inherits the Go rules).

It rebuilds by itself on state changes — don't `ref.refresh` it from a listener of the VPN state (circular
dependency).

Shown on Home under the active config while connected: `cc · ip`, the IP alone when the service gave no country,
`IP not detected` (`homeIpUnknown`) when the chain gave up, `— · —` while it runs.
