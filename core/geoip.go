package teapodcore

import (
	"os"
	"path/filepath"

	"github.com/Wendor/teapod-core/internal/geoconv"
	"github.com/xtls/xray-core/common/geodata"
	"google.golang.org/protobuf/proto"
)

// CountryForIp returns the upper-case country code of ip from datDir/geoip.dat — the file the cores route with —
// or "" when the file can't be read or no country range contains ip. It reads the file on every call: the app
// asks only when an IP lookup service gave no country.
func CountryForIp(datDir string, ip string) string {
	b, err := os.ReadFile(filepath.Join(datDir, "geoip.dat"))
	if err != nil {
		return ""
	}
	list := &geodata.GeoIPList{}
	if err := proto.Unmarshal(b, list); err != nil {
		return ""
	}
	return geoconv.CountryForIP(list, ip)
}
