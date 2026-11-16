//go:build with_gvisor

package awg

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/netip"
	"strings"
	"testing"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"github.com/amnezia-vpn/amneziawg-go/v3/device"
	"github.com/sagernet/gvisor/pkg/tcpip"
	"github.com/sagernet/gvisor/pkg/tcpip/adapters/gonet"
	"github.com/sagernet/gvisor/pkg/tcpip/header"
	gvstack "github.com/sagernet/gvisor/pkg/tcpip/stack"
	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	tun "github.com/sagernet/sing-tun"
	"github.com/sagernet/sing/common/json"
	M "github.com/sagernet/sing/common/metadata"
	"golang.org/x/crypto/curve25519"
)

type keyPair struct{ private, public []byte }

func newKeyPair(t *testing.T) keyPair {
	t.Helper()
	priv := make([]byte, 32)
	if _, err := rand.Read(priv); err != nil {
		t.Fatal(err)
	}
	priv[0] &= 248
	priv[31] = (priv[31] & 127) | 64
	pub, err := curve25519.X25519(priv, curve25519.Basepoint)
	if err != nil {
		t.Fatal(err)
	}
	return keyPair{priv, pub}
}

func b64(b []byte) string { return base64.StdEncoding.EncodeToString(b) }

var serverAmnezia = AmneziaOptions{
	Jc: 4, Jmin: 40, Jmax: 70, S1: 16, S2: 16, S3: 16, S4: 16,
	H1: "100-200", H2: "300", H3: "400", H4: "500-600", I1: "<b 0xc0ffee><r 16>",
}

// startServer — reference amneziawg-go with an HTTP server on 10.66.0.1:80 inside the tunnel.
func startServer(t *testing.T, server, client keyPair, amnezia AmneziaOptions) uint16 {
	t.Helper()
	port, _ := startServerWithStack(t, server, client, amnezia)
	return port
}

func startServerWithStack(t *testing.T, server, client keyPair, amnezia AmneziaOptions) (uint16, *gvstack.Stack) {
	t.Helper()
	stack, err := newStackDevice(1408, []netip.Prefix{netip.MustParsePrefix("10.66.0.1/24")})
	if err != nil {
		t.Fatal(err)
	}
	logger := &device.Logger{Verbosef: func(string, ...any) {}, Errorf: func(f string, a ...any) { t.Logf("server: "+f, a...) }}
	dev := device.NewDevice(stack, conn.NewStdNetBind(), logger)
	t.Cleanup(dev.Close)
	awgIpc, err := amnezia.IpcConfig()
	if err != nil {
		t.Fatal(err)
	}
	ipc := "private_key=" + hex.EncodeToString(server.private) + "\nlisten_port=0\n" + awgIpc +
		"public_key=" + hex.EncodeToString(client.public) + "\nallowed_ip=10.66.0.2/32\n"
	if err := dev.IpcSet(ipc); err != nil {
		t.Fatal(err)
	}
	stack.Reconfigured()
	if err := stack.Start(); err != nil {
		t.Fatal(err)
	}
	if err := dev.Up(); err != nil {
		t.Fatal(err)
	}
	listener, err := gonet.ListenTCP(stack.stack, tcpip.FullAddress{NIC: tun.DefaultNIC, Port: 80,
		Addr: tun.AddressFromAddr(netip.MustParseAddr("10.66.0.1"))}, header.IPv4ProtocolNumber)
	if err != nil {
		t.Fatal(err)
	}
	srv := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(w, "awg-ok")
	})}
	go srv.Serve(listener)
	t.Cleanup(func() { _ = srv.Close() })

	get, err := dev.IpcGet()
	if err != nil {
		t.Fatal(err)
	}
	for _, line := range strings.Split(get, "\n") {
		if port, ok := strings.CutPrefix(line, "listen_port="); ok {
			var p uint16
			fmt.Sscan(port, &p)
			return p, stack.stack
		}
	}
	t.Fatal("server listen port not found")
	return 0, nil
}

// startClient — sing-box with an awg endpoint to the server.
func startClient(t *testing.T, server, client keyPair, port uint16, amnezia AmneziaOptions) *box.Box {
	t.Helper()
	registry := include.EndpointRegistry()
	RegisterEndpoint(registry)
	ctx := box.Context(context.Background(), include.InboundRegistry(), include.OutboundRegistry(), registry,
		include.DNSTransportRegistry(), include.ServiceRegistry(), include.CertificateProviderRegistry())
	amneziaJSON, _ := json.Marshal(amnezia)
	config := fmt.Sprintf(`{"log":{"disabled":true},"endpoints":[{"type":"awg","tag":"proxy",
		"address":["10.66.0.2/32"],"private_key":%q,
		"peers":[{"address":"127.0.0.1","port":%d,"public_key":%q,"allowed_ips":["10.66.0.0/24"]}],
		"amnezia":%s}]}`, b64(client.private), port, b64(server.public), amneziaJSON)
	opts, err := json.UnmarshalExtendedContext[option.Options](ctx, []byte(config))
	if err != nil {
		t.Fatal(err)
	}
	instance, err := box.New(box.Options{Context: ctx, Options: opts})
	if err != nil {
		t.Fatal(err)
	}
	if err := instance.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = instance.Close() })
	return instance
}

func get(instance *box.Box, timeout time.Duration) (string, error) {
	ep, ok := instance.Endpoint().Get("proxy")
	if !ok {
		return "", fmt.Errorf("no proxy endpoint")
	}
	client := &http.Client{Timeout: timeout, Transport: &http.Transport{
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			return ep.DialContext(ctx, network, M.ParseSocksaddr(addr))
		},
	}}
	resp, err := client.Get("http://10.66.0.1/")
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	return string(body), err
}

func TestLoopbackHandshake(t *testing.T) {
	server, client := newKeyPair(t), newKeyPair(t)
	amnezia := serverAmnezia
	amnezia.HeaderProtectionKey = b64(newKeyPair(t).private)
	port := startServer(t, server, client, amnezia)
	body, err := get(startClient(t, server, client, port, amnezia), 10*time.Second)
	if err != nil || body != "awg-ok" {
		t.Fatalf("got %q, %v; want awg-ok", body, err)
	}
}

func TestLoopbackHandshakeMismatchFails(t *testing.T) {
	server, client := newKeyPair(t), newKeyPair(t)
	port := startServer(t, server, client, serverAmnezia)
	wrong := serverAmnezia
	wrong.H1 = "700-800"
	if body, err := get(startClient(t, server, client, port, wrong), 5*time.Second); err == nil {
		t.Fatalf("handshake with mismatched H1 must fail, got %q", body)
	}
}

// AmneziaVPN "AmneziaWG 2" server parameters (AWG 3.1) from a real key.
func TestLoopbackHandshakeAmneziaAWG2(t *testing.T) {
	server, client := newKeyPair(t), newKeyPair(t)
	amnezia := AmneziaOptions{
		Jc: 5, Jmin: 10, Jmax: 50, S1: 12, S2: 12, S3: 12, S4: 12,
		H1: "1", H2: "2", H3: "3", H4: "4",
		HeaderProtectionKey: b64(newKeyPair(t).private),
		RekeyAfterTime:      "100-120", RekeyTimeout: "3-7", RejectAfterTime: "150-180",
		KeepaliveTimeout: "5-15", MaxHandshakeAttempts: "15-20",
		RandomTrailers: true, DisableCookies: true,
	}
	port := startServer(t, server, client, amnezia)
	body, err := get(startClient(t, server, client, port, amnezia), 10*time.Second)
	if err != nil || body != "awg-ok" {
		t.Fatalf("get: %q %v", body, err)
	}
}

// The first UDP packet goes out while the handshake is in progress (sing-box sends a DNS query like this right after
// start) — it must arrive: UDP doesn't retry, DNS would wait 10 s.
func TestLoopbackFirstUDPPacketSurvivesHandshake(t *testing.T) {
	server, client := newKeyPair(t), newKeyPair(t)
	port, stack := startServerWithStack(t, server, client, serverAmnezia)
	echo, err := gonet.DialUDP(stack, &tcpip.FullAddress{NIC: tun.DefaultNIC, Port: 53,
		Addr: tun.AddressFromAddr(netip.MustParseAddr("10.66.0.1"))}, nil, header.IPv4ProtocolNumber)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = echo.Close() })
	go func() {
		buf := make([]byte, 1500)
		for {
			n, from, err := echo.ReadFrom(buf)
			if err != nil {
				return
			}
			_, _ = echo.WriteTo(buf[:n], from)
		}
	}()
	instance := startClient(t, server, client, port, serverAmnezia)
	ep, _ := instance.Endpoint().Get("proxy")
	dst := M.ParseSocksaddr("10.66.0.1:53")
	pc, err := ep.ListenPacket(context.Background(), dst)
	if err != nil {
		t.Fatal(err)
	}
	defer pc.Close()
	if _, err := pc.WriteTo([]byte("query"), dst.UDPAddr()); err != nil {
		t.Fatal(err)
	}
	_ = pc.SetReadDeadline(time.Now().Add(3 * time.Second))
	buf := make([]byte, 64)
	n, _, err := pc.ReadFrom(buf)
	if err != nil || string(buf[:n]) != "query" {
		t.Fatalf("echo: %q %v", buf[:n], err)
	}
}
