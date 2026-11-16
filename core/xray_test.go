package teapodcore

import (
	"fmt"
	"net"
	"strings"
	"testing"

	core "github.com/xtls/xray-core/core"
	coreserial "github.com/xtls/xray-core/infra/conf/serial"
	_ "github.com/xtls/xray-core/main/distro/all"
)

// A failed start must close the instance: the features that started before the
// failing one (here the tagged inbound) would otherwise keep their listeners.
func TestStartXrayInstanceReleasesListenersWhenStartFails(t *testing.T) {
	busy, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer busy.Close()
	probe, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	free := probe.Addr().(*net.TCPAddr).Port
	probe.Close()

	// Tagged inbounds start before untagged ones, so the free port is bound first.
	config := fmt.Sprintf(`{
		"inbounds": [
			{"tag": "first", "listen": "127.0.0.1", "port": %d, "protocol": "socks"},
			{"listen": "127.0.0.1", "port": %d, "protocol": "socks"}
		],
		"outbounds": [{"protocol": "freedom"}]
	}`, free, busy.Addr().(*net.TCPAddr).Port)
	cfg, err := coreserial.LoadJSONConfig(strings.NewReader(config))
	if err != nil {
		t.Fatal(err)
	}
	inst, err := core.New(cfg)
	if err != nil {
		t.Fatal(err)
	}

	if err := startXrayInstance(inst); err == nil {
		inst.Close()
		t.Fatal("start succeeded on a busy port")
	}
	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", free))
	if err != nil {
		t.Fatalf("the started inbound still holds its port after the failed start: %v", err)
	}
	ln.Close()
}
