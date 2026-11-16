package tun2socks

import (
	"fmt"
	"log"
	"sync"
)

// TeapodTun2socks is the top-level public API for gomobile binding.
// All methods are safe for concurrent use.
type TeapodTun2socks struct {
	mu     sync.Mutex
	engine *Engine
	hook   *EngineHook
}

// NewTeapodTun2socks creates a new TeapodTun2socks instance.
func NewTeapodTun2socks() *TeapodTun2socks {
	return &TeapodTun2socks{}
}

// Start initializes and starts the teapod-tun2socks engine.
//
// Parameters:
//
//	tunFD           — file descriptor of the TUN interface (from VpnService)
//	mtu             — MTU of the TUN interface; must match VpnService.Builder.setMtu()
//	socksHost        — SOCKS5 proxy hostname or IP
//	socksPort        — SOCKS5 proxy port
//	socksUsername    — SOCKS5 username (empty string = no auth)
//	socksPassword    — SOCKS5 password (empty string = no auth)
//	cacheCapacity    — max entries in the UID validation LRU cache
//	cacheTTLSeconds  — TTL for cached validation results in seconds
//	validator        — Kotlin callback implementing UID validation
//
// Returns an error string (empty on success).
func (t *TeapodTun2socks) Start(tunFD int64, mtu int64, socksHost string, socksPort int64, socksUsername, socksPassword string, allowICMP, blockQuic bool, cacheCapacity int64, cacheTTLSeconds int64, validator UIDValidatorFunc) string {
	t.mu.Lock()
	defer t.mu.Unlock()

	if t.engine != nil {
		return "teapod-tun2socks already started"
	}

	hook := NewEngineHook(int(cacheCapacity), int(cacheTTLSeconds))
	hook.SetValidator(validator)

	engine, err := NewEngine(int(tunFD), int(mtu), socksHost, int(socksPort), socksUsername, socksPassword, allowICMP, blockQuic, hook)
	if err != nil {
		log.Printf("[teapod-tun2socks] Start error: %v", err)
		return fmt.Sprintf("engine creation failed: %v", err)
	}

	t.hook = hook
	t.engine = engine

	go func() {
		if err := engine.Start(); err != nil {
			log.Printf("[teapod-tun2socks] engine Start returned: %v", err)
		}
	}()

	log.Printf("[teapod-tun2socks] started: socks=%s:%d mtu=%d allowICMP=%v blockQuic=%v cache_capacity=%d cache_ttl=%ds",
		socksHost, socksPort, mtu, allowICMP, blockQuic, cacheCapacity, cacheTTLSeconds)
	return ""
}

// Stop gracefully shuts down TeapodTun2socks.
func (t *TeapodTun2socks) Stop() {
	t.mu.Lock()
	engine := t.engine
	t.engine = nil
	t.hook = nil
	t.mu.Unlock()

	if engine == nil {
		return
	}
	engine.Stop()
	log.Printf("[teapod-tun2socks] stopped")
}

// IsRunning returns whether the engine is currently running.
func (t *TeapodTun2socks) IsRunning() bool {
	t.mu.Lock()
	engine := t.engine
	t.mu.Unlock()

	if engine == nil {
		return false
	}
	return engine.IsRunning()
}

// CacheSize returns the current number of entries in the validation cache.
func (t *TeapodTun2socks) CacheSize() int64 {
	t.mu.Lock()
	hook := t.hook
	t.mu.Unlock()

	if hook == nil {
		return 0
	}
	return int64(hook.CacheLen())
}

// SetLogEnabled toggles internal Go logging.
func (t *TeapodTun2socks) SetLogEnabled(enabled bool) {
	t.mu.Lock()
	hook := t.hook
	t.mu.Unlock()

	if hook != nil {
		hook.SetLogEnabled(enabled)
	}
}

// GetActiveConnections returns the number of TCP connections currently being proxied.
// A sustained spike (e.g. > 200) after hours of uptime indicates a connection leak.
func (t *TeapodTun2socks) GetActiveConnections() int64 {
	t.mu.Lock()
	engine := t.engine
	t.mu.Unlock()

	if engine == nil {
		return 0
	}
	return engine.ActiveConns()
}

// GetStatsLine returns a diagnostic string with key tunnel health metrics
// (active conns, gVisor TCP counters, channel queue depth, byte counters, cache size).
// Intended to be logged by the Kotlin caller via its own log() so the line
// ends up in vpn_log.txt and the Flutter UI, not only in Android logcat.
func (t *TeapodTun2socks) GetStatsLine() string {
	t.mu.Lock()
	engine := t.engine
	hook := t.hook
	t.mu.Unlock()

	if engine == nil {
		return ""
	}
	cacheLen := 0
	if hook != nil {
		cacheLen = hook.CacheLen()
	}
	return engine.StatsLine(cacheLen)
}

// GetUploadBytes returns the total amount of bytes read from TUN (upload to internet).
func (t *TeapodTun2socks) GetUploadBytes() int64 {
	t.mu.Lock()
	engine := t.engine
	t.mu.Unlock()

	if engine == nil {
		return 0
	}
	return int64(engine.txBytes.Load())
}

// GetDownloadBytes returns the total amount of bytes written to TUN (download from internet).
func (t *TeapodTun2socks) GetDownloadBytes() int64 {
	t.mu.Lock()
	engine := t.engine
	t.mu.Unlock()

	if engine == nil {
		return 0
	}
	return int64(engine.rxBytes.Load())
}

// GetLastRxActivityMs returns the Unix timestamp (milliseconds) of the last successful
// write to the TUN interface. Returns 0 if nothing has been written yet.
// Use this to detect tun2socks hangs: if the heartbeat SOCKS5 probe succeeds but
// this value hasn't changed for several minutes with active connections, tun2socks
// goroutines are receiving data from the proxy but it's not reaching the TUN.
func (t *TeapodTun2socks) GetLastRxActivityMs() int64 {
	t.mu.Lock()
	engine := t.engine
	t.mu.Unlock()

	if engine == nil {
		return 0
	}
	return engine.LastRxMs()
}

// GetDiagnostics returns a JSON snapshot of the tunnel state (health metrics,
// failure counters, per-connection activity table). Empty string if not running.
func (t *TeapodTun2socks) GetDiagnostics() string {
	t.mu.Lock()
	engine := t.engine
	hook := t.hook
	t.mu.Unlock()

	if engine == nil {
		return ""
	}
	cacheLen := 0
	if hook != nil {
		cacheLen = hook.CacheLen()
	}
	return engine.Diagnostics(cacheLen)
}

// ForceCloseAllConnections closes the gVisor side of every active proxied TCP
// connection. Each connection's goroutine pair exits and the app receives a reset,
// causing it to reconnect through a clean path. Call this on network-change events
// to prevent stale gVisor connections from surviving across physical network switches.
// Returns the number of connections that were closed. No-op if not running.
func (t *TeapodTun2socks) ForceCloseAllConnections() int64 {
	t.mu.Lock()
	engine := t.engine
	t.mu.Unlock()

	if engine == nil {
		return 0
	}
	return int64(engine.CloseAllConnections())
}
