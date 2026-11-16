//go:build with_gvisor

package awg

import (
	"net/netip"
	"runtime"
	"testing"
	"time"

	"github.com/sagernet/sing/common/buf"
)

// A TUN reader blocked in Read before IpcSet must wake up and recompute
// the S4 offset — otherwise the first packet goes out without padding.
func TestStackDeviceReconfiguredWakesRead(t *testing.T) {
	dev, err := newStackDevice(1408, []netip.Prefix{netip.MustParsePrefix("10.66.0.2/32")})
	if err != nil {
		t.Fatal(err)
	}
	defer dev.Close()
	type result struct {
		n   int
		err error
	}
	done := make(chan result, 1)
	go func() {
		n, err := dev.Read([][]byte{make([]byte, 2048)}, []int{0}, 16)
		done <- result{n, err}
	}()
	time.Sleep(50 * time.Millisecond)
	dev.Reconfigured()
	select {
	case r := <-done:
		if r.n != 0 || r.err != nil {
			t.Fatalf("Read = %d, %v; want 0, nil", r.n, r.err)
		}
	case <-time.After(time.Second):
		t.Fatal("Read not woken by Reconfigured")
	}
}

// A wake queued before Read wins over a packet that is also ready: the packet would
// otherwise go out with the S4 offset computed before the reconfiguration.
func TestStackDeviceReadPrefersPendingWake(t *testing.T) {
	dev, err := newStackDevice(1408, []netip.Prefix{netip.MustParsePrefix("10.66.0.2/32")})
	if err != nil {
		t.Fatal(err)
	}
	defer dev.Close()
	bufs, sizes := [][]byte{make([]byte, 2048)}, []int{0}
	for i := 0; i < 64; i++ {
		dev.packetOutbound <- buf.As([]byte{0x45})
		dev.Reconfigured()
		if n, err := dev.Read(bufs, sizes, 16); n != 0 || err != nil {
			t.Fatalf("round %d: Read = %d, %v; want the wake (0, nil) before the packet", i, n, err)
		}
		if n, err := dev.Read(bufs, sizes, 16); n != 1 || err != nil {
			t.Fatalf("round %d: Read = %d, %v; want the packet after the wake", i, n, err)
		}
	}
}

// A failed address registration must not leave the allocated stack running.
func TestNewStackDeviceClosesStackOnBadAddress(t *testing.T) {
	dup := []netip.Prefix{netip.MustParsePrefix("10.66.0.2/32"), netip.MustParsePrefix("10.66.0.2/32")}
	before := runtime.NumGoroutine()
	for i := 0; i < 20; i++ {
		if _, err := newStackDevice(1408, dup); err == nil {
			t.Fatal("a duplicate address must fail")
		}
	}
	deadline := time.Now().Add(2 * time.Second)
	for runtime.NumGoroutine() > before+2 && time.Now().Before(deadline) {
		time.Sleep(20 * time.Millisecond)
	}
	if n := runtime.NumGoroutine(); n > before+2 {
		t.Fatalf("goroutines %d -> %d after 20 failed stacks; the stacks were not closed", before, n)
	}
}
