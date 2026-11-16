//go:build linux || android

package tun2socks_test

import (
	"bytes"
	"net"
	"testing"

	. "github.com/Wendor/teapod-tun2socks"
)

// ── EncodeUDPDatagram / DecodeUDPDatagram ─────────────────────────────────────

func TestEncodeDecodeDatagram_IPv4_Roundtrip(t *testing.T) {
	dstIP := net.ParseIP("1.2.3.4").To4()
	dstPort := 5353
	payload := []byte("hello udp")

	encoded := EncodeUDPDatagram(dstIP, dstPort, payload)

	_, _, decoded, err := DecodeUDPDatagram(encoded)
	if err != nil {
		t.Fatalf("DecodeUDPDatagram: %v", err)
	}
	if !bytes.Equal(decoded, payload) {
		t.Errorf("payload mismatch: got %q, want %q", decoded, payload)
	}
}

func TestEncodeDecodeDatagram_IPv6_Roundtrip(t *testing.T) {
	dstIP := net.ParseIP("2001:db8::1")
	dstPort := 443
	payload := []byte{0xDE, 0xAD, 0xBE, 0xEF}

	encoded := EncodeUDPDatagram(dstIP, dstPort, payload)

	_, _, decoded, err := DecodeUDPDatagram(encoded)
	if err != nil {
		t.Fatalf("DecodeUDPDatagram IPv6: %v", err)
	}
	if !bytes.Equal(decoded, payload) {
		t.Errorf("payload mismatch: got %x, want %x", decoded, payload)
	}
}

func TestEncodeDecodeDatagram_EmptyPayload(t *testing.T) {
	dstIP := net.ParseIP("10.0.0.1").To4()
	encoded := EncodeUDPDatagram(dstIP, 80, []byte{})

	_, _, decoded, err := DecodeUDPDatagram(encoded)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(decoded) != 0 {
		t.Errorf("expected empty payload, got %x", decoded)
	}
}

func TestEncodeDecodeDatagram_PortPreserved(t *testing.T) {
	dstIP := net.ParseIP("8.8.8.8").To4()
	dstPort := 53

	encoded := EncodeUDPDatagram(dstIP, dstPort, []byte("query"))

	srcIP, srcPort, _, err := DecodeUDPDatagram(encoded)
	if err != nil {
		t.Fatalf("DecodeUDPDatagram: %v", err)
	}
	if srcPort != dstPort {
		t.Errorf("port: got %d, want %d", srcPort, dstPort)
	}
	if !srcIP.Equal(dstIP) {
		t.Errorf("IP: got %s, want %s", srcIP, dstIP)
	}
}

func TestEncodeUDPDatagram_IPv4Header(t *testing.T) {
	dstIP := net.ParseIP("192.168.1.1").To4()
	payload := []byte("test")
	encoded := EncodeUDPDatagram(dstIP, 1234, payload)

	// Format: RSV(2) FRAG(1) ATYP(1) ADDR(4) PORT(2) DATA
	// Header total = 10 bytes for IPv4
	const hdrLen = 2 + 1 + 1 + 4 + 2
	if len(encoded) != hdrLen+len(payload) {
		t.Errorf("encoded len = %d, want %d", len(encoded), hdrLen+len(payload))
	}
	if encoded[2] != 0x00 {
		t.Errorf("FRAG field = 0x%02x, want 0x00", encoded[2])
	}
	if encoded[3] != 0x01 {
		t.Errorf("ATYP field = 0x%02x, want 0x01 (IPv4)", encoded[3])
	}
}

func TestEncodeUDPDatagram_IPv6Header(t *testing.T) {
	dstIP := net.ParseIP("::1")
	payload := []byte("test")
	encoded := EncodeUDPDatagram(dstIP, 80, payload)

	// IPv6 header: RSV(2) FRAG(1) ATYP(1) ADDR(16) PORT(2) = 22 bytes
	const hdrLen = 2 + 1 + 1 + 16 + 2
	if len(encoded) != hdrLen+len(payload) {
		t.Errorf("encoded len = %d, want %d", len(encoded), hdrLen+len(payload))
	}
	if encoded[3] != 0x04 {
		t.Errorf("ATYP field = 0x%02x, want 0x04 (IPv6)", encoded[3])
	}
}

func TestDecodeDatagram_TooShort(t *testing.T) {
	_, _, _, err := DecodeUDPDatagram([]byte{0x00, 0x00})
	if err == nil {
		t.Error("expected error for too-short datagram")
	}
}

func TestDecodeDatagram_Fragmented(t *testing.T) {
	// FRAG != 0 must return an error
	data := make([]byte, 20)
	data[2] = 0x01 // FRAG = 1
	data[3] = 0x01 // ATYP = IPv4

	_, _, _, err := DecodeUDPDatagram(data)
	if err == nil {
		t.Error("expected error for fragmented datagram (FRAG != 0)")
	}
}

func TestDecodeDatagram_UnknownAtyp(t *testing.T) {
	data := []byte{0, 0, 0, 0x99, 0, 0, 0, 0, 0, 0} // ATYP = 0x99
	_, _, _, err := DecodeUDPDatagram(data)
	if err == nil {
		t.Error("expected error for unknown ATYP")
	}
}

func TestDecodeDatagram_IPv4TooShort(t *testing.T) {
	// RSV RSV FRAG ATYP=IPv4, but not enough data for a 4-byte address + port
	data := []byte{0, 0, 0, 0x01, 1, 2} // only 2 bytes instead of the required 6
	_, _, _, err := DecodeUDPDatagram(data)
	if err == nil {
		t.Error("expected error for truncated IPv4 datagram")
	}
}
