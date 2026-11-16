package tun2socks

import (
	"context"
	"io"
	"net"
	"testing"
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
