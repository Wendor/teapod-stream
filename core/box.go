//go:build android

package teapodcore

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"path/filepath"

	box "github.com/sagernet/sing-box"
	C "github.com/sagernet/sing-box/constant"
	boxlog "github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
	mobasset "golang.org/x/mobile/asset"

	"github.com/Wendor/teapod-core/internal/geoconv"
)

// boxProxyTag — tag of the proxy outbound/endpoint in the sing-box config (contract with Dart).
const boxProxyTag = "proxy"

// boxCore is a started sing-box instance and the cancel of its context.
type boxCore struct {
	instance *box.Box
	cancel   context.CancelFunc
}

var boxSlot = &coreSlot[boxCore]{name: "sing-box", close: func(c boxCore) error {
	defer c.cancel()
	return c.instance.Close()
}}

// boxLogWriter passes sing-box logs to LogListener (format — boxLogLine); the core prefix
// is added by Kotlin.
type boxLogWriter struct{}

func (boxLogWriter) WriteMessage(level boxlog.Level, message string) {
	logListenerMu.Lock()
	l := logListener
	logListenerMu.Unlock()
	if l == nil {
		return
	}
	l.OnLog(boxLogLine(level, message))
}

// newBox creates (but doesn't start) a sing-box instance from a JSON config.
func newBox(config string, dataDir string, logs bool) (*box.Box, context.CancelFunc, error) {
	prepared, err := geoconv.Prepare([]byte(config), dataDir, filepath.Join(dataDir, "box-rules"),
		func(name string) (io.ReadCloser, error) { return mobasset.Open(name) })
	if err != nil {
		return nil, nil, err
	}
	ctx, cancel := context.WithCancel(newBoxContext(context.Background(), dataDir))
	opts, err := json.UnmarshalExtendedContext[option.Options](ctx, prepared)
	if err != nil {
		cancel()
		return nil, nil, fmt.Errorf("config error: %w", err)
	}
	// Enables AutoDetectInterfaceControl (socket protect) for any config.
	if opts.Route == nil {
		opts.Route = &option.RouteOptions{}
	}
	opts.Route.AutoDetectInterface = true
	boxOpts := box.Options{Context: ctx, Options: opts}
	if logs {
		boxOpts.PlatformLogWriter = boxLogWriter{}
	}
	inst, err := box.New(boxOpts)
	if err != nil {
		cancel()
		return nil, nil, fmt.Errorf("init failed: %w", err)
	}
	return inst, cancel, nil
}

// StartBox starts sing-box with the provided JSON config. dataDir holds
// geoip.dat/geosite.dat. A running instance is stopped first.
func StartBox(config string, dataDir string, cb XrayCallback) {
	boxSlot.start(cb, func() (boxCore, error) {
		inst, cancel, err := newBox(config, dataDir, true)
		if err != nil {
			return boxCore{}, err
		}
		if err := inst.Start(); err != nil {
			_ = inst.Close()
			cancel()
			return boxCore{}, fmt.Errorf("startup failed: %w", err)
		}
		return boxCore{instance: inst, cancel: cancel}, nil
	})
}

// StopBox stops sing-box and releases all resources.
func StopBox() {
	boxSlot.stop()
}

// GetBoxVersion returns the sing-box version string.
func GetBoxVersion() string {
	return "sing-box v" + C.Version
}

// boxProxyDial — dial through the proxy outbound or endpoint.
func boxProxyDial(inst *box.Box) (func(ctx context.Context, network, addr string) (net.Conn, error), error) {
	var dialer N.Dialer
	if out, ok := inst.Outbound().Outbound(boxProxyTag); ok {
		dialer = out
	} else if ep, ok := inst.Endpoint().Get(boxProxyTag); ok {
		dialer = ep
	} else {
		return nil, errors.New("sing-box: no proxy outbound")
	}
	return func(ctx context.Context, network, addr string) (net.Conn, error) {
		return dialer.DialContext(ctx, network, M.ParseSocksaddr(addr))
	}, nil
}

// MeasureBoxDelay measures latency through the running sing-box instance.
func MeasureBoxDelay(url string) (int64, error) {
	c, ok := boxSlot.get()
	if !ok {
		return -1, errors.New("sing-box not running")
	}
	dial, err := boxProxyDial(c.instance)
	if err != nil {
		return -1, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), probeTimeout)
	defer cancel()
	return measureDelayVia(ctx, dial, url)
}

// MeasureBoxOutboundDelay starts a temporary sing-box instance (config without
// inbounds) to measure latency without affecting the running session.
func MeasureBoxOutboundDelay(config string, dataDir string, url string) (int64, error) {
	inst, cancel, err := newBox(config, dataDir, false)
	if err != nil {
		return -1, err
	}
	defer cancel()
	defer inst.Close()
	if err := inst.Start(); err != nil {
		return -1, fmt.Errorf("startup failed: %w", err)
	}
	dial, err := boxProxyDial(inst)
	if err != nil {
		return -1, err
	}
	ctx, cancelProbe := context.WithTimeout(context.Background(), probeTimeout)
	defer cancelProbe()
	return measureDelayVia(ctx, dial, url)
}
