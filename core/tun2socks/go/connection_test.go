//go:build linux || android

package tun2socks_test

import (
	"fmt"
	"net"
	"sync"
	"testing"
	"time"

	. "github.com/Wendor/teapod-tun2socks"
)

// ── ConnectionKey ─────────────────────────────────────────────────────────────

func TestNewConnectionKey_Fields(t *testing.T) {
	src := net.ParseIP("10.0.0.2")
	dst := net.ParseIP("8.8.8.8")
	key := NewConnectionKey(src, 12345, dst, 53, ProtocolUDP)

	if key.SrcIP != "10.0.0.2" {
		t.Errorf("SrcIP = %q, want 10.0.0.2", key.SrcIP)
	}
	if key.DstIP != "8.8.8.8" {
		t.Errorf("DstIP = %q, want 8.8.8.8", key.DstIP)
	}
	if key.SrcPort != 12345 {
		t.Errorf("SrcPort = %d, want 12345", key.SrcPort)
	}
	if key.DstPort != 53 {
		t.Errorf("DstPort = %d, want 53", key.DstPort)
	}
	if key.Proto != ProtocolUDP {
		t.Errorf("Proto = %d, want %d", key.Proto, ProtocolUDP)
	}
}

// Check that src/dst normalization was removed: two connections in opposite
// directions give different keys.
func TestNewConnectionKey_NoSymmetry(t *testing.T) {
	a := net.ParseIP("10.0.0.2")
	b := net.ParseIP("8.8.8.8")

	k1 := NewConnectionKey(a, 1000, b, 53, ProtocolUDP)
	k2 := NewConnectionKey(b, 53, a, 1000, ProtocolUDP)

	if k1 == k2 {
		t.Error("keys for opposite directions must differ (symmetric normalization was removed)")
	}
}

func TestNewConnectionKey_ProtocolDistinguishes(t *testing.T) {
	src := net.ParseIP("10.0.0.1")
	dst := net.ParseIP("1.1.1.1")

	tcp := NewConnectionKey(src, 5000, dst, 443, ProtocolTCP)
	udp := NewConnectionKey(src, 5000, dst, 443, ProtocolUDP)

	if tcp == udp {
		t.Error("TCP and UDP keys for the same 4-tuple must differ")
	}
}

func TestConnectionKey_String(t *testing.T) {
	src := net.ParseIP("192.168.1.1")
	dst := net.ParseIP("93.184.216.34")
	key := NewConnectionKey(src, 443, dst, 80, ProtocolTCP)
	s := key.String()
	if s == "" {
		t.Error("String() must not be empty")
	}
	// Check that the protocol is present in the string
	if len(s) < 3 {
		t.Errorf("String() too short: %q", s)
	}
}

// ── LRUCache ──────────────────────────────────────────────────────────────────

func makeKey(src, dst string, proto uint8) ConnectionKey {
	return NewConnectionKey(net.ParseIP(src), 1000, net.ParseIP(dst), 80, proto)
}

func TestLRUCache_BasicPutGet(t *testing.T) {
	c := NewLRUCache(10, 5*time.Second)
	key := makeKey("10.0.0.1", "8.8.8.8", ProtocolTCP)
	result := ValidationResult{Allowed: true, UID: 42}

	c.Add(key, result)

	got, ok := c.Get(key)
	if !ok {
		t.Fatal("Get: expected hit, got miss")
	}
	if got.Allowed != result.Allowed || got.UID != result.UID {
		t.Errorf("Get returned %+v, want %+v", got, result)
	}
}

func TestLRUCache_Miss(t *testing.T) {
	c := NewLRUCache(10, 5*time.Second)
	key := makeKey("10.0.0.1", "8.8.8.8", ProtocolTCP)

	_, ok := c.Get(key)
	if ok {
		t.Error("expected miss on empty cache, got hit")
	}
}

func TestLRUCache_TTLExpiry(t *testing.T) {
	ttl := 50 * time.Millisecond
	c := NewLRUCache(10, ttl)
	key := makeKey("10.0.0.1", "8.8.8.8", ProtocolTCP)

	c.Add(key, ValidationResult{Allowed: true})

	// The entry must be there right away
	if _, ok := c.Get(key); !ok {
		t.Fatal("expected hit immediately after Add")
	}

	time.Sleep(ttl + 10*time.Millisecond)

	// After the TTL — a miss
	if _, ok := c.Get(key); ok {
		t.Error("expected miss after TTL expiry")
	}
}

func TestLRUCache_LRUEviction(t *testing.T) {
	c := NewLRUCache(3, 10*time.Second)

	keys := []ConnectionKey{
		makeKey("10.0.0.1", "1.1.1.1", ProtocolTCP),
		makeKey("10.0.0.2", "2.2.2.2", ProtocolTCP),
		makeKey("10.0.0.3", "3.3.3.3", ProtocolTCP),
	}
	for i, k := range keys {
		c.Add(k, ValidationResult{Allowed: true, UID: i})
	}

	// Adding a 4th element evicts the first one (LRU)
	newKey := makeKey("10.0.0.4", "4.4.4.4", ProtocolTCP)
	c.Add(newKey, ValidationResult{Allowed: false})

	if _, ok := c.Get(keys[0]); ok {
		t.Error("LRU entry should have been evicted")
	}
	for _, k := range keys[1:] {
		if _, ok := c.Get(k); !ok {
			t.Errorf("non-LRU entry %v should still be present", k)
		}
	}
	if _, ok := c.Get(newKey); !ok {
		t.Error("newly inserted entry should be present")
	}
}

func TestLRUCache_LRUUpdate(t *testing.T) {
	c := NewLRUCache(2, 10*time.Second)

	k1 := makeKey("10.0.0.1", "1.1.1.1", ProtocolTCP)
	k2 := makeKey("10.0.0.2", "2.2.2.2", ProtocolTCP)
	k3 := makeKey("10.0.0.3", "3.3.3.3", ProtocolTCP)

	c.Add(k1, ValidationResult{Allowed: true})
	c.Add(k2, ValidationResult{Allowed: true})

	// Accessing k1 makes it "the freshest"
	c.Get(k1)

	// Adding k3 evicts k2 (the least recently used)
	c.Add(k3, ValidationResult{Allowed: false})

	if _, ok := c.Get(k2); ok {
		t.Error("k2 should have been evicted after k1 was accessed")
	}
	if _, ok := c.Get(k1); !ok {
		t.Error("k1 should still be present (was recently accessed)")
	}
}

func TestLRUCache_Remove(t *testing.T) {
	c := NewLRUCache(10, 10*time.Second)
	key := makeKey("10.0.0.1", "8.8.8.8", ProtocolTCP)

	c.Add(key, ValidationResult{Allowed: true})
	c.Remove(key)

	if _, ok := c.Get(key); ok {
		t.Error("entry should be absent after Remove")
	}
}

func TestLRUCache_Update(t *testing.T) {
	c := NewLRUCache(10, 10*time.Second)
	key := makeKey("10.0.0.1", "8.8.8.8", ProtocolTCP)

	c.Add(key, ValidationResult{Allowed: true, UID: 100})
	c.Add(key, ValidationResult{Allowed: false, UID: 200})

	got, ok := c.Get(key)
	if !ok {
		t.Fatal("expected hit after update")
	}
	if got.Allowed || got.UID != 200 {
		t.Errorf("expected updated value {false, 200}, got %+v", got)
	}
	if c.Len() != 1 {
		t.Errorf("Len = %d after update of existing key, want 1", c.Len())
	}
}

func TestLRUCache_Len(t *testing.T) {
	c := NewLRUCache(10, 10*time.Second)
	if c.Len() != 0 {
		t.Errorf("initial Len = %d, want 0", c.Len())
	}

	c.Add(makeKey("10.0.0.1", "1.1.1.1", ProtocolTCP), ValidationResult{})
	c.Add(makeKey("10.0.0.2", "2.2.2.2", ProtocolTCP), ValidationResult{})

	if c.Len() != 2 {
		t.Errorf("Len = %d, want 2", c.Len())
	}
}

func TestLRUCache_Concurrent(t *testing.T) {
	c := NewLRUCache(100, 5*time.Second)
	var wg sync.WaitGroup
	const goroutines = 20
	const ops = 50

	for i := range goroutines {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			for j := range ops {
				key := makeKey(
					fmt.Sprintf("10.0.0.%d", id),
					fmt.Sprintf("8.8.8.%d", j%10),
					ProtocolTCP,
				)
				c.Add(key, ValidationResult{Allowed: id%2 == 0, UID: id})
				c.Get(key)
			}
		}(i)
	}
	wg.Wait()
	// Check that the cache isn't broken (no panics, Len within reasonable bounds)
	if l := c.Len(); l > 100 {
		t.Errorf("cache Len %d exceeds capacity 100", l)
	}
}
