package teapodcore

import (
	"net"
	"os"
	"path/filepath"
	"testing"

	"github.com/xtls/xray-core/common/geodata"
	"google.golang.org/protobuf/proto"
)

func TestCountryForIpReadsGeoipDat(t *testing.T) {
	dir := t.TempDir()
	if got := CountryForIp(dir, "203.0.113.7"); got != "" {
		t.Fatalf("without geoip.dat = %q, want empty", got)
	}
	_, n, _ := net.ParseCIDR("203.0.113.0/24")
	b, err := proto.Marshal(&geodata.GeoIPList{Entry: []*geodata.GeoIP{
		{Code: "NL", Cidr: []*geodata.CIDR{{Ip: n.IP.To4(), Prefix: 24}}},
	}})
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "geoip.dat"), b, 0o644); err != nil {
		t.Fatal(err)
	}
	if got := CountryForIp(dir, "203.0.113.7"); got != "NL" {
		t.Errorf("CountryForIp = %q, want NL", got)
	}
	if got := CountryForIp(dir, "198.51.100.1"); got != "" {
		t.Errorf("outside every range = %q, want empty", got)
	}
}
