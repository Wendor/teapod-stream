package teapodcore

import (
	"context"
	"errors"
	"fmt"
	"net"
	"sync/atomic"
	"testing"
	"time"
)

// The outbound probe ends at its deadline even when the server never answers: one deadline
// covers both attempts, not 12 s per attempt.
func TestMeasureOutboundDelayEndsAtItsDeadline(t *testing.T) {
	silent, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer silent.Close()
	var accepted atomic.Int32
	var held []net.Conn
	go func() {
		for {
			conn, err := silent.Accept()
			if err != nil {
				return
			}
			accepted.Add(1)
			held = append(held, conn) // accepted, never answered
		}
	}()

	saved := probeTimeout
	probeTimeout = 300 * time.Millisecond
	defer func() { probeTimeout = saved }()

	started := time.Now()
	ms, err := MeasureOutboundDelay(`{"outbounds": [{"protocol": "freedom"}]}`,
		fmt.Sprintf("http://%s/generate_204", silent.Addr()))
	if err == nil {
		t.Fatalf("probe of a silent server succeeded: %d ms", ms)
	}
	if elapsed := time.Since(started); elapsed > 3*time.Second {
		t.Fatalf("probe took %v, deadline %v", elapsed, probeTimeout)
	}
	// It got as far as the server and ended because of the deadline, not an early failure.
	if accepted.Load() == 0 {
		t.Fatal("the probe never reached the server")
	}
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("error %v, want the deadline", err)
	}
}
