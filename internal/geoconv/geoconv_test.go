package geoconv

import (
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/sagernet/sing-box/common/srs"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/domain"
	"github.com/xtls/xray-core/common/geodata"
	"google.golang.org/protobuf/proto"
)

func site(code string, domains ...*geodata.Domain) *geodata.GeoSite {
	return &geodata.GeoSite{Code: code, Domain: domains}
}

func dom(t geodata.Domain_Type, v string, attrs ...string) *geodata.Domain {
	d := &geodata.Domain{Type: t, Value: v}
	for _, a := range attrs {
		d.Attribute = append(d.Attribute, &geodata.Domain_Attribute{Key: a})
	}
	return d
}

func writeDat(t *testing.T, path string, m proto.Message) {
	t.Helper()
	b, err := proto.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, b, 0o644); err != nil {
		t.Fatal(err)
	}
}

func testSites() *geodata.GeoSiteList {
	return &geodata.GeoSiteList{Entry: []*geodata.GeoSite{
		site("TEST",
			dom(geodata.Domain_Substr, "kw"),
			dom(geodata.Domain_Regex, "^a.*$"),
			dom(geodata.Domain_Domain, "example.com", "ads"),
			dom(geodata.Domain_Full, "full.example.org"),
		),
	}}
}

func rule(t *testing.T, rs option.PlainRuleSet) option.DefaultHeadlessRule {
	t.Helper()
	if len(rs.Rules) != 1 {
		t.Fatalf("rules = %d, want 1", len(rs.Rules))
	}
	return rs.Rules[0].DefaultOptions
}

func TestGeoSiteRulesMapsDomainTypes(t *testing.T) {
	rs, err := GeoSiteRules(testSites(), "test")
	if err != nil {
		t.Fatal(err)
	}
	r := rule(t, rs)
	if !slices.Equal(r.DomainKeyword, []string{"kw"}) || !slices.Equal(r.DomainRegex, []string{"^a.*$"}) ||
		!slices.Equal(r.DomainSuffix, []string{"example.com"}) || !slices.Equal(r.Domain, []string{"full.example.org"}) {
		t.Fatalf("unexpected rule: %+v", r)
	}
}

func TestGeoSiteSuffixMatchesApexAndSubdomain(t *testing.T) {
	rs, err := GeoSiteRules(testSites(), "test")
	if err != nil {
		t.Fatal(err)
	}
	m := domain.NewMatcher(nil, rule(t, rs).DomainSuffix, false)
	if !m.Match("example.com") || !m.Match("a.example.com") || m.Match("badexample.com") {
		t.Fatal("domain_suffix must match apex and subdomains only")
	}
}

func TestGeoSiteAttributeFilter(t *testing.T) {
	rs, err := GeoSiteRules(testSites(), "test@ads")
	if err != nil {
		t.Fatal(err)
	}
	r := rule(t, rs)
	if !slices.Equal(r.DomainSuffix, []string{"example.com"}) || len(r.Domain)+len(r.DomainKeyword)+len(r.DomainRegex) != 0 {
		t.Fatalf("unexpected rule: %+v", r)
	}
}

func TestGeoIPRulesCIDR(t *testing.T) {
	list := &geodata.GeoIPList{Entry: []*geodata.GeoIP{{Code: "XX", Cidr: []*geodata.CIDR{
		{Ip: []byte{10, 0, 0, 0}, Prefix: 8},
		{Ip: []byte{0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, Prefix: 32},
	}}}}
	rs, err := GeoIPRules(list, "xx")
	if err != nil {
		t.Fatal(err)
	}
	if got := rule(t, rs).IPCIDR; !slices.Equal(got, []string{"10.0.0.0/8", "2001:db8::/32"}) {
		t.Fatalf("ip_cidr = %v", got)
	}
}

func prepareConfig(tags ...string) []byte {
	var sets []map[string]any
	for _, tag := range tags {
		sets = append(sets, map[string]any{"type": "local", "tag": tag, "format": "binary", "path": tag + ".srs"})
	}
	b, _ := json.Marshal(map[string]any{"route": map[string]any{"rule_set": sets}})
	return b
}

func ruleSetPaths(t *testing.T, config []byte) map[string]string {
	t.Helper()
	var root struct {
		Route struct {
			RuleSet []struct{ Tag, Path string } `json:"rule_set"`
		} `json:"route"`
	}
	if err := json.Unmarshal(config, &root); err != nil {
		t.Fatal(err)
	}
	paths := map[string]string{}
	for _, s := range root.Route.RuleSet {
		paths[s.Tag] = s.Path
	}
	return paths
}

func readSrs(t *testing.T, path string) option.PlainRuleSet {
	t.Helper()
	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	compat, err := srs.Read(f, false)
	if err != nil {
		t.Fatal(err)
	}
	rs, err := compat.Upgrade()
	if err != nil {
		t.Fatal(err)
	}
	return rs
}

func TestPrepareRewritesPathsAndWritesSrs(t *testing.T) {
	dat, cache := t.TempDir(), t.TempDir()
	writeDat(t, filepath.Join(dat, "geosite.dat"), testSites())

	out, err := Prepare(prepareConfig("geosite-test"), dat, cache, nil)
	if err != nil {
		t.Fatal(err)
	}
	want := filepath.Join(cache, "geosite-test.srs")
	if p := ruleSetPaths(t, out)["geosite-test"]; p != want {
		t.Fatalf("path = %q, want %q", p, want)
	}
	// In .srs domain/domain_suffix are stored as a DomainMatcher.
	if r := rule(t, readSrs(t, want)); r.DomainMatcher == nil || !r.DomainMatcher.Match("a.example.com") ||
		!r.DomainMatcher.Match("full.example.org") {
		t.Fatalf("srs rule = %+v", r)
	}
}

func TestPrepareRegeneratesWhenDatChanges(t *testing.T) {
	dat, cache := t.TempDir(), t.TempDir()
	datPath := filepath.Join(dat, "geosite.dat")
	writeDat(t, datPath, testSites())
	if _, err := Prepare(prepareConfig("geosite-test"), dat, cache, nil); err != nil {
		t.Fatal(err)
	}

	writeDat(t, datPath, &geodata.GeoSiteList{Entry: []*geodata.GeoSite{
		site("test", dom(geodata.Domain_Domain, "updated.example.net")),
	}})
	future := time.Now().Add(time.Minute)
	if err := os.Chtimes(datPath, future, future); err != nil {
		t.Fatal(err)
	}
	if _, err := Prepare(prepareConfig("geosite-test"), dat, cache, nil); err != nil {
		t.Fatal(err)
	}
	r := rule(t, readSrs(t, filepath.Join(cache, "geosite-test.srs")))
	if r.DomainMatcher == nil || !r.DomainMatcher.Match("updated.example.net") || r.DomainMatcher.Match("example.com") {
		t.Fatalf("stale srs: %+v", r)
	}
}

func TestPrepareUnknownCode(t *testing.T) {
	dat := t.TempDir()
	writeDat(t, filepath.Join(dat, "geosite.dat"), testSites())
	_, err := Prepare(prepareConfig("geosite-nope"), dat, t.TempDir(), nil)
	if err == nil || !strings.Contains(err.Error(), `geosite code "nope" not found`) {
		t.Fatalf("err = %v", err)
	}
}

func TestPrepareIgnoresForeignRuleSets(t *testing.T) {
	config := []byte(`{"route":{"rule_set":[{"type":"remote","tag":"geosite-x","url":"https://e/x.srs"},{"type":"local","tag":"custom","path":"/data/custom.srs"}]}}`)
	out, err := Prepare(config, t.TempDir(), t.TempDir(), nil)
	if err != nil {
		t.Fatal(err)
	}
	paths := ruleSetPaths(t, out)
	if paths["custom"] != "/data/custom.srs" || paths["geosite-x"] != "" {
		t.Fatalf("foreign rule sets changed: %v", paths)
	}
}

func TestPrepareRejectsPathEscape(t *testing.T) {
	dat := t.TempDir()
	writeDat(t, filepath.Join(dat, "geosite.dat"), &geodata.GeoSiteList{Entry: []*geodata.GeoSite{
		site("geolocation-!cn", dom(geodata.Domain_Domain, "a.com")),
		site("category-ads-all", dom(geodata.Domain_Domain, "ads.com", "ads")),
	}})
	if _, err := Prepare(prepareConfig("geosite-../evil"), dat, t.TempDir(), nil); err == nil {
		t.Fatal("tag with path separator must be rejected")
	}
	cache := t.TempDir()
	out, err := Prepare(prepareConfig("geosite-geolocation-!cn", "geosite-category-ads-all@ads"), dat, cache, nil)
	if err != nil {
		t.Fatal(err)
	}
	for tag, p := range ruleSetPaths(t, out) {
		if filepath.Dir(p) != cache {
			t.Fatalf("%s written outside cache: %s", tag, p)
		}
		if _, err := os.Stat(p); err != nil {
			t.Fatal(err)
		}
	}
}
