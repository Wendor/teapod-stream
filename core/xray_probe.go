package teapodcore

import (
	"context"
	"fmt"
	"net"
	"strings"

	corenet "github.com/xtls/xray-core/common/net"
	"github.com/xtls/xray-core/common/serial"
	core "github.com/xtls/xray-core/core"
	coreserial "github.com/xtls/xray-core/infra/conf/serial"
)

// MeasureOutboundDelay starts a temporary xray instance with the given config
// to measure latency without affecting the running session.
func MeasureOutboundDelay(config string, url string) (int64, error) {
	cfg, err := coreserial.LoadJSONConfig(strings.NewReader(config))
	if err != nil {
		return -1, fmt.Errorf("config load error: %w", err)
	}

	cfg.Inbound = nil
	var essential []*serial.TypedMessage
	for _, app := range cfg.App {
		switch app.Type {
		// No xray.app.log.Config: log.New registers the instance as the global
		// handler, and after Close the handler is inactive — the running VPN core
		// would stop logging until its next start.
		case "xray.app.proxyman.OutboundConfig",
			"xray.app.dispatcher.Config":
			essential = append(essential, app)
		}
	}
	cfg.App = essential

	inst, err := core.New(cfg)
	if err != nil {
		return -1, fmt.Errorf("instance creation failed: %w", err)
	}
	if err := startXrayInstance(inst); err != nil {
		return -1, fmt.Errorf("startup failed: %w", err)
	}
	defer inst.Close()
	ctx, cancel := context.WithTimeout(context.Background(), probeTimeout)
	defer cancel()
	return measureDelay(ctx, inst, url)
}

// measureDelay measures HTTP round-trip latency through a running core instance.
func measureDelay(ctx context.Context, inst *core.Instance, url string) (int64, error) {
	return measureDelayVia(ctx, func(ctx context.Context, network, addr string) (net.Conn, error) {
		dest, err := corenet.ParseDestination(fmt.Sprintf("%s:%s", network, addr))
		if err != nil {
			return nil, err
		}
		return core.Dial(ctx, inst, dest)
	}, url)
}
