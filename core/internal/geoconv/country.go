package geoconv

import (
	"net/netip"
	"strings"

	"github.com/xtls/xray-core/common/geodata"
)

// CountryForIP returns the upper-case country code of the most specific geoip.dat range that contains ip, or ""
// when no country entry does. Only two-letter codes count: lists like "private", "cloudflare" or "telegram" are not
// countries, and reverse-match entries match everything outside their ranges.
func CountryForIP(list *geodata.GeoIPList, ip string) string {
	addr, err := netip.ParseAddr(ip)
	if err != nil {
		return ""
	}
	addr = addr.Unmap()
	best, bestBits := "", -1
	for _, entry := range list.GetEntry() {
		code := entry.GetCode()
		if len(code) != 2 || entry.GetReverseMatch() {
			continue
		}
		for _, c := range entry.GetCidr() {
			base, ok := netip.AddrFromSlice(c.GetIp())
			if !ok {
				continue
			}
			prefix := netip.PrefixFrom(base.Unmap(), int(c.GetPrefix()))
			if prefix.Bits() > bestBits && prefix.Contains(addr) {
				best, bestBits = strings.ToUpper(code), prefix.Bits()
			}
		}
	}
	return best
}
