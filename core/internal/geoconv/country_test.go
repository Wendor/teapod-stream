package geoconv

import (
	"net"
	"testing"

	"github.com/xtls/xray-core/common/geodata"
)

func cidr(t *testing.T, s string) *geodata.CIDR {
	t.Helper()
	_, n, err := net.ParseCIDR(s)
	if err != nil {
		t.Fatal(err)
	}
	ip := n.IP
	if v4 := ip.To4(); v4 != nil {
		ip = v4
	}
	bits, _ := n.Mask.Size()
	return &geodata.CIDR{Ip: ip, Prefix: uint32(bits)}
}

func TestCountryForIP(t *testing.T) {
	list := &geodata.GeoIPList{Entry: []*geodata.GeoIP{
		{Code: "PRIVATE", Cidr: []*geodata.CIDR{cidr(t, "10.0.0.0/8")}},
		{Code: "nl", Cidr: []*geodata.CIDR{cidr(t, "203.0.113.0/24"), cidr(t, "2001:db8::/32")}},
		{Code: "DE", Cidr: []*geodata.CIDR{cidr(t, "203.0.113.128/25")}},
		{Code: "CLOUDFLARE", Cidr: []*geodata.CIDR{cidr(t, "198.51.100.0/24")}},
		{Code: "RU", ReverseMatch: true, Cidr: []*geodata.CIDR{cidr(t, "192.0.2.0/24")}},
	}}
	for ip, want := range map[string]string{
		"203.0.113.7":        "NL", // upper-cased
		"203.0.113.200":      "DE", // the more specific range wins
		"::ffff:203.0.113.7": "NL", // IPv4-mapped IPv6
		"2001:db8::1":        "NL",
		"10.1.2.3":           "", // "private" is not a country
		"198.51.100.1":       "", // neither is a service list
		"8.8.8.8":            "", // reverse match never counts
		"not an ip":          "",
	} {
		if got := CountryForIP(list, ip); got != want {
			t.Errorf("CountryForIP(%q) = %q, want %q", ip, got, want)
		}
	}
}
