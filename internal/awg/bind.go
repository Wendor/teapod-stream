// Adapted from sing-box v1.14.4 transport/wireguard/client_bind.go.
// SPDX-License-Identifier: GPL-3.0-or-later

package awg

import (
	"context"
	"net"
	"net/netip"
	"sync"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/v3/conn"
	"github.com/sagernet/sing/common"
	"github.com/sagernet/sing/common/bufio"
	E "github.com/sagernet/sing/common/exceptions"
	"github.com/sagernet/sing/common/logger"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
	"github.com/sagernet/sing/service"
	"github.com/sagernet/sing/service/pause"
)

var _ conn.Bind = (*clientBind)(nil)

// clientBind — a UDP socket to the single peer (connect mode). Unlike
// the original, packet bytes 1–3 aren't touched: in AWG they hold the H1–H4 header, not reserved.
type clientBind struct {
	ctx          context.Context
	logger       logger.Logger
	pauseManager pause.Manager
	bindCtx      context.Context
	bindDone     context.CancelFunc
	dialer       N.Dialer
	server       M.Socksaddr
	connAccess   sync.Mutex
	conn         *wireConn
	done         chan struct{}
}

func newClientBind(ctx context.Context, logger logger.Logger, dialer N.Dialer, server M.Socksaddr) *clientBind {
	return &clientBind{
		ctx:          ctx,
		logger:       logger,
		pauseManager: service.FromContext[pause.Manager](ctx),
		dialer:       dialer,
		server:       server,
		done:         make(chan struct{}),
	}
}

func (c *clientBind) connect() (*wireConn, error) {
	c.connAccess.Lock()
	defer c.connAccess.Unlock()
	select {
	case <-c.done:
		return nil, net.ErrClosed
	default:
	}
	if c.conn != nil {
		select {
		case <-c.conn.done:
		default:
			return c.conn, nil
		}
	}
	udpConn, err := c.dialer.DialContext(c.bindCtx, N.NetworkUDP, c.server)
	if err != nil {
		return nil, err
	}
	c.conn = &wireConn{PacketConn: bufio.NewUnbindPacketConn(udpConn), done: make(chan struct{})}
	return c.conn, nil
}

func (c *clientBind) Open(port uint16) (fns []conn.ReceiveFunc, actualPort uint16, err error) {
	select {
	case <-c.done:
		c.done = make(chan struct{})
	default:
	}
	c.bindCtx, c.bindDone = context.WithCancel(c.ctx)
	return []conn.ReceiveFunc{c.receive}, 0, nil
}

func (c *clientBind) receive(packets [][]byte, sizes []int, eps []conn.Endpoint) (count int, err error) {
	udpConn, err := c.connect()
	if err != nil {
		select {
		case <-c.done:
			return
		default:
		}
		c.logger.Error(E.Cause(err, "connect to server"))
		err = nil
		if c.pauseManager != nil {
			c.pauseManager.WaitActiveContext(c.bindCtx)
		}
		select {
		case <-c.done:
		case <-time.After(time.Second):
		}
		return
	}
	n, addr, err := udpConn.ReadFrom(packets[0])
	if err != nil {
		udpConn.Close()
		select {
		case <-c.done:
		default:
			c.logger.Error(E.Cause(err, "read packet"))
			err = nil
		}
		return
	}
	sizes[0] = n
	eps[0] = remoteEndpoint(M.SocksaddrFromNet(addr).Unwrap().AddrPort())
	count = 1
	return
}

func (c *clientBind) Close() error {
	select {
	case <-c.done:
	default:
		close(c.done)
	}
	if c.bindDone != nil {
		c.bindDone()
	}
	c.connAccess.Lock()
	defer c.connAccess.Unlock()
	common.Close(common.PtrOrNil(c.conn))
	return nil
}

func (c *clientBind) SetMark(mark uint32) error {
	return nil
}

// Send writes to the connected socket: the ep address doesn't matter (connect mode).
func (c *clientBind) Send(bufs [][]byte, ep conn.Endpoint) error {
	udpConn, err := c.connect()
	if err != nil {
		time.Sleep(time.Second)
		return err
	}
	destination := netip.AddrPort(ep.(remoteEndpoint))
	for _, b := range bufs {
		if _, err = udpConn.WriteTo(b, M.SocksaddrFromNetIP(destination).UDPAddr()); err != nil {
			udpConn.Close()
			return err
		}
	}
	return nil
}

func (c *clientBind) ParseEndpoint(s string) (conn.Endpoint, error) {
	ap, err := netip.ParseAddrPort(s)
	if err != nil {
		return nil, err
	}
	return remoteEndpoint(ap), nil
}

func (c *clientBind) BatchSize() int {
	return 1
}

type wireConn struct {
	net.PacketConn
	access sync.Mutex
	done   chan struct{}
}

func (w *wireConn) Close() error {
	w.access.Lock()
	defer w.access.Unlock()
	select {
	case <-w.done:
		return net.ErrClosed
	default:
	}
	w.PacketConn.Close()
	close(w.done)
	return nil
}

var _ conn.Endpoint = (*remoteEndpoint)(nil)

type remoteEndpoint netip.AddrPort

func (e remoteEndpoint) ClearSrc() {}

func (e remoteEndpoint) SrcToString() string { return "" }

func (e remoteEndpoint) DstToString() string { return netip.AddrPort(e).String() }

func (e remoteEndpoint) DstToBytes() []byte {
	b, _ := netip.AddrPort(e).MarshalBinary()
	return b
}

func (e remoteEndpoint) DstIP() netip.Addr { return netip.AddrPort(e).Addr() }

func (e remoteEndpoint) SrcIP() netip.Addr { return netip.Addr{} }
