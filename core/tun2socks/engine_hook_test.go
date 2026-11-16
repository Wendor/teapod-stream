package tun2socks

import (
	"net"
	"testing"
)

// denyAfter allows the first call, denies the rest and counts calls.
type denyAfter struct{ calls int }

func (v *denyAfter) Validate(_ string, _ int, _ string, _ int, _ int) bool {
	v.calls++
	return v.calls == 1
}

// A UDP decision must not leak to another flow from the same source port: every
// app on the TUN shares the source IP, so a port-only key let an excluded app
// reuse an allowed app's port (and a cached deny blocked the next allowed app).
func TestValidateUDPDoesNotShareDecisionAcrossDestinations(t *testing.T) {
	v := &denyAfter{}
	h := NewEngineHook(100, 300)
	h.SetValidator(v)
	src := net.ParseIP("10.1.2.3")

	if ok, _ := h.Validate(src, 40000, net.ParseIP("1.1.1.1"), 53, ProtocolUDP); !ok {
		t.Fatal("first flow must be allowed")
	}
	if ok, _ := h.Validate(src, 40000, net.ParseIP("9.9.9.9"), 443, ProtocolUDP); ok {
		t.Fatal("same source port to another destination must be validated, not served from cache")
	}
	if v.calls != 2 {
		t.Fatalf("validator calls = %d, want 2", v.calls)
	}
	// The exact 5-tuple stays cached.
	if ok, _ := h.Validate(src, 40000, net.ParseIP("1.1.1.1"), 53, ProtocolUDP); !ok || v.calls != 2 {
		t.Fatalf("exact tuple must hit the cache (ok=%v calls=%d)", ok, v.calls)
	}
}
