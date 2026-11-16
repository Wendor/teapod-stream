package tun2socks

import (
	"container/list"
	"net"
	"sync"
	"time"
)

// Protocol type constants
const (
	ProtocolTCP   = 6
	ProtocolUDP   = 17
	ProtocolICMP  = 1   // ICMPv4
	ProtocolICMPv6 = 58 // ICMPv6
)

// ConnectionKey uniquely identifies a network flow.
// For TCP this is the 4-tuple (srcIP, srcPort, dstIP, dstPort, protocol).
// We normalise the key so that the same connection always maps to the same key
// regardless of direction.
type ConnectionKey struct {
	SrcIP   string
	SrcPort uint16
	DstIP   string
	DstPort uint16
	Proto   uint8 // 6 = TCP, 17 = UDP
}

// NewConnectionKey builds a connection key from the originating direction of a flow.
// In tun2socks, the netstack forwarder is always called for application-initiated
// connections (src = local app, dst = remote server), so no symmetric normalization
// is needed or correct here.
func NewConnectionKey(srcIP net.IP, srcPort uint16, dstIP net.IP, dstPort uint16, proto uint8) ConnectionKey {
	return ConnectionKey{
		SrcIP:   srcIP.String(),
		SrcPort: srcPort,
		DstIP:   dstIP.String(),
		DstPort: dstPort,
		Proto:   proto,
	}
}

// String returns a human-readable representation of the key.
func (k ConnectionKey) String() string {
	var protoStr string
	switch k.Proto {
	case ProtocolTCP:
		protoStr = "tcp"
	case ProtocolUDP:
		protoStr = "udp"
	default:
		protoStr = "unknown"
	}
	return protoStr + "://" + k.SrcIP + ":" + itoa(k.SrcPort) + "-" + k.DstIP + ":" + itoa(k.DstPort)
}

// itoa is a minimal integer-to-string converter (avoids strconv import).
func itoa(n uint16) string {
	if n == 0 {
		return "0"
	}
	var buf [6]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	return string(buf[i:])
}

// ValidationResult holds the outcome of a UID validation check.
type ValidationResult struct {
	Allowed bool
	UID     int
	Expired time.Time
}

// LRUCache implements a thread-safe LRU cache with TTL-based expiration.
type LRUCache struct {
	mu       sync.Mutex
	capacity int
	ttl      time.Duration
	cache    map[ConnectionKey]*list.Element
	list     *list.List // list.Element.Value is *cacheEntry
}

type cacheEntry struct {
	key    ConnectionKey
	result ValidationResult
}

// NewLRUCache creates a new LRU cache with the given capacity and TTL.
func NewLRUCache(capacity int, ttl time.Duration) *LRUCache {
	return &LRUCache{
		capacity: capacity,
		ttl:      ttl,
		cache:    make(map[ConnectionKey]*list.Element),
		list:     list.New(),
	}
}

// Get returns a ValidationResult and whether it was found and is still valid.
func (c *LRUCache) Get(key ConnectionKey) (ValidationResult, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if elem, ok := c.cache[key]; ok {
		entry := elem.Value.(*cacheEntry)
		if time.Now().Before(entry.result.Expired) {
			// Move to front (most recently used)
			c.list.MoveToFront(elem)
			return entry.result, true
		}
		// Expired — remove
		c.removeElement(elem)
	}
	return ValidationResult{}, false
}

// Add inserts or updates a ValidationResult for the given key.
func (c *LRUCache) Add(key ConnectionKey, result ValidationResult) {
	c.mu.Lock()
	defer c.mu.Unlock()

	result.Expired = time.Now().Add(c.ttl)

	if elem, ok := c.cache[key]; ok {
		// Update existing
		entry := elem.Value.(*cacheEntry)
		entry.result = result
		c.list.MoveToFront(elem)
		return
	}

	// Insert new
	entry := &cacheEntry{key: key, result: result}
	elem := c.list.PushFront(entry)
	c.cache[key] = elem

	// Evict if over capacity
	if c.list.Len() > c.capacity {
		oldest := c.list.Back()
		if oldest != nil {
			c.removeElement(oldest)
		}
	}
}

// Remove deletes an entry from the cache.
func (c *LRUCache) Remove(key ConnectionKey) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if elem, ok := c.cache[key]; ok {
		c.removeElement(elem)
	}
}

// removeElement removes a list element from both the map and the list.
// Caller must hold c.mu.
func (c *LRUCache) removeElement(elem *list.Element) {
	entry := elem.Value.(*cacheEntry)
	delete(c.cache, entry.key)
	c.list.Remove(elem)
}

// Len returns the current number of entries in the cache.
func (c *LRUCache) Len() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.list.Len()
}
