package teapodcore

import (
	"log"

	core "github.com/xtls/xray-core/core"
)

// startXrayInstance starts inst and closes it when a feature fails to start: xray starts
// features in order and doesn't roll back, so the ones already started (inbound listeners
// on the SOCKS port) would stay up with no reference left to close them.
func startXrayInstance(inst *core.Instance) error {
	err := inst.Start()
	if err == nil {
		return nil
	}
	if closeErr := inst.Close(); closeErr != nil {
		log.Printf("[xray] cleanup after failed start: %v", closeErr)
	}
	return err
}
