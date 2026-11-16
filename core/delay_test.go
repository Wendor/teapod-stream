package teapodcore

import (
	"context"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

func directDial(ctx context.Context, network, addr string) (net.Conn, error) {
	var d net.Dialer
	return d.DialContext(ctx, network, addr)
}

func TestMeasureDelayViaReturnsBestOfTwo(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))
	defer srv.Close()

	ms, err := measureDelayVia(context.Background(), directDial, srv.URL)
	if err != nil || ms < 0 {
		t.Fatalf("got %d, %v; want >= 0, nil", ms, err)
	}
}

func TestMeasureDelayViaBadStatus(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer srv.Close()

	ms, err := measureDelayVia(context.Background(), directDial, srv.URL)
	if ms != -1 || err == nil || !strings.Contains(err.Error(), "unexpected status") {
		t.Fatalf("got %d, %v; want -1, unexpected status", ms, err)
	}
}

func TestMeasureDelayViaDefaultURL(t *testing.T) {
	var mu sync.Mutex
	var addrs []string
	dial := func(_ context.Context, _, addr string) (net.Conn, error) {
		mu.Lock()
		addrs = append(addrs, addr)
		mu.Unlock()
		return nil, errors.New("offline")
	}

	ms, err := measureDelayVia(context.Background(), dial, "")
	if ms != -1 || err == nil {
		t.Fatalf("got %d, %v; want -1, error", ms, err)
	}
	if len(addrs) == 0 || addrs[0] != "www.google.com:443" {
		t.Fatalf("dialed %v; want www.google.com:443", addrs)
	}
}
