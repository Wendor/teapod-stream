package tun2socks

import (
	"io"
	"net"
	"testing"
	"time"
)

// tcpPair returns both ends of a loopback TCP connection.
func tcpPair(t *testing.T) (client, server net.Conn) {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	accepted := make(chan net.Conn, 1)
	go func() {
		c, _ := ln.Accept()
		accepted <- c
	}()
	client, err = net.Dial("tcp", ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	return client, <-accepted
}

// A request followed by shutdown(SHUT_WR) must still get its response: EOF from
// the app is a half-close, not the end of the flow.
func TestPipeConnectionsKeepsResponseAfterAppHalfClose(t *testing.T) {
	app, appSide := tcpPair(t)        // app ↔ gVisor side
	proxySide, upstream := tcpPair(t) // tun2socks ↔ xray
	defer app.Close()
	defer upstream.Close()

	now := time.Now().UnixMilli()
	tc := &trackedConn{app: appSide, proxy: proxySide, dst: "test", createdMs: now}
	tc.lastTxMs.Store(now)
	tc.lastRxMs.Store(now)
	done := make(chan struct{})
	go func() {
		pipeConnections(tc, &Engine{})
		close(done)
	}()

	if _, err := app.Write([]byte("request")); err != nil {
		t.Fatal(err)
	}
	if err := app.(*net.TCPConn).CloseWrite(); err != nil {
		t.Fatal(err)
	}

	upstream.SetDeadline(time.Now().Add(5 * time.Second))
	if got, err := io.ReadAll(upstream); err != nil || string(got) != "request" {
		t.Fatalf("upstream got %q, %v; want request + FIN", got, err)
	}
	if _, err := upstream.Write([]byte("response")); err != nil {
		t.Fatal(err)
	}
	upstream.Close()

	app.SetDeadline(time.Now().Add(5 * time.Second))
	if got, err := io.ReadAll(app); err != nil || string(got) != "response" {
		t.Fatalf("app got %q, %v; want the response after its half-close", got, err)
	}
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("pipeConnections did not finish after both directions closed")
	}
}

// The engine's liveness stamp moves only with payload from the proxy: an app's request alone
// (what a dead server leaves — the stack still acks the app) must not make the tunnel look alive.
func TestPipeConnectionsStampsEngineRxOnlyOnProxyPayload(t *testing.T) {
	app, appSide := tcpPair(t)
	proxySide, upstream := tcpPair(t)
	defer app.Close()
	defer upstream.Close()

	now := time.Now().UnixMilli()
	tc := &trackedConn{app: appSide, proxy: proxySide, dst: "test", createdMs: now}
	tc.lastTxMs.Store(now)
	tc.lastRxMs.Store(now)
	e := &Engine{}
	go pipeConnections(tc, e)

	if _, err := app.Write([]byte("request")); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 16)
	upstream.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := io.ReadAtLeast(upstream, buf, len("request")); err != nil {
		t.Fatal(err)
	}
	if got := e.LastRxMs(); got != 0 {
		t.Fatalf("engine rx stamped by the app's request: %d", got)
	}

	if _, err := upstream.Write([]byte("response")); err != nil {
		t.Fatal(err)
	}
	app.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := io.ReadAtLeast(app, buf, len("response")); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(2 * time.Second)
	for e.LastRxMs() == 0 && time.Now().Before(deadline) {
		time.Sleep(5 * time.Millisecond)
	}
	if e.LastRxMs() == 0 {
		t.Fatal("engine rx not stamped by the proxy's response")
	}
}
