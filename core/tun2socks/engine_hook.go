package tun2socks

import (
	"log"
	"net"
	"sync"
	"sync/atomic"
	"time"
)

// UIDValidatorFunc is the Kotlin callback invoked for each new connection.
//
// gomobile limitation: interface methods may return at most one primitive value.
// Validate returns true if the connection should be forwarded, false to block it.
// The Kotlin side already knows the UID when it answers, so UID is not returned here.
type UIDValidatorFunc interface {
	// Validate is called for every new TCP/UDP connection.
	// Returns true to allow, false to deny.
	//   srcIP, srcPort — source address
	//   dstIP, dstPort — destination address
	//   protocol       — 6 (TCP) or 17 (UDP)
	Validate(srcIP string, srcPort int, dstIP string, dstPort int, protocol int) bool
}

// EngineHook ties the LRU cache together with the UID validator callback.
//
// The cache key is the full 5-tuple. A src-only UDP cache existed while UDP was
// validated on the packet path; it is gone because every app on the TUN shares
// the source IP, so the key was just a port: an excluded app bound to tun0 could
// reuse a port an allowed app had just used and be admitted (learning the VPN
// exit), and a cached deny blocked the next allowed app that got the port.
// Validation now runs in the per-flow goroutine, so a miss no longer stalls the TUN.
type EngineHook struct {
	cache      *LRUCache
	validator  UIDValidatorFunc
	mu         sync.RWMutex
	logEnabled atomic.Bool
}

// NewEngineHook creates a new hook.
// capacity — max entries in the LRU cache
// ttlSeconds — TTL for cached entries in seconds
func NewEngineHook(capacity int, ttlSeconds int) *EngineHook {
	ttl := time.Duration(ttlSeconds) * time.Second
	h := &EngineHook{
		cache: NewLRUCache(capacity, ttl),
	}
	// Off by default: a line per new flow (every destination) goes to logcat.
	// SetLogEnabled(true) for debugging.
	return h
}

// SetValidator sets the Kotlin callback.
func (h *EngineHook) SetValidator(v UIDValidatorFunc) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.validator = v
}

// Validate checks the cache first; on miss, calls the Kotlin validator.
func (h *EngineHook) Validate(srcIP net.IP, srcPort uint16, dstIP net.IP, dstPort uint16, proto uint8) (bool, int) {
	key := NewConnectionKey(srcIP, srcPort, dstIP, dstPort, proto)

	if result, ok := h.cache.Get(key); ok {
		if h.logEnabled.Load() {
			log.Printf("[teapod-tun2socks] cache HIT %s — allowed=%v", key, result.Allowed)
		}
		return result.Allowed, result.UID
	}

	h.mu.RLock()
	validator := h.validator
	h.mu.RUnlock()

	if validator == nil {
		log.Printf("[teapod-tun2socks] WARNING: no validator set, DENYING %s", key)
		return false, -1
	}

	allowed := validator.Validate(
		srcIP.String(), int(srcPort),
		dstIP.String(), int(dstPort),
		int(proto),
	)

	if h.logEnabled.Load() {
		log.Printf("[teapod-tun2socks] cache MISS %s — allowed=%v (from Kotlin)", key, allowed)
	}

	result := ValidationResult{Allowed: allowed, UID: -1}
	h.cache.Add(key, result)
	return allowed, -1
}

// Invalidate removes a connection from the cache.
func (h *EngineHook) Invalidate(srcIP net.IP, srcPort uint16, dstIP net.IP, dstPort uint16, proto uint8) {
	h.cache.Remove(NewConnectionKey(srcIP, srcPort, dstIP, dstPort, proto))
}

// CacheLen returns the current full-cache size.
func (h *EngineHook) CacheLen() int { return h.cache.Len() }

// SetLogEnabled toggles internal logging.
func (h *EngineHook) SetLogEnabled(enabled bool) { h.logEnabled.Store(enabled) }
