package tun2socks

import (
	"context"
	"io"
	"net"
	"testing"
	"time"
)

// An IPv6 bind address must come back as "[addr]:port": UDPAssociate resolves it.
func TestReadSocksAddressIPv6(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()
	reply := append([]byte{0x05, 0x00, 0x00, 0x04}, net.ParseIP("::1").To16()...)
	reply = append(reply, 0x04, 0x38) // port 1080
	go server.Write(reply)

	addr, err := readSocksAddress(client)
	if err != nil {
		t.Fatal(err)
	}
	if addr != "[::1]:1080" {
		t.Fatalf("address %q; want [::1]:1080", addr)
	}
	if _, err := net.ResolveUDPAddr("udp", addr); err != nil {
		t.Fatalf("UDPAssociate can't resolve %q: %v", addr, err)
	}
}

// A proxy on an IPv6 address must be dialable.
func TestDialTCPToIPv6Proxy(t *testing.T) {
	ln, err := net.Listen("tcp", "[::1]:0")
	if err != nil {
		t.Skipf("no IPv6 loopback: %v", err)
	}
	defer ln.Close()
	go func() {
		c, err := ln.Accept()
		if err != nil {
			return
		}
		defer c.Close()
		buf := make([]byte, 3)
		io.ReadFull(c, buf) // greeting: no auth
		c.Write([]byte{0x05, 0x00})
		req := make([]byte, 10)
		io.ReadFull(c, req) // CONNECT to an IPv4 destination
		c.Write([]byte{0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0, 80})
	}()

	port := ln.Addr().(*net.TCPAddr).Port
	conn, err := NewSOCKS5Client("::1", port, "", "").DialTCP(context.Background(), "192.0.2.1", 80)
	if err != nil {
		t.Fatalf("DialTCP via [::1]:%d: %v", port, err)
	}
	conn.Close()
}

// udpAssociateServer accepts one UDP ASSOCIATE and replies with relay as BND.ADDR, or
// with host and relay's port when host is set. It returns the address the client sent.
func udpAssociateServer(t *testing.T, ln net.Listener, relay *net.UDPAddr, host string) <-chan net.IP {
	t.Helper()
	got := make(chan net.IP, 1)
	go func() {
		c, err := ln.Accept()
		if err != nil {
			return
		}
		defer c.Close()
		buf := make([]byte, 3)
		io.ReadFull(c, buf) // greeting: no auth
		c.Write([]byte{0x05, 0x00})
		head := make([]byte, 4)
		io.ReadFull(c, head)
		addr := make([]byte, 4)
		if head[3] == 0x04 {
			addr = make([]byte, 16)
		}
		io.ReadFull(c, addr)
		io.ReadFull(c, make([]byte, 2))
		got <- net.IP(addr)
		reply := []byte{0x05, 0x00, 0x00, 0x01}
		ip := relay.IP.To4()
		if host != "" {
			reply[3], ip = 0x03, append([]byte{byte(len(host))}, host...)
		} else if ip == nil {
			reply[3], ip = 0x04, relay.IP.To16()
		}
		reply = append(append(reply, ip...), byte(relay.Port>>8), byte(relay.Port))
		c.Write(reply)
		io.Copy(io.Discard, c) // keep the control connection open
	}()
	return got
}

// A proxy on IPv6 gets an IPv6 local socket, so datagrams reach its IPv6 relay.
func TestUDPAssociateThroughIPv6Relay(t *testing.T) {
	ln, err := net.Listen("tcp", "[::1]:0")
	if err != nil {
		t.Skipf("no IPv6 loopback: %v", err)
	}
	defer ln.Close()
	relay, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv6loopback})
	if err != nil {
		t.Fatal(err)
	}
	defer relay.Close()
	sent := udpAssociateServer(t, ln, relay.LocalAddr().(*net.UDPAddr), "")

	assoc, err := NewSOCKS5Client("::1", ln.Addr().(*net.TCPAddr).Port, "", "").UDPAssociate(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	defer assoc.Close()
	if ip := <-sent; !ip.Equal(net.IPv6loopback) {
		t.Fatalf("ASSOCIATE sent BND.ADDR %s; want ::1", ip)
	}
	if _, err := assoc.UDPConn.WriteToUDP([]byte("ping"), assoc.RelayAddr); err != nil {
		t.Fatalf("send to relay %s: %v", assoc.RelayAddr, err)
	}
	relay.SetReadDeadline(time.Now().Add(2 * time.Second))
	buf := make([]byte, 16)
	n, _, err := relay.ReadFromUDP(buf)
	if err != nil || string(buf[:n]) != "ping" {
		t.Fatalf("relay got %q, %v; want ping", buf[:n], err)
	}
}

// A relay of another family than the proxy can't be reached from the local socket:
// UDPAssociate refuses it instead of failing every datagram later.
func TestUDPAssociateRejectsRelayOfOtherFamily(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	udpAssociateServer(t, ln, &net.UDPAddr{IP: net.IPv6loopback, Port: 5000}, "")

	assoc, err := NewSOCKS5Client("127.0.0.1", ln.Addr().(*net.TCPAddr).Port, "", "").UDPAssociate(context.Background())
	if err == nil {
		assoc.Close()
		t.Fatal("UDPAssociate accepted an IPv6 relay for an IPv4 socket")
	}
}

// A relay host name with IPv4 and IPv6 addresses resolves in the proxy's family, not to
// the IPv4 address the plain "udp" network picks first.
func TestUDPAssociateResolvesRelayNameInProxyFamily(t *testing.T) {
	var v4, v6 bool
	ips, _ := net.LookupIP("localhost")
	for _, ip := range ips {
		v4, v6 = v4 || ip.To4() != nil, v6 || ip.To4() == nil
	}
	if !v4 || !v6 {
		t.Skipf("localhost resolves to %v; need IPv4 and IPv6", ips)
	}
	ln, err := net.Listen("tcp", "[::1]:0")
	if err != nil {
		t.Skipf("no IPv6 loopback: %v", err)
	}
	defer ln.Close()
	udpAssociateServer(t, ln, &net.UDPAddr{Port: 5000}, "localhost")

	assoc, err := NewSOCKS5Client("::1", ln.Addr().(*net.TCPAddr).Port, "", "").UDPAssociate(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	defer assoc.Close()
	if !assoc.RelayAddr.IP.Equal(net.IPv6loopback) {
		t.Fatalf("relay %v; want [::1]:5000", assoc.RelayAddr)
	}
}
