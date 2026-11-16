//go:build android

package teapodcore

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"path/filepath"
	"sync"
	"time"

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

type boxEngine struct {
	mu       sync.Mutex
	instance *box.Box
	cancel   context.CancelFunc
	cb       XrayCallback
}

var (
	boxMu  sync.Mutex
	boxEng *boxEngine
)

func currentBox() *boxEngine {
	boxMu.Lock()
	defer boxMu.Unlock()
	return boxEng
}

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
	StopBox()

	eng := &boxEngine{cb: cb}
	boxMu.Lock()
	boxEng = eng
	boxMu.Unlock()

	go func() {
		eng.mu.Lock()
		defer eng.mu.Unlock()

		// See StartXray: StopBox may have taken eng.mu earlier and not found the instance.
		if currentBox() != eng {
			if cb != nil {
				cb.OnStatus(-1, "start cancelled: core was stopped")
			}
			return
		}

		inst, cancel, err := newBox(config, dataDir, true)
		if err == nil {
			if err = inst.Start(); err != nil {
				_ = inst.Close()
				cancel()
				err = fmt.Errorf("startup failed: %w", err)
			}
		}
		if err != nil {
			log.Printf("[sing-box] %v", err)
			if cb != nil {
				cb.OnStatus(-1, err.Error())
			}
			return
		}

		eng.instance = inst
		eng.cancel = cancel
		if cb != nil {
			cb.OnStatus(0, "Started successfully, running")
		}
	}()
}

// StopBox stops sing-box and releases all resources.
func StopBox() {
	boxMu.Lock()
	eng := boxEng
	boxEng = nil
	boxMu.Unlock()
	if eng == nil {
		return
	}

	eng.mu.Lock()
	defer eng.mu.Unlock()

	if eng.instance != nil {
		if err := eng.instance.Close(); err != nil {
			log.Printf("[sing-box] shutdown error: %v", err)
		}
		eng.instance = nil
	}
	if eng.cancel != nil {
		eng.cancel()
		eng.cancel = nil
	}
	if eng.cb != nil {
		eng.cb.OnStatus(0, "Core stopped")
	}
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
	eng := currentBox()
	if eng == nil {
		return -1, errors.New("sing-box not running")
	}
	eng.mu.Lock()
	inst := eng.instance
	eng.mu.Unlock()
	if inst == nil {
		return -1, errors.New("sing-box instance not ready")
	}
	dial, err := boxProxyDial(inst)
	if err != nil {
		return -1, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
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
	ctx, cancelProbe := context.WithTimeout(context.Background(), 12*time.Second)
	defer cancelProbe()
	return measureDelayVia(ctx, dial, url)
}
