//go:build with_gvisor

// Adapted from sing-box v1.14.4 transport/wireguard/device_stack.go and device_stack_gonet.go.
// SPDX-License-Identifier: GPL-3.0-or-later

package awg

import (
	"context"
	"errors"
	"fmt"
	"github.com/sagernet/gvisor/pkg/tcpip/transport/tcp"
	"github.com/sagernet/gvisor/pkg/waiter"
	"net"
	"net/netip"
	"os"
	"sync"
	"time"

	wgTun "github.com/amnezia-vpn/amneziawg-go/v3/tun"
	"github.com/sagernet/gvisor/pkg/buffer"
	"github.com/sagernet/gvisor/pkg/tcpip"
	"github.com/sagernet/gvisor/pkg/tcpip/adapters/gonet"
	"github.com/sagernet/gvisor/pkg/tcpip/header"
	"github.com/sagernet/gvisor/pkg/tcpip/network/ipv4"
	"github.com/sagernet/gvisor/pkg/tcpip/network/ipv6"
	"github.com/sagernet/gvisor/pkg/tcpip/stack"
	"github.com/sagernet/sing-tun"
	"github.com/sagernet/sing/common/buf"
	E "github.com/sagernet/sing/common/exceptions"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
)

var _ wgTun.Device = (*stackDevice)(nil)

type stackDevice struct {
	stack          *stack.Stack
	mtu            uint32
	events         chan wgTun.Event
	outbound       chan *stack.PacketBuffer
	packetOutbound chan *buf.Buffer
	done           chan struct{}
	wake           chan struct{}
	// A packet taken while a wake was pending, returned by the next Read
	// (only the single TUN reader goroutine touches these).
	heldPacket    *stack.PacketBuffer
	heldBuffer    *buf.Buffer
	closeOnce     sync.Once
	dispatcher    stack.NetworkDispatcher
	inet4Address  netip.Addr
	inet6Address  netip.Addr
	icmpForwarder *tun.ICMPForwarder
	udpForwarder  *tun.UDPForwarder
}

func newStackDevice(mtu uint32, address []netip.Prefix) (*stackDevice, error) {
	tunDevice := &stackDevice{
		mtu:            mtu,
		events:         make(chan wgTun.Event, 1),
		outbound:       make(chan *stack.PacketBuffer, 256),
		packetOutbound: make(chan *buf.Buffer, 256),
		done:           make(chan struct{}),
		wake:           make(chan struct{}, 1),
	}
	ipStack, err := tun.NewGVisorStackWithOptions((*wireEndpoint)(tunDevice), stack.NICOptions{}, true)
	if err != nil {
		return nil, err
	}
	for _, prefix := range address {
		addr := tun.AddressFromAddr(prefix.Addr())
		protoAddr := tcpip.ProtocolAddress{
			AddressWithPrefix: tcpip.AddressWithPrefix{
				Address:   addr,
				PrefixLen: prefix.Bits(),
			},
		}
		if prefix.Addr().Is4() {
			tunDevice.inet4Address = prefix.Addr()
			protoAddr.Protocol = ipv4.ProtocolNumber
		} else {
			tunDevice.inet6Address = prefix.Addr()
			protoAddr.Protocol = ipv6.ProtocolNumber
		}
		gErr := ipStack.AddProtocolAddress(tun.DefaultNIC, protoAddr, stack.AddressProperties{})
		if gErr != nil {
			// The stack already runs its TCP processor goroutines.
			ipStack.Close()
			ipStack.Wait()
			return nil, E.New("parse local address ", protoAddr.AddressWithPrefix, ": ", gErr.String())
		}
	}
	tunDevice.stack = ipStack
	return tunDevice, nil
}

func (w *stackDevice) DialContext(ctx context.Context, network string, destination M.Socksaddr) (net.Conn, error) {
	addr := tcpip.FullAddress{
		NIC:  tun.DefaultNIC,
		Port: destination.Port,
		Addr: tun.AddressFromAddr(destination.Addr),
	}
	bind := tcpip.FullAddress{
		NIC: tun.DefaultNIC,
	}
	var networkProtocol tcpip.NetworkProtocolNumber
	if destination.IsIPv4() {
		if !w.inet4Address.IsValid() {
			return nil, E.New("missing IPv4 local address")
		}
		networkProtocol = header.IPv4ProtocolNumber
		bind.Addr = tun.AddressFromAddr(w.inet4Address)
	} else {
		if !w.inet6Address.IsValid() {
			return nil, E.New("missing IPv6 local address")
		}
		networkProtocol = header.IPv6ProtocolNumber
		bind.Addr = tun.AddressFromAddr(w.inet6Address)
	}
	switch N.NetworkName(network) {
	case N.NetworkTCP:
		tcpConn, err := dialTCPWithBind(ctx, w.stack, bind, addr, networkProtocol)
		if err != nil {
			return nil, err
		}
		return tcpConn, nil
	case N.NetworkUDP:
		udpConn, err := gonet.DialUDP(w.stack, &bind, &addr, networkProtocol)
		if err != nil {
			return nil, err
		}
		return udpConn, nil
	default:
		return nil, E.Extend(N.ErrUnknownNetwork, network)
	}
}

func (w *stackDevice) ListenPacket(ctx context.Context, destination M.Socksaddr) (net.PacketConn, error) {
	bind := tcpip.FullAddress{
		NIC: tun.DefaultNIC,
	}
	var networkProtocol tcpip.NetworkProtocolNumber
	if destination.IsIPv4() {
		if !w.inet4Address.IsValid() {
			return nil, E.New("missing IPv4 local address")
		}
		networkProtocol = header.IPv4ProtocolNumber
		bind.Addr = tun.AddressFromAddr(w.inet4Address)
	} else {
		if !w.inet6Address.IsValid() {
			return nil, E.New("missing IPv6 local address")
		}
		networkProtocol = header.IPv6ProtocolNumber
		bind.Addr = tun.AddressFromAddr(w.inet6Address)
	}
	udpConn, err := gonet.DialUDP(w.stack, &bind, nil, networkProtocol)
	if err != nil {
		return nil, err
	}
	return udpConn, nil
}

func (w *stackDevice) Inet4Address() netip.Addr {
	return w.inet4Address
}

func (w *stackDevice) Inet6Address() netip.Addr {
	return w.inet6Address
}

func (w *stackDevice) Start() error {
	if w.udpForwarder != nil {
		err := w.udpForwarder.Start()
		if err != nil {
			return err
		}
	}
	w.events <- wgTun.EventUp
	return nil
}

func (w *stackDevice) File() *os.File {
	return nil
}

func (w *stackDevice) Read(bufs [][]byte, sizes []int, offset int) (count int, err error) {
	// A pending wake goes first: the caller computed the S4 offset before Read, and a packet
	// returned now would go out with the old offset.
	select {
	case <-w.wake:
		return 0, nil
	default:
	}
	if w.heldPacket == nil && w.heldBuffer == nil {
		select {
		case packet, ok := <-w.outbound:
			if !ok {
				return 0, os.ErrClosed
			}
			w.heldPacket = packet
		case packet := <-w.packetOutbound:
			w.heldBuffer = packet
		case <-w.wake:
			return 0, nil
		case <-w.done:
			return 0, os.ErrClosed
		}
		// A wake that came while this Read waited goes first too; the packet is kept for
		// the next Read, which runs with the new offset.
		select {
		case <-w.wake:
			return 0, nil
		default:
		}
	}
	if packet := w.heldPacket; packet != nil {
		w.heldPacket = nil
		defer packet.DecRef()
		var copyN int
		for _, view := range packet.AsSlices() {
			copyN += copy(bufs[0][offset+copyN:], view)
		}
		sizes[0] = copyN
		return 1, nil
	}
	packet := w.heldBuffer
	w.heldBuffer = nil
	defer packet.Release()
	sizes[0] = copy(bufs[0][offset:], packet.Bytes())
	return 1, nil
}

// Reconfigured wakes Read: the amneziawg-go TUN reader starts in NewDevice and blocks
// with the S4 offset as of the start (0). Without a wake-up the first packet after IpcSet goes out
// without S4 padding and is dropped by the server (UDP is lost: the first DNS query waited 10 s).
func (w *stackDevice) Reconfigured() {
	select {
	case w.wake <- struct{}{}:
	default:
	}
}

func (w *stackDevice) Write(bufs [][]byte, offset int) (count int, err error) {
	for _, b := range bufs {
		b = b[offset:]
		if len(b) == 0 {
			continue
		}
		var networkProtocol tcpip.NetworkProtocolNumber
		switch header.IPVersion(b) {
		case header.IPv4Version:
			networkProtocol = header.IPv4ProtocolNumber
		case header.IPv6Version:
			networkProtocol = header.IPv6ProtocolNumber
		}
		packetBuffer := stack.NewPacketBuffer(stack.PacketBufferOptions{
			Payload: buffer.MakeWithData(b),
		})
		w.dispatcher.DeliverNetworkPacket(networkProtocol, packetBuffer)
		packetBuffer.DecRef()
		count++
	}
	return
}

func (w *stackDevice) Flush() error {
	return nil
}

func (w *stackDevice) MTU() (int, error) {
	return int(w.mtu), nil
}

func (w *stackDevice) Name() (string, error) {
	return "sing-box", nil
}

func (w *stackDevice) Events() <-chan wgTun.Event {
	return w.events
}

func (w *stackDevice) Close() error {
	w.closeOnce.Do(func() {
		close(w.done)
		close(w.events)
		if w.icmpForwarder != nil {
			w.icmpForwarder.Close()
		}
		if w.udpForwarder != nil {
			_ = w.udpForwarder.Close()
		}
		w.stack.Close()
		for _, endpoint := range w.stack.CleanupEndpoints() {
			endpoint.Abort()
		}
		w.stack.Wait()
	})
	return nil
}

func (w *stackDevice) BatchSize() int {
	return 1
}

var _ stack.LinkEndpoint = (*wireEndpoint)(nil)

type wireEndpoint stackDevice

func (ep *wireEndpoint) MTU() uint32 {
	return ep.mtu
}

func (ep *wireEndpoint) SetMTU(mtu uint32) {
}

func (ep *wireEndpoint) MaxHeaderLength() uint16 {
	return 0
}

func (ep *wireEndpoint) LinkAddress() tcpip.LinkAddress {
	return ""
}

func (ep *wireEndpoint) SetLinkAddress(addr tcpip.LinkAddress) {
}

func (ep *wireEndpoint) Capabilities() stack.LinkEndpointCapabilities {
	return stack.CapabilityRXChecksumOffload
}

func (ep *wireEndpoint) Attach(dispatcher stack.NetworkDispatcher) {
	ep.dispatcher = dispatcher
}

func (ep *wireEndpoint) IsAttached() bool {
	return ep.dispatcher != nil
}

func (ep *wireEndpoint) Wait() {
}

func (ep *wireEndpoint) ARPHardwareType() header.ARPHardwareType {
	return header.ARPHardwareNone
}

func (ep *wireEndpoint) AddHeader(buffer *stack.PacketBuffer) {
}

func (ep *wireEndpoint) ParseHeader(ptr *stack.PacketBuffer) bool {
	return true
}

func (ep *wireEndpoint) WritePackets(list stack.PacketBufferList) (int, tcpip.Error) {
	for _, packetBuffer := range list.AsSlice() {
		packetBuffer.IncRef()
		select {
		case <-ep.done:
			return 0, &tcpip.ErrClosedForSend{}
		case ep.outbound <- packetBuffer:
		}
	}
	return list.Len(), nil
}

func (ep *wireEndpoint) Close() {
}

func (ep *wireEndpoint) SetOnCloseAction(f func()) {
}

func dialTCPWithBind(ctx context.Context, s *stack.Stack, localAddr, remoteAddr tcpip.FullAddress, network tcpip.NetworkProtocolNumber) (*gonet.TCPConn, error) {
	// Create TCP endpoint, then connect.
	var wq waiter.Queue
	ep, err := s.NewEndpoint(tcp.ProtocolNumber, network, &wq)
	if err != nil {
		return nil, errors.New(err.String())
	}

	// Create wait queue entry that notifies a channel.
	//
	// We do this unconditionally as Connect will always return an error.
	waitEntry, notifyCh := waiter.NewChannelEntry(waiter.WritableEvents)
	wq.EventRegister(&waitEntry)
	defer wq.EventUnregister(&waitEntry)

	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	default:
	}

	// Bind before connect if requested.
	if localAddr != (tcpip.FullAddress{}) {
		if err = ep.Bind(localAddr); err != nil {
			return nil, fmt.Errorf("ep.Bind(%+v) = %s", localAddr, err)
		}
	}

	err = ep.Connect(remoteAddr)
	if _, ok := err.(*tcpip.ErrConnectStarted); ok {
		select {
		case <-ctx.Done():
			ep.Close()
			return nil, ctx.Err()
		case <-notifyCh:
		}

		err = ep.LastError()
	}
	if err != nil {
		ep.Close()
		return nil, &net.OpError{
			Op:   "connect",
			Net:  "tcp",
			Addr: M.SocksaddrFromNetIP(netip.AddrPortFrom(tun.AddrFromAddress(remoteAddr.Addr), remoteAddr.Port)).TCPAddr(),
			Err:  errors.New(err.String()),
		}
	}

	// sing-box added: set keepalive
	ep.SocketOptions().SetKeepAlive(true)
	keepAliveIdle := tcpip.KeepaliveIdleOption(15 * time.Second)
	ep.SetSockOpt(&keepAliveIdle)
	keepAliveInterval := tcpip.KeepaliveIntervalOption(15 * time.Second)
	ep.SetSockOpt(&keepAliveInterval)

	return gonet.NewTCPConn(&wq, ep), nil
}
