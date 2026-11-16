// Package geoconv converts geoip.dat/geosite.dat codes (xray format) into sing-box
// rule-sets (.srs): sing-box 1.12+ doesn't read the old geo databases.
package geoconv

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/netip"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/sagernet/sing-box/common/srs"
	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/option"
	"github.com/xtls/xray-core/common/geodata"
	"google.golang.org/protobuf/proto"
)

// tagPattern — geo rule-set tags from the config: geoip-<code>, geosite-<code>[@attr].
var tagPattern = regexp.MustCompile(`^(geoip|geosite)-([a-z0-9][a-z0-9!_.\-]*(?:@[a-z0-9!_.\-]+)?)$`)

// Prepare generates .srs for local rule-sets tagged geoip-*/geosite-*
// in cacheDir and rewrites their path. .dat files are looked up in datDir, otherwise via openAsset.
func Prepare(config []byte, datDir, cacheDir string, openAsset func(name string) (io.ReadCloser, error)) ([]byte, error) {
	dec := json.NewDecoder(bytes.NewReader(config))
	dec.UseNumber()
	var root map[string]any
	if err := dec.Decode(&root); err != nil {
		return nil, fmt.Errorf("geoconv: %w", err)
	}
	route, _ := root["route"].(map[string]any)
	sets, _ := route["rule_set"].([]any)
	lists := &datLoader{datDir: datDir, openAsset: openAsset}
	changed := false
	for _, item := range sets {
		set, ok := item.(map[string]any)
		if !ok || set["type"] != C.RuleSetTypeLocal {
			continue
		}
		tag, _ := set["tag"].(string)
		if !strings.HasPrefix(tag, "geoip-") && !strings.HasPrefix(tag, "geosite-") {
			continue
		}
		m := tagPattern.FindStringSubmatch(tag)
		if m == nil {
			return nil, fmt.Errorf("geoconv: invalid rule-set tag %q", tag)
		}
		path, err := ensureRuleSet(m[1], m[2], tag, cacheDir, lists)
		if err != nil {
			return nil, err
		}
		set["path"] = path
		set["format"] = C.RuleSetFormatBinary
		changed = true
	}
	if !changed {
		return config, nil
	}
	return json.Marshal(root)
}

// GeoSiteRules builds a rule-set from a geosite code; "code@attr" — only domains with the attribute.
func GeoSiteRules(list *geodata.GeoSiteList, code string) (option.PlainRuleSet, error) {
	name, attr, _ := strings.Cut(code, "@")
	for _, entry := range list.GetEntry() {
		if !strings.EqualFold(entry.GetCode(), name) {
			continue
		}
		var r option.DefaultHeadlessRule
		for _, d := range entry.GetDomain() {
			if attr != "" && !hasAttribute(d, attr) {
				continue
			}
			switch d.GetType() {
			case geodata.Domain_Substr:
				r.DomainKeyword = append(r.DomainKeyword, d.GetValue())
			case geodata.Domain_Regex:
				r.DomainRegex = append(r.DomainRegex, d.GetValue())
			case geodata.Domain_Domain:
				r.DomainSuffix = append(r.DomainSuffix, d.GetValue())
			case geodata.Domain_Full:
				r.Domain = append(r.Domain, d.GetValue())
			}
		}
		return ruleSet(r), nil
	}
	return option.PlainRuleSet{}, fmt.Errorf("geosite code %q not found", name)
}

// GeoIPRules builds a rule-set from a geoip code.
func GeoIPRules(list *geodata.GeoIPList, code string) (option.PlainRuleSet, error) {
	for _, entry := range list.GetEntry() {
		if !strings.EqualFold(entry.GetCode(), code) {
			continue
		}
		if entry.GetReverseMatch() {
			return option.PlainRuleSet{}, fmt.Errorf("geoip code %q: reverse match is not supported", code)
		}
		var r option.DefaultHeadlessRule
		for _, c := range entry.GetCidr() {
			addr, ok := netip.AddrFromSlice(c.GetIp())
			if !ok {
				return option.PlainRuleSet{}, fmt.Errorf("geoip code %q: invalid ip %v", code, c.GetIp())
			}
			r.IPCIDR = append(r.IPCIDR, netip.PrefixFrom(addr, int(c.GetPrefix())).Masked().String())
		}
		return ruleSet(r), nil
	}
	return option.PlainRuleSet{}, fmt.Errorf("geoip code %q not found", code)
}

func hasAttribute(d *geodata.Domain, attr string) bool {
	for _, a := range d.GetAttribute() {
		if strings.EqualFold(a.GetKey(), attr) {
			return true
		}
	}
	return false
}

// ruleSet — an empty set (no domains after filtering) matches nothing.
func ruleSet(r option.DefaultHeadlessRule) option.PlainRuleSet {
	if len(r.Domain)+len(r.DomainSuffix)+len(r.DomainKeyword)+len(r.DomainRegex)+len(r.IPCIDR) == 0 {
		return option.PlainRuleSet{}
	}
	return option.PlainRuleSet{Rules: []option.HeadlessRule{{Type: C.RuleTypeDefault, DefaultOptions: r}}}
}

// ensureRuleSet returns the path to an up-to-date .srs. Next to it lies <tag>.srs.src
// with the size and mtime of the source .dat; on mismatch the .srs is rebuilt.
func ensureRuleSet(kind, code, tag, cacheDir string, lists *datLoader) (string, error) {
	out := filepath.Join(cacheDir, tag+".srs")
	stamp := lists.stamp(kind)
	if stamp != "" {
		if prev, err := os.ReadFile(out + ".src"); err == nil && string(prev) == stamp {
			if _, err := os.Stat(out); err == nil {
				return out, nil
			}
		}
	}
	var rules option.PlainRuleSet
	var err error
	if kind == "geosite" {
		var list *geodata.GeoSiteList
		if list, err = lists.sites(); err == nil {
			rules, err = GeoSiteRules(list, code)
		}
	} else {
		var list *geodata.GeoIPList
		if list, err = lists.ips(); err == nil {
			rules, err = GeoIPRules(list, code)
		}
	}
	if err != nil {
		return "", err
	}
	if err := writeAtomic(out, func(w io.Writer) error {
		return srs.Write(w, rules, C.RuleSetVersionCurrent)
	}); err != nil {
		return "", fmt.Errorf("geoconv: write %s: %w", tag, err)
	}
	if stamp == "" {
		_ = os.Remove(out + ".src")
	} else if err := os.WriteFile(out+".src", []byte(stamp), 0o644); err != nil {
		return "", fmt.Errorf("geoconv: %w", err)
	}
	return out, nil
}

func writeAtomic(path string, write func(io.Writer) error) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".srs-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if err := write(tmp); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), path)
}

// datLoader reads a .dat at most once per Prepare call.
type datLoader struct {
	datDir    string
	openAsset func(name string) (io.ReadCloser, error)
	siteList  *geodata.GeoSiteList
	ipList    *geodata.GeoIPList
}

// stamp — size and mtime of the .dat on disk; "" — no file on disk (the cache isn't used).
func (l *datLoader) stamp(kind string) string {
	fi, err := os.Stat(filepath.Join(l.datDir, kind+".dat"))
	if err != nil {
		return ""
	}
	return fmt.Sprintf("%d:%d", fi.Size(), fi.ModTime().UnixNano())
}

func (l *datLoader) read(name string) ([]byte, error) {
	b, err := os.ReadFile(filepath.Join(l.datDir, name))
	if err == nil || !errors.Is(err, os.ErrNotExist) || l.openAsset == nil {
		return b, err
	}
	r, err := l.openAsset(name)
	if err != nil {
		return nil, err
	}
	defer r.Close()
	return io.ReadAll(r)
}

func (l *datLoader) sites() (*geodata.GeoSiteList, error) {
	if l.siteList == nil {
		b, err := l.read("geosite.dat")
		if err != nil {
			return nil, fmt.Errorf("geoconv: %w", err)
		}
		list := &geodata.GeoSiteList{}
		if err := proto.Unmarshal(b, list); err != nil {
			return nil, fmt.Errorf("geoconv: geosite.dat: %w", err)
		}
		l.siteList = list
	}
	return l.siteList, nil
}

func (l *datLoader) ips() (*geodata.GeoIPList, error) {
	if l.ipList == nil {
		b, err := l.read("geoip.dat")
		if err != nil {
			return nil, fmt.Errorf("geoconv: %w", err)
		}
		list := &geodata.GeoIPList{}
		if err := proto.Unmarshal(b, list); err != nil {
			return nil, fmt.Errorf("geoconv: geoip.dat: %w", err)
		}
		l.ipList = list
	}
	return l.ipList, nil
}
