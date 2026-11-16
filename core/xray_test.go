package teapodcore

import (
	"errors"
	"fmt"
	"net"
	"strings"
	"syscall"
	"testing"

	core "github.com/xtls/xray-core/core"
	coreserial "github.com/xtls/xray-core/infra/conf/serial"
	_ "github.com/xtls/xray-core/main/distro/all"
)

// startOnBusyPort starts an instance whose tagged inbound takes a free port and whose
// untagged one hits a busy port. It returns the free port after the failed start, and
// whether the start failed on the busy port (false: another process took the probed one).
// Tagged inbounds start before untagged ones, so the free port is bound first.
func startOnBusyPort(t *testing.T, busyPort int) (int, bool) {
	t.Helper()
	probe, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	free := probe.Addr().(*net.TCPAddr).Port
	probe.Close()

	config := fmt.Sprintf(`{
		"inbounds": [
			{"tag": "first", "listen": "127.0.0.1", "port": %d, "protocol": "socks"},
			{"listen": "127.0.0.1", "port": %d, "protocol": "socks"}
		],
		"outbounds": [{"protocol": "freedom"}]
	}`, free, busyPort)
	cfg, err := coreserial.LoadJSONConfig(strings.NewReader(config))
	if err != nil {
		t.Fatal(err)
	}
	inst, err := core.New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	err = startXrayInstance(inst)
	if err == nil {
		inst.Close()
		t.Fatal("start succeeded on a busy port")
	}
	return free, strings.Contains(err.Error(), fmt.Sprintf("127.0.0.1:%d", busyPort))
}

// A failed start must close the instance: the features that started before the
// failing one (here the tagged inbound) would otherwise keep their listeners.
func TestStartXrayInstanceReleasesListenersWhenStartFails(t *testing.T) {
	busy, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer busy.Close()

	// Another process may take the probed port before the start or before the check, so
	// either case gets a few attempts with fresh ports; a real leak fails them all.
	const attempts = 3
	for i := 0; i < attempts; i++ {
		free, onBusyPort := startOnBusyPort(t, busy.Addr().(*net.TCPAddr).Port)
		if !onBusyPort {
			continue // the probed port was taken: the inbound under test never listened
		}
		ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", free))
		if err == nil {
			ln.Close()
			return
		}
		if !errors.Is(err, syscall.EADDRINUSE) {
			t.Fatal(err)
		}
	}
	t.Fatalf("no attempt out of %d showed the started inbound releasing its port", attempts)
}
