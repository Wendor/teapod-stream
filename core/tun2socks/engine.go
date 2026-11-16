package tun2socks

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"sync"
	"sync/atomic"
	"time"

	"github.com/sagernet/gvisor/pkg/buffer"
	"github.com/sagernet/gvisor/pkg/tcpip"
	"github.com/sagernet/gvisor/pkg/tcpip/adapters/gonet"
	"github.com/sagernet/gvisor/pkg/tcpip/header"
	"github.com/sagernet/gvisor/pkg/tcpip/link/channel"
	"github.com/sagernet/gvisor/pkg/tcpip/network/ipv4"
	"github.com/sagernet/gvisor/pkg/tcpip/network/ipv6"
	"github.com/sagernet/gvisor/pkg/tcpip/stack"
	"github.com/sagernet/gvisor/pkg/tcpip/transport/tcp"
	"github.com/sagernet/gvisor/pkg/tcpip/transport/udp"
	"github.com/sagernet/gvisor/pkg/waiter"
	"golang.org/x/sys/unix"
)

// tcpBufPool reuses 32 KB read buffers across TCP pipe goroutines, reducing
// per-connection allocations from O(connections) to O(peak concurrent connections).
var tcpBufPool = sync.Pool{
	New: func() any {
		b := make([]byte, 32*1024)
		return &b
	},
}

const (
	// channelSize is the gVisor outbound packet channel capacity (gVisor → tunWriteLoop).
	// Must be large enough to absorb bursts: 256 was too small and caused dropped SYN-ACKs
	// and ACKs when Telegram received multiple media notifications simultaneously.
	channelSize = 4096
	nicID        tcpip.NICID = 1
	// udpIdleTimeout is the maximum idle time for a UDP flow before its goroutines
	// and sockets are released. The deadline is reset on every received packet, so
	// active sessions (QUIC, gaming) stay alive indefinitely; only truly idle flows
	// (finished DNS queries, stale connections) are cleaned up.
	udpIdleTimeout = 60 * time.Second
	// tcpIdleTimeout is the maximum idle time for a TCP flow, measured across BOTH
	// directions (a one-directional transfer such as a long download keeps the flow
	// alive). Stuck connections (e.g. after an LTE tower handover with no FIN/RST)
	// are cleaned up before they fill the gVisor TCP forwarder backlog (limit: 1024).
	tcpIdleTimeout = 5 * time.Minute
	// tcpZombieTimeout closes a TCP flow early when the app has sent data but the
	// upstream stayed completely silent (request sent, no reply): the typical
	// signature of a mid-stream server-side reset whose close was never propagated
	// end-to-end. Apps re-dial instantly instead of hanging on a dead h2 connection.
	// Aligned with xray's default policy connIdle so legitimate long-polls that
	// survive xray are not cut shorter than xray itself would.
	tcpZombieTimeout = 2 * time.Minute
	// tcpIdleCheckStep is the read-deadline granularity used to periodically
	// re-evaluate idle/zombie state without dedicated sweeper goroutines.
	tcpIdleCheckStep = 30 * time.Second
	// maxUDPConns caps the number of concurrent UDP associations. Each association
	// holds a TCP control connection to the proxy plus a local UDP socket (2 fds) and
	// 3 goroutines, kept alive for up to udpIdleTimeout. Unlike TCP, the UDP forwarder
	// has no built-in backlog, so a QUIC-heavy or misbehaving app fanning out to many
	// destinations could otherwise exhaust the process fd limit within seconds
	// (the src-only validation cache makes each new flow essentially free to admit).
	maxUDPConns = 512
)

type Engine struct {
	stack          *stack.Stack
	endpoint       *channel.Endpoint
	hook           *EngineHook
	mtu            int
	running        atomic.Bool
	stopCh         chan struct{}
	wg             sync.WaitGroup
	tunFile        *os.File
	logPrefix      string
	allowICMP      bool
	blockQuic      bool
	txBytes        atomic.Uint64
	rxBytes        atomic.Uint64
	activeConns    atomic.Int64
	activeUDPConns atomic.Int64
	lastRxMs       atomic.Int64
	ctx            context.Context
	cancel         context.CancelFunc
	connsMu        sync.Mutex
	conns          map[uint64]*trackedConn
	udpConnsMu     sync.Mutex
	udpConns       map[uint64]net.Conn
	connsSeq       atomic.Uint64
	socksDialFails atomic.Uint64
	quicRejects    atomic.Uint64
	zombieKills    atomic.Uint64
}

// trackedConn is a proxied TCP connection with per-direction activity timestamps
// (Unix ms) used for connection-level idle accounting and zombie detection.
type trackedConn struct {
	app      net.Conn // gVisor side
	proxy    net.Conn // SOCKS side
	dst      string
	createdMs int64
	lastTxMs atomic.Int64 // last payload app → proxy
	lastRxMs atomic.Int64 // last payload proxy → app
}

// idleVerdict reports whether the connection should be closed as idle and
// whether it matched the zombie signature (request sent, upstream silent).
func (tc *trackedConn) idleVerdict(nowMs int64) (expired, zombie bool) {
	tx, rx := tc.lastTxMs.Load(), tc.lastRxMs.Load()
	last := tx
	if rx > last {
		last = rx
	}
	idle := nowMs - last
	if idle >= tcpIdleTimeout.Milliseconds() {
		return true, false
	}
	if tx > rx && idle >= tcpZombieTimeout.Milliseconds() {
		return true, true
	}
	return false, false
}

func NewEngine(tunFD int, mtu int, socksHost string, socksPort int, socksUser, socksPass string, allowICMP, blockQuic bool, hook *EngineHook) (*Engine, error) {
	s := stack.New(stack.Options{
		NetworkProtocols: []stack.NetworkProtocolFactory{
			ipv4.NewProtocol,
			ipv6.NewProtocol,
		},
		TransportProtocols: []stack.TransportProtocolFactory{
			tcp.NewProtocol,
			udp.NewProtocol,
		},
		HandleLocal: false,
	})

	ep := channel.New(channelSize, uint32(mtu), "")

	if tcpipErr := s.CreateNIC(nicID, ep); tcpipErr != nil {
		s.Close()
		return nil, fmt.Errorf("CreateNIC: %v", tcpipErr)
	}

	s.SetRouteTable([]tcpip.Route{
		{Destination: header.IPv4EmptySubnet, NIC: nicID},
		{Destination: header.IPv6EmptySubnet, NIC: nicID},
	})

	s.SetPromiscuousMode(nicID, true)
	s.SetSpoofing(nicID, true)

	// Proxy-mode TCP tuning: aggressively clean up dead state.
	// In a TUN proxy the addressing is virtual, so RFC 793 TIME_WAIT and linger
	// guarantees are meaningless. The defaults (60 s each) cause hundreds of entries
	// to accumulate in gVisor's endpoint table under Doze-mode + reconnect bursts,
	// which over several hours degrades new connection establishment.
	twTimeout := tcpip.TCPTimeWaitTimeoutOption(0) // disable TIME_WAIT entirely
	s.SetTransportProtocolOption(tcp.ProtocolNumber, &twTimeout)
	twReuse := tcpip.TCPTimeWaitReuseOption(tcpip.TCPTimeWaitReuseGlobal)
	s.SetTransportProtocolOption(tcp.ProtocolNumber, &twReuse)
	linger := tcpip.TCPLingerTimeoutOption(time.Second)
	s.SetTransportProtocolOption(tcp.ProtocolNumber, &linger)

	ctx, cancel := context.WithCancel(context.Background())
	e := &Engine{
		stack:    s,
		endpoint: ep,
		hook:     hook,
		mtu:      mtu,
		stopCh:   make(chan struct{}),
		logPrefix: fmt.Sprintf("[teapod-tun2socks fd=%d mtu=%d]", tunFD, mtu),
		allowICMP: allowICMP,
		blockQuic: blockQuic,
		ctx:      ctx,
		cancel:   cancel,
		conns:    make(map[uint64]*trackedConn),
		udpConns: make(map[uint64]net.Conn),
	}

	// Forwarder closures capture e so they can pass e.ctx to SOCKS5 dials,
	// allowing Stop() to cancel in-flight dials immediately via e.cancel().
	tcpForwarder := tcp.NewForwarder(s, 65535, 1024, func(r *tcp.ForwarderRequest) {
		go handleTCPForwarder(e.ctx, r, hook, socksHost, socksPort, socksUser, socksPass, e)
	})
	s.SetTransportProtocolHandler(tcp.ProtocolNumber, tcpForwarder.HandlePacket)

	udpForwarder := udp.NewForwarder(s, func(r *udp.ForwarderRequest) bool {
		// No hook.Validate here: this callback runs synchronously in the packet
		// delivery path (tunReadLoop → InjectInbound). A validation cache miss costs
		// a 20-100ms Kotlin IPC, stalling ALL tunnel traffic — and every DNS query
		// from a fresh ephemeral port is a miss. Validation happens in
		// handleUDPForwarder instead (same as TCP since v1.1.13); denied flows are
		// silently dropped there.

		// Reject new flows once the association cap is reached, so a fan-out burst
		// cannot exhaust file descriptors. The slot is reserved synchronously here
		// (before the goroutine and the slow UDPAssociate dial run) so a burst reads
		// an up-to-date count; a lazy increment inside the goroutine would let
		// hundreds of concurrent dials race past a stale zero. handleUDPForwarder
		// owns the matching decrement for every exit path. Existing flows keep
		// working; the dropped packet makes the app retransmit, and a slot frees up
		// as idle flows expire.
		if e.activeUDPConns.Add(1) > maxUDPConns {
			e.activeUDPConns.Add(-1)
			return false
		}

		go handleUDPForwarder(e.ctx, r, hook, socksHost, socksPort, socksUser, socksPass, mtu, e)
		return true
	})
	s.SetTransportProtocolHandler(udp.ProtocolNumber, udpForwarder.HandlePacket)

	dupFD, err := unix.Dup(tunFD)
	if err != nil {
		s.Close()
		cancel()
		return nil, fmt.Errorf("dup tunFD: %v", err)
	}
	unix.CloseOnExec(dupFD)
	// Put the fd in non-blocking mode so os.File registers it with the runtime
	// poller. Without this, a blocking read() syscall is NOT interrupted by
	// tunFile.Close() in Stop(): tunReadLoop stays parked in the syscall and
	// e.wg.Wait() blocks forever (until an unrelated packet happens to arrive).
	// The Android VpnService fd is blocking by default, so this is required.
	if err := unix.SetNonblock(dupFD, true); err != nil {
		unix.Close(dupFD)
		s.Close()
		cancel()
		return nil, fmt.Errorf("set tunFD nonblock: %v", err)
	}
	e.tunFile = os.NewFile(uintptr(dupFD), "tun")

	return e, nil
}

func (e *Engine) Start() error {
	if !e.running.CompareAndSwap(false, true) {
		return fmt.Errorf("engine already running")
	}
	log.Printf("%s engine started", e.logPrefix)

	e.wg.Add(1)
	go func() {
		defer e.wg.Done()
		e.tunReadLoop()
	}()

	e.wg.Add(1)
	go func() {
		defer e.wg.Done()
		e.tunWriteLoop(e.ctx)
	}()

	<-e.stopCh
	log.Printf("%s engine stopped", e.logPrefix)
	return nil
}

func (e *Engine) tunReadLoop() {
	buf := make([]byte, e.mtu+4)
	for {
		select {
		case <-e.stopCh:
			return
		default:
		}

		n, err := e.tunFile.Read(buf)
		if err != nil {
			if e.running.Load() {
				// TUN fd was closed externally (e.g. Android revoked VPN during a phone call
				// without calling onRevoke). Trigger Stop() so IsRunning() returns false,
				// which the Kotlin heartbeat detects and uses to trigger a reconnect.
				log.Printf("%s TUN read error — fd closed externally, triggering stop: %v", e.logPrefix, err)
				go e.Stop() // must be async: Stop calls wg.Wait which would deadlock if called directly
			}
			return
		}
		if n == 0 {
			continue
		}
		e.txBytes.Add(uint64(n))

		pkt := buf[:n]
		var proto tcpip.NetworkProtocolNumber
		switch pkt[0] >> 4 {
		case 4:
			proto = header.IPv4ProtocolNumber
			// Filter ICMPv4 echo packets when allowICMP is disabled.
			// ICMP has no source ports, so per-app UID lookup is not possible;
			// the filter applies to all apps uniformly.
			if len(pkt) > 9 && pkt[9] == ProtocolICMP {
				if !e.allowICMP {
					if shouldBlockICMP(pkt, false) {
						log.Printf("%s ICMPv4 blocked (echo)", e.logPrefix)
						continue
					}
				} else if resp := buildICMPv4EchoReply(pkt); resp != nil {
					e.writeTun(resp)
					continue
				}
			}
			// Reject QUIC (UDP 443) inline with an ICMP Port Unreachable. Without this,
			// browsers send their full QUIC retransmission sequence (~55s of exponential
			// backoff) before falling back to TCP, during which all HTTP/2 streams to the
			// same host stall in the browser's connection queue.
			if e.blockQuic && isUDPDstPortIPv4(pkt, 443) {
				e.quicRejects.Add(1)
				if resp := buildICMPv4PortUnreachable(pkt); resp != nil {
					e.writeTun(resp)
				}
				continue
			}
		case 6:
			proto = header.IPv6ProtocolNumber
			// Filter ICMPv6 echo packets when allowICMP is disabled. Walk the
			// extension header chain so an echo hidden behind e.g. a Hop-by-Hop
			// header cannot slip past the filter.
			if hdrProto, off, hok := ipv6TransportHeader(pkt); hok && hdrProto == ProtocolICMPv6 {
				if !e.allowICMP {
					if shouldBlockICMPv6(pkt, off) {
						log.Printf("%s ICMPv6 blocked (echo)", e.logPrefix)
						continue
					}
				} else if resp := buildICMPv6EchoReply(pkt, off); resp != nil {
					e.writeTun(resp)
					continue
				}
			}
			if e.blockQuic && isUDPDstPortIPv6(pkt, 443) {
				e.quicRejects.Add(1)
				if resp := buildICMPv6PortUnreachable(pkt); resp != nil {
					e.writeTun(resp)
				}
				continue
			}
		default:
			continue
		}

		pkb := stack.NewPacketBuffer(stack.PacketBufferOptions{
			Payload: buffer.MakeWithData(pkt),
		})
		e.endpoint.InjectInbound(proto, pkb)
		pkb.DecRef()
	}
}

// writeTun writes a locally generated reply (ICMP unreachable / echo reply) to the TUN.
func (e *Engine) writeTun(pkt []byte) {
	if _, err := e.tunFile.Write(pkt); err != nil && e.running.Load() {
		log.Printf("%s TUN reply write failed: %v", e.logPrefix, err)
	}
}

// shouldBlockICMP checks if an ICMPv4 packet should be blocked.
// The ICMP header starts after the IPv4 header (IHL * 4 bytes).
// Blocks Echo Request (type 8) and Echo Reply (type 0) to prevent unauthorized
// apps from using ping to bypass application filters. Allows all other ICMP types
// (error messages like Destination Unreachable, etc.)
func shouldBlockICMP(pkt []byte, isIPv6 bool) bool {
	if isIPv6 {
		// IPv6 callers use shouldBlockICMPv6 with a pre-computed offset instead,
		// because the ICMPv6 header may sit behind extension headers.
		if len(pkt) < 40 {
			return true
		}
		return isICMPEchoType(pkt[40])
	}
	if len(pkt) < 20 {
		return true // Malformed packet
	}
	// IPv4 IHL is in bits 4-7 of byte 0, in 32-bit words
	ihl := int(pkt[0]&0x0F) * 4
	if len(pkt) < ihl+1 {
		return true // Malformed packet
	}
	return isICMPEchoType(pkt[ihl])
}

// shouldBlockICMPv6 reports whether the ICMPv6 message beginning at icmpOffset is
// an Echo Request/Reply that should be blocked. icmpOffset is the offset returned
// by ipv6TransportHeader, i.e. past any extension headers.
func shouldBlockICMPv6(pkt []byte, icmpOffset int) bool {
	if len(pkt) < icmpOffset+1 {
		return true // Malformed/truncated — block to be safe
	}
	return isICMPEchoType(pkt[icmpOffset])
}

// isICMPEchoType reports whether an ICMP type byte is an Echo Request or Reply.
//
//	IPv4: Echo Request = 8, Echo Reply = 0
//	IPv6: Echo Request = 128, Echo Reply = 129
func isICMPEchoType(icmpType byte) bool {
	return icmpType == 0 || icmpType == 8 || icmpType == 128 || icmpType == 129
}

func (e *Engine) tunWriteLoop(ctx context.Context) {
	for {
		pkt := e.endpoint.ReadContext(ctx)
		if pkt == nil {
			return
		}
		v := pkt.ToView()
		data := v.AsSlice()
		if _, err := e.tunFile.Write(data); err != nil {
			if e.running.Load() {
				log.Printf("%s TUN write: %v", e.logPrefix, err)
			}
		} else {
			e.rxBytes.Add(uint64(len(data)))
			e.lastRxMs.Store(time.Now().UnixMilli())
		}
		v.Release()
		pkt.DecRef()
	}
}

func (e *Engine) Stop() {
	if !e.running.CompareAndSwap(true, false) {
		return
	}
	e.cancel() // unblock any in-flight SOCKS5 DialContext in forwarder goroutines
	close(e.stopCh)
	e.tunFile.Close()
	e.stack.Close()
	e.wg.Wait()
	log.Printf("%s engine shut down complete", e.logPrefix)
}

func (e *Engine) IsRunning() bool    { return e.running.Load() }
func (e *Engine) ActiveConns() int64 { return e.activeConns.Load() + e.activeUDPConns.Load() }
func (e *Engine) LastRxMs() int64    { return e.lastRxMs.Load() }

func (e *Engine) trackConn(id uint64, tc *trackedConn) {
	e.connsMu.Lock()
	e.conns[id] = tc
	e.connsMu.Unlock()
}

func (e *Engine) untrackConn(id uint64) {
	e.connsMu.Lock()
	delete(e.conns, id)
	e.connsMu.Unlock()
}

func (e *Engine) trackUDPConn(id uint64, c net.Conn) {
	e.udpConnsMu.Lock()
	e.udpConns[id] = c
	e.udpConnsMu.Unlock()
}

func (e *Engine) untrackUDPConn(id uint64) {
	e.udpConnsMu.Lock()
	delete(e.udpConns, id)
	e.udpConnsMu.Unlock()
}

// CloseAllConnections closes the gVisor side of every active proxied TCP and UDP
// connection. Each goroutine pair detects the close and exits, causing apps to
// receive a reset and reconnect. Returns the total number of connections closed.
func (e *Engine) CloseAllConnections() int {
	e.connsMu.Lock()
	tcpSnap := make([]net.Conn, 0, len(e.conns))
	for _, tc := range e.conns {
		tcpSnap = append(tcpSnap, tc.app)
	}
	e.connsMu.Unlock()

	e.udpConnsMu.Lock()
	udpSnap := make([]net.Conn, 0, len(e.udpConns))
	for _, c := range e.udpConns {
		udpSnap = append(udpSnap, c)
	}
	e.udpConnsMu.Unlock()

	for _, c := range tcpSnap {
		c.Close()
	}
	for _, c := range udpSnap {
		c.Close()
	}
	return len(tcpSnap) + len(udpSnap)
}

// StatsLine returns a single diagnostic string with key tunnel health metrics:
//   - tcpConns/udpConns — active TCP and UDP proxy goroutines
//   - gvisorEstab       — gVisor TCP endpoints in ESTABLISHED state
//   - gvisorConn        — gVisor TCP endpoints counted as "connected"
//   - chanQueued        — packets buffered in the gVisor→TUN channel (capacity: channelSize)
//   - txMB/rxMB         — cumulative bytes through TUN since start
//
// Useful for detecting: goroutine leaks (tcpConns/udpConns spike), channel overflow
// (chanQueued near 4096), or gVisor endpoint table bloat (gvisorEstab >> tcpConns).
func (e *Engine) StatsLine(cacheLen int) string {
	stats := e.stack.Stats()
	return fmt.Sprintf("tcpConns=%d udpConns=%d gvisorEstab=%d gvisorConn=%d chanQueued=%d/%d txMB=%.1f rxMB=%.1f cacheEntries=%d dialFails=%d quicRej=%d zombies=%d",
		e.activeConns.Load(),
		e.activeUDPConns.Load(),
		stats.TCP.CurrentEstablished.Value(),
		stats.TCP.CurrentConnected.Value(),
		e.endpoint.NumQueued(), channelSize,
		float64(e.txBytes.Load())/1e6,
		float64(e.rxBytes.Load())/1e6,
		cacheLen,
		e.socksDialFails.Load(),
		e.quicRejects.Load(),
		e.zombieKills.Load(),
	)
}

// Diagnostics returns a JSON snapshot of the tunnel state for on-device debugging:
// health metrics, failure counters and the per-connection activity table (dst,
// age, per-direction idle). Intended for a "tunnel snapshot" action in the app UI.
func (e *Engine) Diagnostics(cacheLen int) string {
	type connDiag struct {
		Dst       string `json:"dst"`
		AgeSec    int64  `json:"ageSec"`
		TxIdleSec int64  `json:"txIdleSec"`
		RxIdleSec int64  `json:"rxIdleSec"`
	}
	now := time.Now().UnixMilli()

	e.connsMu.Lock()
	conns := make([]connDiag, 0, len(e.conns))
	for _, tc := range e.conns {
		if len(conns) >= 200 {
			break
		}
		conns = append(conns, connDiag{
			Dst:       tc.dst,
			AgeSec:    (now - tc.createdMs) / 1000,
			TxIdleSec: (now - tc.lastTxMs.Load()) / 1000,
			RxIdleSec: (now - tc.lastRxMs.Load()) / 1000,
		})
	}
	e.connsMu.Unlock()

	stats := e.stack.Stats()
	snapshot := map[string]any{
		"tcpConns":    e.activeConns.Load(),
		"udpConns":    e.activeUDPConns.Load(),
		"gvisorEstab": stats.TCP.CurrentEstablished.Value(),
		"chanQueued":  e.endpoint.NumQueued(),
		"txBytes":     e.txBytes.Load(),
		"rxBytes":     e.rxBytes.Load(),
		"lastRxSec":   (now - e.lastRxMs.Load()) / 1000,
		"cacheLen":    cacheLen,
		"dialFails":   e.socksDialFails.Load(),
		"quicRejects": e.quicRejects.Load(),
		"zombieKills": e.zombieKills.Load(),
		"conns":       conns,
	}
	b, err := json.Marshal(snapshot)
	if err != nil {
		return fmt.Sprintf(`{"error":%q}`, err.Error())
	}
	return string(b)
}

// LogStats writes StatsLine to Go's standard logger (→ Android logcat tag "GoLog").
// For routing into vpn_log.txt and Flutter UI, use StatsLine() from Kotlin instead.
func (e *Engine) LogStats(cacheLen int) {
	log.Printf("%s tunnel stats: %s", e.logPrefix, e.StatsLine(cacheLen))
}

func handleTCPForwarder(ctx context.Context, req *tcp.ForwarderRequest, hook *EngineHook, socksHost string, socksPort int, socksUser, socksPass string, e *Engine) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[teapod-tun2socks] panic in TCP forwarder: %v", r)
		}
	}()
	id := req.ID()
	// gVisor Forwarder:
	// RemoteAddress is the Source (Phone).
	// LocalAddress is the Destination (Internet).
	srcIP := net.IP(id.RemoteAddress.AsSlice())
	dstIP := net.IP(id.LocalAddress.AsSlice())
	srcPort := id.RemotePort
	dstPort := id.LocalPort

	// Complete the 3-way handshake first so Chrome's SYN is ACK'd immediately.
	// Validate after: the IPC call to Kotlin can take 20-100ms per connection and
	// serialises on the Android side when many connections arrive simultaneously.
	// If we validated before CreateEndpoint, Chrome's SYN-retransmit (at ~1s) would
	// arrive while the ForwarderRequest is still pending, causing gVisor to RST it.
	var wq waiter.Queue
	ep, tcpipErr := req.CreateEndpoint(&wq)
	if tcpipErr != nil {
		req.Complete(true)
		return
	}
	// Remove the request from the forwarder's inFlight table (gVisor API contract:
	// "Clients must eventually call Complete()"; CreateEndpoint does NOT do it).
	// Without this every connection leaks one inFlight entry; after maxInFlight
	// (1024) leaked entries gVisor silently drops every new SYN — the tunnel looks
	// alive (heartbeat bypasses TUN) but no new TCP connection can be established.
	req.Complete(false)

	ep.SocketOptions().SetKeepAlive(false)
	gonetConn := gonet.NewTCPConn(&wq, ep)

	if allowed, _ := hook.Validate(srcIP, srcPort, dstIP, dstPort, uint8(ProtocolTCP)); !allowed {
		gonetConn.Close()
		return
	}

	dialStart := time.Now()
	proxyConn, dialErr := NewSOCKS5Client(socksHost, socksPort, socksUser, socksPass).
		DialTCP(ctx, dstIP.String(), int(dstPort))
	if dialErr != nil {
		e.socksDialFails.Add(1)
		log.Printf("[teapod-tun2socks] SOCKS5 dial %s:%d failed after %dms: %v", dstIP, dstPort, time.Since(dialStart).Milliseconds(), dialErr)
		gonetConn.Close()
		return
	}

	nowMs := time.Now().UnixMilli()
	tc := &trackedConn{
		app:       gonetConn,
		proxy:     proxyConn,
		dst:       fmt.Sprintf("%s:%d", dstIP, dstPort),
		createdMs: nowMs,
	}
	tc.lastTxMs.Store(nowMs)
	tc.lastRxMs.Store(nowMs)

	connID := e.connsSeq.Add(1)
	e.trackConn(connID, tc)
	e.activeConns.Add(1)
	go func() {
		defer e.activeConns.Add(-1)
		defer e.untrackConn(connID)
		pipeConnections(tc, e)
	}()
}

func handleUDPForwarder(ctx context.Context, req *udp.ForwarderRequest, hook *EngineHook, socksHost string, socksPort int, socksUser, socksPass string, mtu int, e *Engine) {
	// The forwarder callback reserved one activeUDPConns slot before launching us;
	// release it on every exit path (early failure or, via pipeUDP, flow teardown).
	defer e.activeUDPConns.Add(-1)
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[teapod-tun2socks] panic in UDP forwarder: %v", r)
		}
	}()
	id := req.ID()
	srcIP := net.IP(id.RemoteAddress.AsSlice())
	dstIP := net.IP(id.LocalAddress.AsSlice())
	dstPort := id.LocalPort

	var wq waiter.Queue
	ep, tcpipErr := req.CreateEndpoint(&wq)
	if tcpipErr != nil {
		return
	}

	gonetConn := gonet.NewUDPConn(&wq, ep)

	// Validate off the packet path (see the forwarder callback for why).
	if allowed, _ := hook.Validate(srcIP, id.RemotePort, dstIP, dstPort, uint8(ProtocolUDP)); !allowed {
		gonetConn.Close()
		return
	}

	socks := NewSOCKS5Client(socksHost, socksPort, socksUser, socksPass)
	assoc, err := socks.UDPAssociate(ctx)
	if err != nil {
		e.socksDialFails.Add(1)
		log.Printf("[teapod-tun2socks] UDP ASSOCIATE failed for %s:%d: %v", dstIP, dstPort, err)
		gonetConn.Close()
		return
	}

	connID := e.connsSeq.Add(1)
	e.trackUDPConn(connID, gonetConn)
	defer e.untrackUDPConn(connID)
	// Run the relay inline: handleUDPForwarder is already its own goroutine, and
	// keeping it on the stack ties the reserved slot's lifetime to the live flow.
	pipeUDP(gonetConn, assoc, dstIP, int(dstPort), mtu)
}

func pipeUDP(gonetConn *gonet.UDPConn, assoc *UDPAssociation, dstIP net.IP, dstPort int, mtu int) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[teapod-tun2socks] panic in pipeUDP: %v", r)
		}
	}()
	// shutdown closes both ends exactly once, unblocking whichever goroutine is
	// still blocked on a read. Each goroutine calls defer shutdown() so that when
	// either side exits (error, idle timeout, or upstream close) the other side is
	// guaranteed to unblock and exit immediately.
	var once sync.Once
	shutdown := func() {
		once.Do(func() {
			gonetConn.Close()
			assoc.Close()
		})
	}
	defer shutdown()

	// Monitor the SOCKS5 control TCP connection: if xray closes it, tear down the relay
	// immediately instead of waiting for the 60-second UDP idle timeout. This handles
	// the case where xray drops the UDP ASSOCIATE (restart, resource pressure, etc.)
	// without us noticing — without this, pipeUDP hangs for up to 60s while the app
	// waits for responses that will never arrive.
	go func() {
		defer shutdown()
		io.Copy(io.Discard, assoc.ctrl)
	}()

	var wg sync.WaitGroup
	wg.Add(2)

	// TUN -> relay: read from gVisor endpoint, forward to SOCKS5 UDP relay.
	go func() {
		defer wg.Done()
		defer shutdown()
		buf := make([]byte, mtu)
		for {
			// Idle-based deadline: reset before every read so the timeout only fires
			// when no packet has arrived for udpIdleTimeout, not after an absolute time.
			gonetConn.SetReadDeadline(time.Now().Add(udpIdleTimeout))
			n, err := gonetConn.Read(buf)
			if err != nil {
				return
			}
			datagram := EncodeUDPDatagram(dstIP, dstPort, buf[:n])
			if _, err := assoc.UDPConn.WriteToUDP(datagram, assoc.RelayAddr); err != nil {
				return
			}
		}
	}()

	// relay -> TUN: read responses from SOCKS5 UDP relay, forward to gVisor endpoint.
	go func() {
		defer wg.Done()
		defer shutdown()
		buf := make([]byte, mtu+22)
		for {
			assoc.UDPConn.SetReadDeadline(time.Now().Add(udpIdleTimeout))
			n, from, err := assoc.UDPConn.ReadFromUDP(buf)
			if err != nil {
				return
			}
			// Only accept datagrams from the SOCKS5 relay we associated with.
			// The local UDP socket is bound to 127.0.0.1; without this check any
			// other app on the device could send a spoofed SOCKS5 datagram to the
			// ephemeral port and have its payload delivered to the app as a genuine
			// network response (e.g. forged DNS answers bypassing the tunnel).
			if from == nil || !from.IP.Equal(assoc.RelayAddr.IP) || from.Port != assoc.RelayAddr.Port {
				continue
			}
			_, _, payload, err := DecodeUDPDatagram(buf[:n])
			if err != nil {
				log.Printf("[teapod-tun2socks] UDP datagram dropped: %v", err)
				continue
			}
			if _, err := gonetConn.Write(payload); err != nil {
				return
			}
		}
	}()

	wg.Wait()
}

func pipeConnections(tc *trackedConn, e *Engine) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[teapod-tun2socks] panic in pipeConnections: %v", r)
		}
	}()
	// shutdown closes both ends exactly once, unblocking whichever goroutine is
	// still blocked on a read — same pattern as pipeUDP.
	var once sync.Once
	shutdown := func() {
		once.Do(func() {
			tc.app.Close()
			tc.proxy.Close()
		})
	}
	defer shutdown()

	var wg sync.WaitGroup
	wg.Add(2)

	// pipe copies src → dst, stamping per-direction activity. Read deadlines wake
	// every tcpIdleCheckStep to re-evaluate CONNECTION-level idle state: a flow dies
	// when both directions were silent for tcpIdleTimeout, or after tcpZombieTimeout
	// when the app sent a request and the upstream never replied (zombie: mid-stream
	// upstream reset whose close was lost). A one-directional transfer (long download)
	// keeps the flow alive — the old per-direction deadline killed those at 5 min.
	//
	// EOF is a half-close: the FIN is passed on and the other direction keeps
	// running, so a request followed by shutdown(SHUT_WR) still gets its response.
	// Closing both ends here lost it. The half-open state is bounded by xray's
	// uplinkOnly/downlinkOnly policy and by the idle checks above. Any other error
	// tears the whole flow down.
	pipe := func(dst, src net.Conn, touched *atomic.Int64) {
		defer wg.Done()
		bufPtr := tcpBufPool.Get().(*[]byte)
		buf := *bufPtr
		defer tcpBufPool.Put(bufPtr)
		for {
			src.SetReadDeadline(time.Now().Add(tcpIdleCheckStep))
			n, err := src.Read(buf)
			if n > 0 {
				touched.Store(time.Now().UnixMilli())
				dst.SetWriteDeadline(time.Now().Add(tcpIdleTimeout))
				if _, werr := dst.Write(buf[:n]); werr != nil {
					shutdown()
					return
				}
			}
			if err != nil {
				if ne, ok := err.(net.Error); ok && ne.Timeout() {
					expired, zombie := tc.idleVerdict(time.Now().UnixMilli())
					if !expired {
						continue
					}
					if zombie {
						e.zombieKills.Add(1)
						log.Printf("[teapod-tun2socks] zombie conn to %s closed (request sent, upstream silent %ds)",
							tc.dst, tcpZombieTimeout.Milliseconds()/1000)
					}
				} else if errors.Is(err, io.EOF) {
					if cw, ok := dst.(interface{ CloseWrite() error }); ok && cw.CloseWrite() == nil {
						return
					}
				}
				shutdown()
				return
			}
		}
	}

	go pipe(tc.proxy, tc.app, &tc.lastTxMs)
	go pipe(tc.app, tc.proxy, &tc.lastRxMs)
	wg.Wait()
}
