package tun2socks

import (
	"context"
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"time"
)

const (
	dialTimeout      = 5 * time.Second
	// Time allowed for the full SOCKS5 handshake + CONNECT response.
	// xray only sends CONNECT response after establishing the upstream connection,
	// so this must cover both xray's own dial timeout and local latency.
	handshakeTimeout = 30 * time.Second
)

// SOCKS5Client implements a minimal SOCKS5 client (CONNECT and UDP ASSOCIATE).
type SOCKS5Client struct {
	host     string
	port     int
	username string
	password string
}

// NewSOCKS5Client creates a new SOCKS5 client.
func NewSOCKS5Client(host string, port int, username, password string) *SOCKS5Client {
	return &SOCKS5Client{host: host, port: port, username: username, password: password}
}

// DialTCP connects to the SOCKS5 proxy and issues a CONNECT command.
// Returns the established proxy connection ready for use.
// ctx is used to cancel the initial TCP dial (e.g. when the engine is stopped);
// once the connection is established the context is not watched.
func (s *SOCKS5Client) DialTCP(ctx context.Context, dstIP string, dstPort int) (net.Conn, error) {
	d := net.Dialer{Timeout: dialTimeout}
	conn, err := d.DialContext(ctx, "tcp", fmt.Sprintf("%s:%d", s.host, s.port))
	if err != nil {
		return nil, fmt.Errorf("socks5: dial proxy: %w", err)
	}

	// Bound the entire handshake+CONNECT phase. Without this deadline the goroutine
	// blocks indefinitely in io.ReadFull: xray accepts the TCP connection immediately
	// but only sends the CONNECT response after establishing its own upstream connection.
	// During network transitions (WiFi→LTE) that upstream dial can hang for tens of
	// seconds, causing all forwarding goroutines to pile up while IsRunning()=true.
	if err := conn.SetDeadline(time.Now().Add(handshakeTimeout)); err != nil {
		conn.Close()
		return nil, fmt.Errorf("socks5: set deadline: %w", err)
	}

	if err := s.handshake(conn); err != nil {
		conn.Close()
		return nil, fmt.Errorf("socks5: handshake: %w", err)
	}

	if err := s.sendConnect(conn, dstIP, dstPort); err != nil {
		conn.Close()
		return nil, fmt.Errorf("socks5: CONNECT: %w", err)
	}

	// Clear deadline: the data pipe must not be limited by handshakeTimeout.
	if err := conn.SetDeadline(time.Time{}); err != nil {
		conn.Close()
		return nil, fmt.Errorf("socks5: clear deadline: %w", err)
	}

	return conn, nil
}

// UDPAssociation holds an active SOCKS5 UDP ASSOCIATE session.
// The caller must call Close when done — this closes the control TCP connection
// and the local UDP socket.
type UDPAssociation struct {
	// RelayAddr is the proxy UDP relay address to send datagrams to.
	RelayAddr *net.UDPAddr
	// UDPConn is the bound local UDP socket used to communicate with the proxy.
	UDPConn *net.UDPConn
	// ctrl is the TCP control connection that must stay open for the relay lifetime.
	ctrl net.Conn
}

// Close releases the UDP association by closing both the local UDP socket and the TCP control connection.
func (a *UDPAssociation) Close() error {
	a.UDPConn.Close()
	return a.ctrl.Close()
}

// UDPAssociate sends a UDP ASSOCIATE command to the SOCKS5 proxy.
// It pre-binds a local UDP port and sends it to the proxy to enforce Strict Source Binding.
// ctx cancels the initial TCP dial; once established the context is not watched.
func (s *SOCKS5Client) UDPAssociate(ctx context.Context) (*UDPAssociation, error) {
	d := net.Dialer{Timeout: dialTimeout}
	conn, err := d.DialContext(ctx, "tcp", fmt.Sprintf("%s:%d", s.host, s.port))
	if err != nil {
		return nil, fmt.Errorf("socks5: dial proxy for UDP ASSOCIATE: %w", err)
	}

	if err := conn.SetDeadline(time.Now().Add(handshakeTimeout)); err != nil {
		conn.Close()
		return nil, fmt.Errorf("socks5: set deadline: %w", err)
	}

	if err := s.handshake(conn); err != nil {
		conn.Close()
		return nil, fmt.Errorf("socks5: handshake for UDP: %w", err)
	}

	// 1. Bind local UDP port on loopback
	localAddr := &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 0}
	udpConn, err := net.ListenUDP("udp", localAddr)
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("socks5: failed to bind local udp: %w", err)
	}
	boundPort := udpConn.LocalAddr().(*net.UDPAddr).Port

	// 2. Send UDP ASSOCIATE with the specific bound port
	req := []byte{
		0x05, 0x03, 0x00, // VER=5, CMD=UDP ASSOCIATE, RSV
		0x01,             // ATYP: IPv4
		127, 0, 0, 1,     // BND.ADDR: 127.0.0.1
		byte(boundPort >> 8), byte(boundPort), // BND.PORT: our allocated port
	}
	if _, err := conn.Write(req); err != nil {
		udpConn.Close()
		conn.Close()
		return nil, fmt.Errorf("socks5: write UDP ASSOCIATE req: %w", err)
	}

	relayAddr, err := readSocksAddress(conn)
	if err != nil {
		udpConn.Close()
		conn.Close()
		return nil, fmt.Errorf("socks5: UDP ASSOCIATE response: %w", err)
	}

	udpAddr, err := net.ResolveUDPAddr("udp", relayAddr)
	if err != nil {
		udpConn.Close()
		conn.Close()
		return nil, fmt.Errorf("socks5: resolve relay addr %q: %w", relayAddr, err)
	}

	// The control TCP connection must stay open for the lifetime of the UDP relay.
	// Clear the handshake deadline so it doesn't expire during a long UDP session.
	if err := conn.SetDeadline(time.Time{}); err != nil {
		udpConn.Close()
		conn.Close()
		return nil, fmt.Errorf("socks5: clear deadline: %w", err)
	}

	return &UDPAssociation{RelayAddr: udpAddr, UDPConn: udpConn, ctrl: conn}, nil
}

// EncodeUDPDatagram wraps payload in a SOCKS5 UDP datagram header (RFC 1928 §7).
//
//	+----+------+------+----------+----------+----------+
//	|RSV | FRAG | ATYP | DST.ADDR | DST.PORT |   DATA   |
//	+----+------+------+----------+----------+----------+
func EncodeUDPDatagram(dstIP net.IP, dstPort int, payload []byte) []byte {
	var atyp byte
	var addr []byte
	if v4 := dstIP.To4(); v4 != nil {
		atyp = 0x01
		addr = v4
	} else {
		atyp = 0x04
		addr = dstIP.To16()
	}

	hdr := make([]byte, 4+len(addr)+2)
	hdr[0] = 0x00 // RSV
	hdr[1] = 0x00 // RSV
	hdr[2] = 0x00 // FRAG = 0 (no fragmentation)
	hdr[3] = atyp
	copy(hdr[4:], addr)
	binary.BigEndian.PutUint16(hdr[4+len(addr):], uint16(dstPort))
	return append(hdr, payload...)
}

// DecodeUDPDatagram parses a SOCKS5 UDP datagram, returning the origin address and payload.
func DecodeUDPDatagram(data []byte) (srcIP net.IP, srcPort int, payload []byte, err error) {
	if len(data) < 4 {
		return nil, 0, nil, fmt.Errorf("socks5 UDP: datagram too short")
	}
	if data[2] != 0x00 {
		return nil, 0, nil, fmt.Errorf("socks5 UDP: fragmented datagrams not supported (FRAG=%d)", data[2])
	}

	atyp := data[3]
	switch atyp {
	case 0x01: // IPv4
		if len(data) < 4+4+2 {
			return nil, 0, nil, fmt.Errorf("socks5 UDP: IPv4 datagram too short")
		}
		srcIP = net.IP(data[4:8])
		srcPort = int(binary.BigEndian.Uint16(data[8:10]))
		payload = data[10:]
	case 0x04: // IPv6
		if len(data) < 4+16+2 {
			return nil, 0, nil, fmt.Errorf("socks5 UDP: IPv6 datagram too short")
		}
		srcIP = net.IP(data[4:20])
		srcPort = int(binary.BigEndian.Uint16(data[20:22]))
		payload = data[22:]
	default:
		return nil, 0, nil, fmt.Errorf("socks5 UDP: unsupported ATYP 0x%02x", atyp)
	}
	return srcIP, srcPort, payload, nil
}

// --- internal helpers ---

// handshake performs SOCKS5 method selection and optional username/password auth.
func (s *SOCKS5Client) handshake(conn net.Conn) error {
	// Method selection
	var methods []byte
	if s.username != "" {
		methods = []byte{0x05, 0x02, 0x00, 0x02} // NO AUTH + USERNAME/PASSWORD
	} else {
		methods = []byte{0x05, 0x01, 0x00} // NO AUTH only
	}
	if _, err := conn.Write(methods); err != nil {
		return fmt.Errorf("write method selection: %w", err)
	}

	resp := make([]byte, 2)
	if _, err := io.ReadFull(conn, resp); err != nil {
		return fmt.Errorf("read method response: %w", err)
	}
	if resp[0] != 0x05 {
		return fmt.Errorf("unexpected SOCKS version 0x%02x", resp[0])
	}

	switch resp[1] {
	case 0x00:
		return nil // no auth required
	case 0x02:
		return s.authUserPass(conn)
	case 0xFF:
		return fmt.Errorf("proxy rejected all auth methods")
	default:
		return fmt.Errorf("unsupported auth method 0x%02x", resp[1])
	}
}

// authUserPass performs RFC 1929 username/password sub-negotiation.
func (s *SOCKS5Client) authUserPass(conn net.Conn) error {
	user := []byte(s.username)
	pass := []byte(s.password)

	buf := make([]byte, 0, 3+len(user)+len(pass))
	buf = append(buf, 0x01)
	buf = append(buf, byte(len(user)))
	buf = append(buf, user...)
	buf = append(buf, byte(len(pass)))
	buf = append(buf, pass...)

	if _, err := conn.Write(buf); err != nil {
		return fmt.Errorf("write auth: %w", err)
	}

	resp := make([]byte, 2)
	if _, err := io.ReadFull(conn, resp); err != nil {
		return fmt.Errorf("read auth response: %w", err)
	}
	if resp[0] != 0x01 { // RFC 1929: sub-negotiation version must be 0x01
		return fmt.Errorf("unexpected auth sub-negotiation version 0x%02x", resp[0])
	}
	if resp[1] != 0x00 {
		return fmt.Errorf("authentication failed (status=0x%02x)", resp[1])
	}
	return nil
}

// sendConnect sends a SOCKS5 CONNECT command and reads the response.
func (s *SOCKS5Client) sendConnect(conn net.Conn, dstIP string, dstPort int) error {
	ip := net.ParseIP(dstIP)
	if ip == nil {
		return fmt.Errorf("invalid destination IP: %s", dstIP)
	}

	var atyp byte
	var addr []byte
	if v4 := ip.To4(); v4 != nil {
		atyp = 0x01
		addr = v4
	} else {
		atyp = 0x04
		addr = ip.To16()
	}

	req := make([]byte, 0, 6+len(addr))
	req = append(req, 0x05, 0x01, 0x00, atyp)
	req = append(req, addr...)
	req = append(req, byte(dstPort>>8), byte(dstPort))

	if _, err := conn.Write(req); err != nil {
		return fmt.Errorf("write CONNECT request: %w", err)
	}

	// Read and discard the bind address — we don't need it for CONNECT.
	if _, err := readSocksAddress(conn); err != nil {
		return fmt.Errorf("read CONNECT response: %w", err)
	}
	return nil
}

// readSocksAddress reads a SOCKS5 reply header (VER REP RSV ATYP BND.ADDR BND.PORT)
// and returns the bound address as "host:port". Validates VER and REP fields.
func readSocksAddress(conn net.Conn) (string, error) {
	hdr := make([]byte, 4)
	if _, err := io.ReadFull(conn, hdr); err != nil {
		return "", fmt.Errorf("read reply header: %w", err)
	}
	if hdr[0] != 0x05 {
		return "", fmt.Errorf("unexpected SOCKS version in reply: 0x%02x", hdr[0])
	}
	if hdr[1] != 0x00 {
		return "", fmt.Errorf("SOCKS5 error reply 0x%02x", hdr[1])
	}

	atyp := hdr[3]
	var host string
	switch atyp {
	case 0x01: // IPv4
		addr := make([]byte, 4)
		if _, err := io.ReadFull(conn, addr); err != nil {
			return "", fmt.Errorf("read IPv4 bind addr: %w", err)
		}
		host = net.IP(addr).String()
	case 0x04: // IPv6
		addr := make([]byte, 16)
		if _, err := io.ReadFull(conn, addr); err != nil {
			return "", fmt.Errorf("read IPv6 bind addr: %w", err)
		}
		host = net.IP(addr).String()
	case 0x03: // domain name
		lenBuf := make([]byte, 1)
		if _, err := io.ReadFull(conn, lenBuf); err != nil {
			return "", fmt.Errorf("read domain length: %w", err)
		}
		name := make([]byte, lenBuf[0])
		if _, err := io.ReadFull(conn, name); err != nil {
			return "", fmt.Errorf("read domain: %w", err)
		}
		host = string(name)
	default:
		return "", fmt.Errorf("unsupported bind address type 0x%02x", atyp)
	}

	portBuf := make([]byte, 2)
	if _, err := io.ReadFull(conn, portBuf); err != nil {
		return "", fmt.Errorf("read bind port: %w", err)
	}
	port := binary.BigEndian.Uint16(portBuf)
	return fmt.Sprintf("%s:%d", host, port), nil
}
