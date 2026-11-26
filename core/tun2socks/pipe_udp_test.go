package tun2socks

import (
	"net"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

// udpFlow wires pipeUDP between an app socket and a fake SOCKS5 relay on loopback.
type udpFlow struct {
	app   *net.UDPConn // the app's side of the gVisor connection
	relay *net.UDPConn // the core's UDP relay
	local *net.UDPAddr // tun2socks' socket the relay sends to
	done  chan struct{}
	rx    atomic.Int64 // the engine's liveness stamp
}

func startUDPFlow(t *testing.T) *udpFlow { return startUDPFlowTo(t, 5004) }

func startUDPFlowTo(t *testing.T, dstPort int) *udpFlow {
	t.Helper()
	listen := func() *net.UDPConn {
		c, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { c.Close() })
		return c
	}
	app, relay, assocConn := listen(), listen(), listen()
	gvisorSide, err := net.DialUDP("udp", nil, app.LocalAddr().(*net.UDPAddr))
	if err != nil {
		t.Fatal(err)
	}
	ctrl, ctrlPeer := tcpPair(t)
	t.Cleanup(func() { ctrlPeer.Close() })

	assoc := &UDPAssociation{RelayAddr: relay.LocalAddr().(*net.UDPAddr), UDPConn: assocConn, ctrl: ctrl}
	f := &udpFlow{app: app, relay: relay, local: assocConn.LocalAddr().(*net.UDPAddr), done: make(chan struct{})}
	go func() {
		pipeUDP(gvisorSide, assoc, net.IPv4(192, 0, 2, 1), dstPort, 1500, &f.rx)
		close(f.done)
	}()
	// Join pipeUDP before the earlier cleanups (the idle timeout restore among them) run:
	// a reader still alive after a failed test would race with them.
	t.Cleanup(func() {
		gvisorSide.Close()
		assocConn.Close()
		ctrl.Close()
		<-f.done
	})
	return f
}

func setUDPIdleTimeout(t *testing.T, d time.Duration) {
	old := udpIdleTimeout
	udpIdleTimeout = d
	t.Cleanup(func() { udpIdleTimeout = old })
}

// A flow that only receives (one subscribe, then a stream) must not be closed by the
// silence of the app → relay direction.
func TestPipeUDPKeepsDownlinkOnlyFlow(t *testing.T) {
	setUDPIdleTimeout(t, 300*time.Millisecond)
	f := startUDPFlow(t)

	datagram := EncodeUDPDatagram(net.IPv4(192, 0, 2, 1), 5004, []byte("frame"))
	const frames = 12
	go func() {
		for i := 0; i < frames; i++ {
			f.relay.WriteToUDP(datagram, f.local)
			time.Sleep(100 * time.Millisecond)
		}
	}()

	buf := make([]byte, 64)
	got := 0
	f.app.SetReadDeadline(time.Now().Add(3 * time.Second))
	for got < frames {
		if _, err := f.app.Read(buf); err != nil {
			t.Fatalf("app got %d of %d frames: the flow closed while receiving (%v)", got, frames, err)
		}
		got++
	}

	select {
	case <-f.done:
	case <-time.After(2 * time.Second):
		t.Fatal("pipeUDP did not end once both directions were idle")
	}
}

// Datagrams that are dropped (here: from a foreign source) don't keep the flow alive.
func TestPipeUDPDroppedDatagramsDontExtendFlow(t *testing.T) {
	setUDPIdleTimeout(t, 300*time.Millisecond)
	f := startUDPFlow(t)

	spammer, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	defer spammer.Close()
	stop := make(chan struct{})
	defer close(stop)
	go func() {
		datagram := EncodeUDPDatagram(net.IPv4(192, 0, 2, 1), 5004, []byte("spoof"))
		for {
			select {
			case <-stop:
				return
			case <-time.After(50 * time.Millisecond):
				spammer.WriteToUDP(datagram, f.local)
			}
		}
	}()

	select {
	case <-f.done:
	case <-time.After(2 * time.Second):
		t.Fatal("spoofed datagrams kept an idle flow alive")
	}
}

// The idle deadline must carry the monotonic clock: a deadline from wall time alone moves
// with every clock change, and a step back would keep an idle flow alive.
func TestUDPActivityDeadlineIsMonotonic(t *testing.T) {
	act := newUDPActivity()
	act.touch()
	d := act.deadline()
	if !strings.Contains(d.String(), "m=") {
		t.Fatalf("deadline %v has no monotonic reading", d)
	}
	if left := time.Until(d); left <= 0 || left > udpIdleTimeout {
		t.Fatalf("deadline in %v; want within (0, %v]", left, udpIdleTimeout)
	}
}

// Activity only moves forward: a reader storing an older time after a newer one must not
// pull the deadline back.
func TestUDPActivityNeverMovesBack(t *testing.T) {
	act := newUDPActivity()
	act.advance(11 * time.Second)
	act.advance(10 * time.Second)
	if got := time.Duration(act.last.Load()); got != 11*time.Second {
		t.Fatalf("activity at %v after a late older touch; want 11s", got)
	}
}

// The engine's liveness stamp moves with a reply delivered to the app.
func TestPipeUDPStampsEngineRxOnReply(t *testing.T) {
	f := startUDPFlow(t)
	if got := f.rx.Load(); got != 0 {
		t.Fatalf("engine rx stamped before any reply: %d", got)
	}
	f.relay.WriteToUDP(EncodeUDPDatagram(net.IPv4(192, 0, 2, 1), 5004, []byte("answer")), f.local)
	buf := make([]byte, 64)
	f.app.SetReadDeadline(time.Now().Add(3 * time.Second))
	if _, err := f.app.Read(buf); err != nil {
		t.Fatalf("app got no reply: %v", err)
	}
	// pipeUDP stamps right after its write to the app: the read here can return first.
	deadline := time.Now().Add(2 * time.Second)
	for f.rx.Load() == 0 && time.Now().Before(deadline) {
		time.Sleep(5 * time.Millisecond)
	}
	if f.rx.Load() == 0 {
		t.Fatal("engine rx not stamped by the reply")
	}
}

// A DNS answer doesn't stamp liveness: the core may answer it from its cache with the server dead.
func TestPipeUDPDNSAnswerDoesntStampEngineRx(t *testing.T) {
	f := startUDPFlowTo(t, 53)
	f.relay.WriteToUDP(EncodeUDPDatagram(net.IPv4(192, 0, 2, 1), 53, []byte("answer")), f.local)
	buf := make([]byte, 64)
	f.app.SetReadDeadline(time.Now().Add(3 * time.Second))
	if _, err := f.app.Read(buf); err != nil {
		t.Fatalf("app got no reply: %v", err)
	}
	time.Sleep(50 * time.Millisecond)
	if got := f.rx.Load(); got != 0 {
		t.Fatalf("engine rx stamped by a DNS answer: %d", got)
	}
}
