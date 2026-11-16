//go:build with_gvisor

package teapodcore

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json"
)

// sing-box without a TUN inbound (behind tun2socks) must start with our platform interface.
func TestBoxStartsWithoutTunInbound(t *testing.T) {
	ctx := newBoxContext(context.Background(), t.TempDir())
	config := `{"log":{"disabled":true},
		"dns":{"servers":[{"type":"local","tag":"dns-local"}],"final":"dns-local"},
		"inbounds":[{"type":"mixed","tag":"socks-in","listen":"127.0.0.1","listen_port":0}],
		"outbounds":[{"type":"direct","tag":"direct"}],
		"route":{"final":"direct","default_domain_resolver":"dns-local"}}`
	opts, err := json.UnmarshalExtendedContext[option.Options](ctx, []byte(config))
	if err != nil {
		t.Fatal(err)
	}
	instance, err := box.New(box.Options{Context: ctx, Options: opts})
	if err != nil {
		t.Fatal(err)
	}
	defer instance.Close()
	if err := instance.Start(); err != nil {
		t.Fatalf("start: %v", err)
	}
}

type discardLogs struct{}

func (discardLogs) WriteMessage(log.Level, string) {}

// With PlatformLogWriter sing-box always opens cache.db; on Android the process cwd is "/"
// (read-only), so relative paths must resolve into dataDir.
func TestBoxCacheFileLivesInDataDir(t *testing.T) {
	dataDir := t.TempDir()
	readOnly := t.TempDir()
	if err := os.Chmod(readOnly, 0o500); err != nil {
		t.Fatal(err)
	}
	t.Chdir(readOnly)
	ctx := newBoxContext(context.Background(), dataDir)
	config := `{"inbounds":[{"type":"mixed","tag":"socks-in","listen":"127.0.0.1","listen_port":0}],
		"outbounds":[{"type":"direct","tag":"direct"}],"route":{"final":"direct"}}`
	opts, err := json.UnmarshalExtendedContext[option.Options](ctx, []byte(config))
	if err != nil {
		t.Fatal(err)
	}
	instance, err := box.New(box.Options{Context: ctx, Options: opts, PlatformLogWriter: discardLogs{}})
	if err != nil {
		t.Fatal(err)
	}
	defer instance.Close()
	if err := instance.Start(); err != nil {
		t.Fatalf("start: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dataDir, "cache.db")); err != nil {
		t.Fatalf("cache.db not in dataDir: %v", err)
	}
}
