package tun2socks

import (
	"encoding/binary"
	"io"
	"net"
	"sync/atomic"
	"testing"
	"time"

	"github.com/sagernet/gvisor/pkg/waiter"
	"golang.org/x/sys/unix"
)

type countingValidator struct{ calls atomic.Int32 }

func (v *countingValidator) Validate(_ string, _ int, _ string, _ int, _ int) bool {
	v.calls.Add(1)
	return true
}

// udpIPv4 builds an IPv4/UDP packet without a UDP checksum (allowed for IPv4).
func udpIPv4(src, dst net.IP, srcPort, dstPort uint16, payload []byte) []byte {
	pkt := make([]byte, 28+len(payload))
	pkt[0] = 0x45
	binary.BigEndian.PutUint16(pkt[2:], uint16(len(pkt)))
	pkt[8] = 64
	pkt[9] = 17
	copy(pkt[12:16], src.To4())
	copy(pkt[16:20], dst.To4())
	var sum uint32
	for i := 0; i < 20; i += 2 {
		sum += uint32(binary.BigEndian.Uint16(pkt[i:]))
	}
	for sum > 0xffff {
		sum = sum>>16 + sum&0xffff
	}
	binary.BigEndian.PutUint16(pkt[10:], ^uint16(sum))
	binary.BigEndian.PutUint16(pkt[20:], srcPort)
	binary.BigEndian.PutUint16(pkt[22:], dstPort)
	binary.BigEndian.PutUint16(pkt[24:], uint16(8+len(payload)))
	copy(pkt[28:], payload)
	return pkt
}

// socksUDPServer answers one UDP ASSOCIATE with relay and hands over the control connection.
func socksUDPServer(t *testing.T, relay *net.UDPAddr) (port int, ctrl <-chan net.Conn) {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	ch := make(chan net.Conn, 1)
	go func() {
		c, err := ln.Accept()
		if err != nil {
			return
		}
		greeting := make([]byte, 3)
		req := make([]byte, 10)
		if _, err := io.ReadFull(c, greeting); err != nil {
			return
		}
		c.Write([]byte{0x05, 0x00})
		if _, err := io.ReadFull(c, req); err != nil {
			return
		}
		reply := []byte{0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0, 0}
		binary.BigEndian.PutUint16(reply[8:], uint16(relay.Port))
		c.Write(reply)
		ch <- c
	}()
	return ln.Addr().(*net.TCPAddr).Port, ch
}

// An allowed decision must not outlive its flow: the cache key has no app identity, so
// another app reusing the 5-tuple within the TTL would be admitted without a validator call.
func TestUDPFlowEndInvalidatesValidation(t *testing.T) {
	fds, err := unix.Socketpair(unix.AF_UNIX, unix.SOCK_DGRAM, 0)
	if err != nil {
		t.Fatal(err)
	}
	app := fds[0]
	defer unix.Close(app)
	defer unix.Close(fds[1])

	relay, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	defer relay.Close()
	socksPort, ctrl := socksUDPServer(t, relay.LocalAddr().(*net.UDPAddr))

	validator := &countingValidator{}
	hook := NewEngineHook(16, 3600)
	hook.SetValidator(validator)
	e, err := NewEngine(fds[1], 1500, "127.0.0.1", socksPort, "", "", false, false, hook)
	if err != nil {
		t.Fatal(err)
	}
	go e.Start()
	defer e.Stop()

	pkt := udpIPv4(net.IPv4(10, 0, 0, 2), net.IPv4(192, 0, 2, 1), 40000, 53, []byte("q"))
	if _, err := unix.Write(app, pkt); err != nil {
		t.Fatal(err)
	}
	var c net.Conn
	select {
	case c = <-ctrl:
	case <-time.After(5 * time.Second):
		t.Fatal("no UDP ASSOCIATE from the flow")
	}
	if validator.calls.Load() != 1 || hook.CacheLen() != 1 {
		t.Fatalf("validator calls %d, cache %d; want 1, 1 while the flow lives", validator.calls.Load(), hook.CacheLen())
	}

	c.Close() // the core drops the association: the flow ends
	deadline := time.Now().Add(5 * time.Second)
	for hook.CacheLen() != 0 && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if n := hook.CacheLen(); n != 0 {
		t.Fatalf("cache holds %d decision(s) after the flow ended; want 0", n)
	}
}

type orderConn struct {
	net.Conn
	released           *bool
	closedAfterRelease bool
}

func (c *orderConn) Close() error {
	c.closedAfterRelease = *c.released
	return nil
}

// The allowed decision must be gone before the endpoint closes: the stack accepts a new
// flow on the same 5-tuple as soon as it is closed, and that flow must be validated again.
func TestReleasingConnReleasesBeforeClose(t *testing.T) {
	var released bool
	calls := 0
	inner := &orderConn{released: &released}
	c := &releasingConn{Conn: inner, release: func() { released = true; calls++ }}
	c.Close()
	c.Close()
	if !inner.closedAfterRelease {
		t.Fatal("the connection closed before the decision was released")
	}
	if calls != 1 {
		t.Fatalf("release called %d times; want 1", calls)
	}
}

type halfCloseConn struct {
	net.Conn
	closedWrite, closed bool
}

func (c *halfCloseConn) CloseWrite() error { c.closedWrite = true; return nil }
func (c *halfCloseConn) Close() error      { c.closed = true; return nil }

// A half-close must reach the endpoint and keep the flow and its decision: pipeConnections
// turns EOF from the proxy into CloseWrite and keeps the other direction working.
func TestReleasingConnPassesHalfClose(t *testing.T) {
	released := false
	inner := &halfCloseConn{}
	var c net.Conn = &releasingConn{Conn: inner, release: func() { released = true }}
	cw, ok := c.(interface{ CloseWrite() error })
	if !ok {
		t.Fatal("releasingConn hides CloseWrite: a half-close would close the whole flow")
	}
	cw.CloseWrite()
	if !inner.closedWrite || inner.closed || released {
		t.Fatalf("closedWrite %v, closed %v, released %v; want true, false, false", inner.closedWrite, inner.closed, released)
	}
}

type readiness waiter.EventMask

func (r readiness) Readiness(mask waiter.EventMask) waiter.EventMask {
	return waiter.EventMask(r) & mask
}

// An app reset while the SOCKS dial is pending removes the endpoint without a Close; the
// decision must go with it, or a new SYN on the 5-tuple skips the validator.
func TestReleasingConnReleasesOnHangup(t *testing.T) {
	for _, tc := range []struct {
		name   string
		before readiness
		notify waiter.EventMask
	}{
		{"reset later", 0, waiter.EventHUp},
		{"error later", 0, waiter.EventErr},
		{"already reset", readiness(waiter.EventHUp), 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var wq waiter.Queue
			calls := 0
			inner := &halfCloseConn{}
			c := &releasingConn{Conn: inner, release: func() { calls++ }}
			c.releaseOnHangup(&wq, tc.before)
			if tc.notify != 0 {
				wq.Notify(waiter.ReadableEvents)
				if calls != 0 {
					t.Fatal("released on a readable event")
				}
				wq.Notify(tc.notify)
			}
			c.Close()
			if calls != 1 {
				t.Fatalf("release called %d times; want 1", calls)
			}
			if inner.closed != true {
				t.Fatal("Close didn't close the endpoint")
			}
		})
	}
}
